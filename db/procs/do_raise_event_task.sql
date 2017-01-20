CREATE OR REPLACE FUNCTION jobcenter.do_raise_event_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_action_id int;
	v_inargs jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, environment, variables, action_id INTO v_args, v_env, v_vars, v_action_id
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id
		AND state = 'ready'
		AND actions.type = 'system'
		AND actions.name = 'raise_event';		

	IF NOT FOUND THEN
		-- FIXME: should not happen, as this is an internal function
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_raise_event_task called for non raise_event task %', a_jobtask.task_id;
	END IF;

	BEGIN
		v_inargs := do_inargsmap(v_action_id, a_jobtask, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
	
	RAISE NOTICE 'do_raise_event_task v_inargs %', v_inargs;

	-- (do_inargsmap has made sure those fields exist?)

	PERFORM raise_event(v_inargs->'event');

	RETURN do_task_epilogue(a_jobtask, false, null, v_inargs, null);
END;$function$
