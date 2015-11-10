CREATE OR REPLACE FUNCTION jobcenter.do_lock_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
AS $function$DECLARE
	v_args jsonb;
	v_vars jsonb;
	v_action_id int;
	v_inargs jsonb;
	v_locktype text;
	v_lockvalue text;
	v_gotlock boolean DEFAULT false;
	v_parentjob_id bigint;
	v_lockjob_id bigint;
	v_deadlockpath bigint[];
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, variables, action_id, parentjob_id
		INTO v_args, v_vars, v_action_id, v_parentjob_id
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_job_id
		AND task_id = a_task_id
		AND workflow_id = a_workflow_id
		AND actions.type = 'system'
		AND actions.name = 'lock';
		
	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_lock_task called for non-lock-task %', a_task_id;
	END IF;

	--RAISE NOTICE 'do_inargsmap action_id % task_id % args % vars % ', v_action_id, a_task_id, v_args, v_vars;
	BEGIN
		v_inargs := do_inargsmap(v_action_id, a_task_id, v_args, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
		
	RAISE NOTICE 'do_lock_task v_inargs %', v_inargs;

	-- and what subscriptions we are actually interested in
	-- (do_inargsmap has made sure those fields exist?)
	v_locktype := v_inargs->>'locktype';
	v_lockvalue := v_inargs->>'lockvalue';

	-- we need an exlusive lock on the locks table to prevent a race condition
	-- between setting the contented flag and updating job state
	-- (and maybe for the deadlock detection too)
	LOCK TABLE locks IN SHARE ROW EXCLUSIVE MODE;

	BEGIN
		INSERT INTO locks (job_id, locktype, lockvalue) VALUES (a_job_id, v_locktype, v_lockvalue);
		v_gotlock := true;
	EXCEPTION WHEN unique_violation THEN
		SELECT job_id INTO v_lockjob_id FROM locks WHERE locktype=v_locktype AND lockvalue = v_lockvalue FOR UPDATE;
		-- select should return something here because of the unique violation
		IF v_lockjob_id = a_job_id THEN
			-- we already have the lock
			v_gotlock := true; -- FIXME: or error?
		ELSIF v_lockjob_id = v_parentjob_id THEN
			-- todo: steal lock from parent
		END IF;
	END;

	IF NOT v_gotlock THEN
		-- mark current lock as contended
		UPDATE locks SET contended=true WHERE locktype=v_locktype AND lockvalue = v_lockvalue;

		-- mark ourselves as waiting for this lock
		UPDATE jobs SET
			state = 'sleeping', -- FIXME: whut
			waitforlocktype = v_locktype,
			waitforlockvalue = v_lockvalue,
			task_started = now()
		WHERE
			job_id = a_job_id;

		-- now see if we have a cycle of sleeping jobs
		WITH RECURSIVE detect_deadlock(job_id, path, cycle) AS (
				SELECT
					 job_id,
					 ARRAY[job_id] as path,
					 false as cycle
				FROM
					 jobs
				WHERE
					job_id = v_lockjob_id
					AND state = 'sleeping'
			UNION ALL
				SELECT
					l.job_id,
					path || l.job_id,
					l.job_id = ANY(path)
				FROM
					jobs j
					JOIN locks l on j.waitforlocktype=l.locktype AND j.waitforlockvalue=l.lockvalue
					JOIN detect_deadlock dd ON j.job_id = dd.job_id
				WHERE
					j.state = 'sleeping' AND
					NOT cycle
		)
		SELECT path INTO v_deadlockpath FROM detect_deadlock WHERE cycle=true;

		IF v_deadlockpath IS NOT NULL THEN
			-- now what?
			-- if the error proves fatal then the cleanup trigger
			-- will cleanup our locks and unlock the other job(s)
			RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id,
					format('deadlock trying to get locktype %s lockvalue %s path %s',
						v_locktype, v_lockvalue, array_to_string(v_deadlockpath, ', ')
					)
				);
		END IF;

		RETURN null; -- no next task
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
