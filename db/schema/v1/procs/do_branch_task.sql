CREATE OR REPLACE FUNCTION jobcenter.do_branch_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_vars jsonb;
	v_casecode text;
	v_branch boolean;
	v_nexttask_id integer;
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
		AND actions.name = 'branch';

	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_branch_task called for non-branch-task %', a_task_id;
	END IF;

	BEGIN
		v_branch := do_branchcasecode(v_casecode, v_args, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('caught exception in do_branchcasecode sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;

	-- the else branch task_id, if any, is stored in de next_task_id field
	-- else it contains the task_id of the end-if noop
	IF v_branch THEN
		SELECT
			to_task_id INTO STRICT v_nexttask_id
		FROM
			next_tasks
		WHERE
			from_task_id = a_task_id
			AND "when" = 'true';
	END IF;

	-- mark jobtask as plotting so that do_jobtask will continue
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

	RETURN nexttask(false, a_workflow_id, v_nexttask_id, a_job_id);
END;$function$
