CREATE OR REPLACE FUNCTION jobcenter.do_sleep_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_action_id integer;
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_inargs jsonb;
	v_timeout timestamptz;
BEGIN
	-- paranoia check with side effects..
	SELECT
		arguments, environment, variables INTO v_args, v_env, v_vars
	FROM
		jobs
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id;

	IF NOT FOUND THEN
		-- FIXME: should not happen, as this is an internal function
		RAISE EXCEPTION 'do_sleep_task % not found', a_jobtask.task_id;
	END IF;

	SELECT
		action_id INTO STRICT v_action_id
	FROM
		actions
	WHERE
		"type" = 'system'
		AND name = 'sleep';
	
	--RAISE NOTICE 'do_inargsmap action_id % task_id % argstrue % vars % ', v_action_id, a_task_id, v_args, v_vars;
	BEGIN
		v_inargs := do_inargsmap(v_action_id, a_jobtask, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;	
	--RAISE NOTICE 'v_inargs %', v_inargs;

	-- now find out how long we are supposed to sleep
	v_timeout = now() + (v_inargs->>'timeout')::interval;
	RAISE NOTICE 'sleep until %', v_timeout;
	-- FIXME: minimum sleep?

	-- mark job sleeping and set the timeout
	UPDATE jobs SET
		state = 'sleeping',
		task_started = now(),
		timeout = v_timeout,
		out_args = v_inargs
	WHERE
		job_id = a_jobtask.job_id;

	RETURN null; -- no next task
END
$function$
