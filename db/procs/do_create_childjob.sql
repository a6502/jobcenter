CREATE OR REPLACE FUNCTION jobcenter.do_create_childjob(a_parentworkflow_id integer, a_parenttask_id integer, a_parentjob_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
AS $function$DECLARE
	v_job_id BIGINT;
	v_workflow_id INT;
	v_task_id INT;
	v_wait boolean;
	v_args JSONB;
	v_vars JSONB;
	v_in_args JSONB;
BEGIN
	-- find the sub worklow using the task in the parent
	-- get the arguments and variables as well
	SELECT
		action_id, wait, arguments, variables INTO v_workflow_id, v_wait, v_args, v_vars
	FROM 
		actions
		JOIN tasks USING (action_id)
		JOIN jobs USING (workflow_id, task_id)
	WHERE
		workflow_id = a_parentworkflow_id
		AND task_id = a_parenttask_id
		AND job_id = a_parentjob_id
		AND type = 'workflow';

	IF NOT FOUND THEN
		-- FIXME: or is this a do_raiserror kind of error?
		RAISE EXCEPTION 'no workflow found for workflow % task %.', a_parentworkflow_id, a_parenttask_id;
	END IF;

	BEGIN
		v_in_args := do_inargsmap(v_workflow_id, a_parenttask_id, v_args, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_parentworkflow_id, a_parenttask_id, a_parentjob_id, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
	
	-- ok, now find the start task of the workflow
	SELECT 
		t.task_id INTO v_task_id
	FROM
		tasks AS t
		JOIN actions AS a ON t.action_id = a.action_id
	WHERE
		t.workflow_id = v_workflow_id
		AND a.type = 'system'
		AND a.name = 'start';

	IF NOT FOUND THEN
		RAISE EXCEPTION 'no start task in workflow % .', a_wfname;
	END IF;

	-- now create the new job and mark the start task 'done'
	INSERT INTO jobcenter.jobs
		(workflow_id, task_id, parentjob_id, parenttask_id, state, arguments, task_entered, task_started, task_completed)
	VALUES
		(v_workflow_id, v_task_id, a_parentjob_id, a_parenttask_id, 'done', v_in_args, now(), now(), now())
	RETURNING
		job_id INTO v_job_id;

	-- now wake up maestro for the new job
	RAISE NOTICE 'NOTIFY "jobtaskdone", %', (v_workflow_id::TEXT || ':' || v_task_id::TEXT || ':' || v_job_id::TEXT );
	PERFORM pg_notify( 'jobtaskdone',  (v_workflow_id::TEXT || ':' || v_task_id::TEXT || ':' || v_job_id::TEXT ));

	IF v_wait THEN
		-- mark the parent job as blocked
		UPDATE jobs SET
			state = 'blocked',
			task_started = now(),
			waitfortask_id = a_parenttask_id
		WHERE job_id = a_parentjob_id;
		RETURN null; -- and no next task
	ELSE
		-- mark the parent job as done
		UPDATE jobs SET
			state = 'done',
			task_started = now(),
			task_completed = now()
		WHERE job_id = a_parentjob_id;
		-- update log
		INSERT INTO job_task_log (job_id, workflow_id, task_id, task_entered, task_started, task_completed)
			SELECT job_id, workflow_id, task_id, task_entered, task_started, task_completed
			FROM jobs
			WHERE job_id = a_parentjob_id;		
		-- and return the next_task
		RETURN do_jobtaskdone(a_parentworkflow_id, a_parenttask_id, a_parentjob_id);
	END IF;
	
	-- not reached
END$function$
