CREATE OR REPLACE FUNCTION jobcenter.do_prepare_for_action(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_action_id int;
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_in_args jsonb;
BEGIN
	-- get the arguments and variables
	SELECT
		action_id, arguments, environment, variables INTO v_action_id, v_args, v_env, v_vars
	FROM 
		actions
		JOIN tasks USING (action_id)
		JOIN jobs USING (workflow_id, task_id)
	WHERE
		workflow_id = a_jobtask.workflow_id
		AND task_id = a_jobtask.task_id
		AND job_id = a_jobtask.job_id
		AND type = 'action';

	IF NOT FOUND THEN
		-- FIXME: or is this a do_raiserror kind of error?
		RAISE EXCEPTION 'no action found for workflow % task %.', a_jobtask.workflow_id, a_jobtask.task_id;
	END IF;

	BEGIN
		v_in_args := do_inargsmap(v_action_id, a_jobtask.task_id, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
	
	-- FIXME: add an extra field to jobs?
	-- 'abuse' the out_args field to store the calulated in_args
	UPDATE jobs
		SET out_args = v_in_args
	WHERE
		job_id = a_jobtask.job_id;

	RAISE NOTICE 'NOTIFY "action:%:ready", %', v_action_id, a_jobtask.job_id;
	PERFORM pg_notify('action:' || v_action_id || ':ready', a_jobtask.job_id::text);
	RETURN null; -- no text task
END$function$
