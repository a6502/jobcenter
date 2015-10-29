CREATE OR REPLACE FUNCTION jobcenter.do_end_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
AS $function$DECLARE
	v_parentjob_id bigint;
	v_parentworkflow_id int;
	v_parentwaitfortask int;
	v_parenttask_id int;
	v_variables jsonb;
	v_outargs jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT
		variables, parentjob_id, parenttask_id INTO
		v_variables, v_parentjob_id, v_parentwaitfortask
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_job_id
		AND workflow_id = a_workflow_id
		AND task_id= a_task_id
		AND state = 'ready'
		AND actions.type = 'system'
		AND actions.name = 'end';

	IF NOT FOUND THEN
		RAISE EXCEPTION 'do_end_task called for non-end-task %', a_task_id;
	END IF;

	BEGIN
		v_outargs := do_workflowoutargsmap(a_workflow_id, v_variables);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('caught exception in do_workflowoutargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
			
	RAISE NOTICE 'do_end_task wf % task % job % vars % => outargs %', a_workflow_id, a_task_id, a_job_id, v_variables, v_outargs;

	IF v_parentjob_id IS NULL THEN
		-- mark job as finished
		UPDATE
			jobs
		SET
			state = 'finished',
			job_finished = now(), -- the trigger on the job_finished column will do the cleanups
			task_started = now(),
			task_completed = now(),
			out_args = v_outargs
		WHERE
			job_id = a_job_id;

		-- and let any waiting clients know
		RAISE NOTICE 'NOTIFY job:%:finished', a_job_id;
		PERFORM pg_notify('job:' || a_job_id || ':finished', '42');
		RETURN null; -- no next task
	END IF;

	-- become a zombie
	UPDATE
		jobs
	SET
		state = 'zombie',
		task_started = now(),
		out_args = v_outargs
	WHERE
		job_id = a_job_id;

	-- check if the parent is already waiting for us
	-- we need locking here to prevent a race condition with wait_for_children
	-- any deadlock error will be handled in do_jobtask
	LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;
	--LOCK TABLE jobs IN SHARE MODE;

	SELECT
		workflow_id, task_id
		INTO v_parentworkflow_id, v_parenttask_id
	FROM
		jobs
	WHERE
		job_id = v_parentjob_id
		-- AND waitfortask_id = v_parentwaitfortask
		AND state = 'blocked';

	IF FOUND THEN
		-- poke parent
		RETURN do_wait_for_children_task(v_parentworkflow_id, v_parenttask_id, v_parentjob_id);
	ELSE
		-- remain a zombie until the parent finds for us
		RAISE NOTICE 'parent not found %', now();
	END IF;
	
	RETURN null; -- no next task
END;$function$
