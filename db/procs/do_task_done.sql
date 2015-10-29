CREATE OR REPLACE FUNCTION jobcenter.do_task_done(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_outargs jsonb, a_notify boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$DECLARE
	v_inargs jsonb;
	v_oldvars jsonb;
	v_maptask_id integer; -- task we use the map defintions from, for wait_for
	v_mapaction_id integer;
	v_action_id integer;
	v_actiontype action_type;
	v_actionname text;
	v_newvars jsonb;
BEGIN
	SELECT 
		action_id, variables, out_args, "type", "name" INTO v_action_id, v_oldvars, v_inargs, v_actiontype, v_actionname
	FROM 
		jobs 
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_job_id
		AND task_id = a_task_id
		AND workflow_id = a_workflow_id
		AND state IN ('working','waiting','sleeping','blocked')
	FOR UPDATE OF jobs;

	IF NOT FOUND THEN
		-- FIXME: or raise error?
		RAISE WARNING 'no job found in suitable state %', a_job_id;
		RETURN;
	END IF;	

	-- check error status
	IF a_outargs ? 'error' THEN
		PERFORM do_task_error(v_workflow_id, v_task_id, v_job_id, a_outargs->'error');
		RETURN;
	END IF;

	-- blegh, we need a special case for reap_child here..
	-- because we want the outputs and maps from the original task
	IF v_actiontype = 'system' AND v_actionname = 'reap_child' THEN
		SELECT
			t2.action_id, t2.task_id INTO v_mapaction_id, v_maptask_id
		FROM 
			tasks AS t1 
			JOIN tasks  AS t2 ON t1.reapfromtask_id = t2.task_id
			JOIN actions AS a ON t2.action_id = a.action_id
		WHERE
			t1.task_id = a_task_id; -- and workflow?
	ELSE
		v_maptask_id := a_task_id;
		v_mapaction_id = v_action_id;
	END IF;

	BEGIN
		v_newvars := do_outargsmap(v_mapaction_id, v_maptask_id, v_oldvars, a_outargs);
	EXCEPTION WHEN OTHERS THEN
		PERFORM do_task_error(v_workflow_id, v_task_id, v_job_id, format('caught exception in do_outargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM)::jsonb);
		RETURN;
	END;

	RAISE NOTICE 'do_task_done do_outargsmap % % % % => %', v_mapaction_id, v_maptask_id, v_oldvars, a_outargs, v_newvars;

	-- not saving unchanged variables is a performance hack
	-- is it worth it?
	IF v_oldvars IS DISTINCT FROM v_newvars THEN
		UPDATE jobs SET
			state = 'done',
			variables = v_newvars,
			task_completed = now(),
			waitfortask_id = NULL,
			cookie = NULL,
			timeout = NULL,
			out_args = NULL
		WHERE job_id = a_job_id;
		INSERT INTO job_task_log (job_id, workflow_id, task_id, variables, task_entered, task_started,
				task_completed, worker_id, task_inargs, task_outargs)
			SELECT job_id, workflow_id, task_id, variables, task_entered, task_started,
				task_completed, worker_id, v_inargs as task_inargs, a_outargs as task_outargs
			FROM jobs
			WHERE job_id = a_job_id;		
	ELSE
		UPDATE jobs SET
			state = 'done',
			task_completed = now(),
			waitfortask_id = NULL,
			cookie = NULL,
			timeout = NULL,
			out_args = NULL
		WHERE job_id = a_job_id;
		INSERT INTO job_task_log (job_id, workflow_id, task_id, task_entered, task_started,
				task_completed, worker_id, task_inargs, task_outargs)
			SELECT job_id, workflow_id, task_id, task_entered, task_started, task_completed,
				worker_id, v_inargs as task_inargs, a_outargs as task_outargs
			FROM jobs
			WHERE job_id = a_job_id;		
	END IF;

	IF a_notify THEN
		-- wake up maestro
		--RAISE NOTICE 'NOTIFY "jobtaskdone", %', (v_workflow_id::TEXT || ':' || v_task_id::TEXT || ':' || v_job_id::TEXT );
		PERFORM pg_notify( 'jobtaskdone',  (a_workflow_id::TEXT || ':' || a_task_id::TEXT || ':' || a_job_id::TEXT ));
	END IF;
END$function$
