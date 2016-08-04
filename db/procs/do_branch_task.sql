CREATE OR REPLACE FUNCTION jobcenter.do_branch_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_boolcode text;
	v_branch boolean;
	v_nexttask_id integer;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, environment, variables, attributes->>'boolcode', next_task_id INTO
		v_args, v_env, v_vars, v_boolcode, v_nexttask_id
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND workflow_id = a_jobtask.workflow_id
		AND task_id= a_jobtask.task_id
		AND state = 'ready'
		AND actions.type = 'system'
		AND actions.name = 'branch';

	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_branch_task called for non-branch-task %', a_jobtask.task_id;
	END IF;

	BEGIN
		v_branch := do_boolcode(v_boolcode, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_boolcode sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;

	-- the else branch task_id, if any, is stored in de next_task_id field
	-- else it contains the task_id of the end-if noop
	IF v_branch THEN
		SELECT
			to_task_id INTO STRICT v_nexttask_id
		FROM
			next_tasks
		WHERE
			from_task_id = a_jobtask.task_id
			AND "when" = 'true';
	END IF;

	-- custom task epilogue because of custom nextjobttask
	UPDATE jobs SET
		state = 'plotting',
		task_started = now(),
		task_completed = now()
	WHERE
		job_id = a_jobtask.job_id;
	PERFORM do_log(a_jobtask.job_id, false, null, to_jsonb(v_branch));

	RETURN (false, (a_jobtask.workflow_id, v_nexttask_id, a_jobtask.job_id)::jobtask)::nextjobtask;
END;$function$
