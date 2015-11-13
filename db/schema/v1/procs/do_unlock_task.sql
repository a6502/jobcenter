CREATE OR REPLACE FUNCTION jobcenter.do_unlock_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_vars jsonb;
	v_action_id int;
	v_inargs jsonb;
	v_locktype text;
	v_lockvalue text;
	v_contended boolean;
	v_waitjob_id bigint;
	v_waittask_id int;
	v_waitworkflow_id int;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, variables, action_id INTO v_args, v_vars, v_action_id
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_job_id
		AND task_id = a_task_id
		AND workflow_id = a_workflow_id
		AND actions.type = 'system'
		AND actions.name = 'unlock';
		
	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_unlock_task called for non-unlock-task %', a_task_id;
	END IF;

	--RAISE NOTICE 'do_inargsmap action_id % task_id % args % vars % ', v_action_id, a_task_id, v_args, v_vars;
	BEGIN
		v_inargs := do_inargsmap(v_action_id, a_task_id, v_args, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
		
	RAISE NOTICE 'do_unlock_task v_inargs %', v_inargs;

	-- and what subscriptions we are actually interested in
	-- (do_inargsmap has made sure those fields exist?)
	v_locktype := v_inargs->>'locktype';
	v_lockvalue := v_inargs->>'lockvalue';

	-- we need an exlusive lock on the locks table to prevent a race condition
	-- between setting the contented flag and updating job state
	LOCK TABLE locks IN SHARE ROW EXCLUSIVE MODE;

	DELETE FROM
		locks
	WHERE
		job_id = a_job_id
		AND locktype =  v_locktype
		AND lockvalue = v_lockvalue
	RETURNING contended INTO v_contended;

	IF NOT FOUND THEN
		-- or do a warning instead?
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('tried to unlock not held lock locktype %s lockvalue %s', v_locktype, v_lockvalue));
	END IF;

	IF v_contended THEN
		SELECT 
			job_id, task_id, workflow_id
			INTO v_waitjob_id, v_waittask_id, v_waitworkflow_id
		FROM
			jobs
		WHERE
			waitforlocktype = v_locktype
			AND waitforlockvalue = v_lockvalue
			AND state = 'sleeping'
		FOR UPDATE OF jobs;
		
		IF FOUND THEN
			-- create lock for blocked task
			INSERT INTO locks (job_id, locktype, lockvalue) VALUES (v_waitjob_id, v_locktype, v_lockvalue);
			-- mark task done
			UPDATE jobs SET
				state = 'done',
				waitforlocktype = null,
				waitforlockvalue = null,
				task_completed = now()
			WHERE
				job_id = v_waitjob_id;
			-- log something
			INSERT INTO job_task_log (job_id, workflow_id, task_id, task_entered, task_started, task_completed)
			SELECT job_id, workflow_id, task_id, task_entered, task_started, task_completed
			FROM jobs
			WHERE job_id = v_waitjob_id;
			-- wake up maestro
			PERFORM pg_notify( 'jobtaskdone',  (v_waitworkflow_id::TEXT || ':' || v_waittask_id::TEXT || ':' || v_waitjob_id::TEXT ));
		END IF;
	END IF;

	UPDATE jobs SET
		state = 'done',
		task_started = now(),
		task_completed = now()
	WHERE
		job_id = a_job_id;
	-- log something
	INSERT INTO job_task_log (job_id, workflow_id, task_id, task_entered, task_started, task_completed)
	SELECT job_id, workflow_id, task_id, task_entered, task_started, task_completed
	FROM jobs
	WHERE job_id = a_job_id;
	
	RETURN do_jobtaskdone(a_workflow_id, a_task_id, a_job_id);
END;$function$
