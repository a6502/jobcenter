CREATE OR REPLACE FUNCTION jobcenter.do_switch_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_stringcode text;
	v_when text;
	v_newvars jsonb;
	v_changed boolean;
	v_nexttask_id integer;
	v_targettask_id integer;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, environment, variables, attributes->>'stringcode', next_task_id INTO
		v_args, v_env, v_vars, v_stringcode, v_nexttask_id
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
		AND actions.name = 'switch';

	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_switch_task called for non-switch-task %', a_jobtask.task_id;
	END IF;

	BEGIN
		SELECT * INTO v_when, v_newvars	FROM do_stringcode(v_stringcode, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_stringcode sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;

	SELECT
		to_task_id INTO v_targettask_id
	FROM
		next_tasks
	WHERE
		from_task_id = a_jobtask.task_id
		AND "when" = v_when;

	-- constraints on the table should prevent more than 1 row matching
	
	IF NOT FOUND THEN
		-- we put the else clause, if any, in the next task field
		-- otherwise it is the end-switch noop
		v_targettask_id = v_nexttask_id;
		v_when = '[else]'; -- for logging
	END IF;

	RAISE NOTICE 'switch targettask_id: %', v_targettask_id;

	v_changed := v_vars IS DISTINCT FROM v_newvars;

	-- custom task epilogue because of custom nextjobttask
	UPDATE jobs SET
		state = 'plotting',
		variables = CASE WHEN v_changed THEN v_newvars ELSE variables END,
		task_started = now(),
		task_completed = now()
	WHERE
		job_id = a_jobtask.job_id;
	PERFORM do_log(a_jobtask.job_id, v_changed, null, to_jsonb(v_when));
	
	RETURN (false, (a_jobtask.workflow_id, v_targettask_id, a_jobtask.job_id)::jobtask)::nextjobtask;
END;$function$
