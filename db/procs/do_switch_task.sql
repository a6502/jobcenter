CREATE OR REPLACE FUNCTION jobcenter.do_switch_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
AS $function$DECLARE
	v_args jsonb;
	v_vars jsonb;
	v_casecode text;
	v_when text;
	v_nexttask_id integer;
	v_targettask_id integer;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, variables, casecode, next_task_id INTO
		v_args, v_vars, v_casecode, v_nexttask_id
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
		AND actions.name = 'switch';

	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_switch_task called for non-switch-task %', a_task_id;
	END IF;

	BEGIN
		v_when := do_switchcasecode(v_casecode, v_args, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('caught exception in do_switchcasecode sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;

	SELECT
		to_task_id INTO v_targettask_id
	FROM
		next_tasks
	WHERE
		from_task_id = a_task_id
		AND "when" = v_when;

	-- constraints on the table should prevent more than 1 row matching
	
	IF NOT FOUND THEN
		-- we put the else clause, if any, in the next task field
		-- otherwise it is the end-switch noop
		v_targettask_id = v_nexttask_id;
	END IF;

	RAISE NOTICE 'switch targettask_id: %', v_targettask_id;

	-- mark jobtask as plotting so do_jobtask will move on
	UPDATE jobs SET
		state = 'plotting',
		task_started = now(),
		task_completed = now()
	WHERE
		job_id = a_job_id;
	-- log something
	INSERT INTO job_task_log (job_id, workflow_id, task_id, task_entered, task_started, task_completed)
	SELECT job_id, workflow_id, task_id, task_entered, task_started, task_completed
	FROM jobs
	WHERE job_id = a_job_id;
	
	RETURN nexttask(false, a_workflow_id, v_targettask_id, a_job_id);
END;$function$
