CREATE OR REPLACE FUNCTION jobcenter.do_raise_error_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_action_id int;
	v_msg text;
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
		job_id = a_job_id
		AND task_id = a_task_id
		AND workflow_id = a_workflow_id
		AND actions.type = 'system'
		AND actions.name = 'raise_error';
		
	IF NOT FOUND THEN
		-- FIXME: call do_raiseerror instead?
		RAISE EXCEPTION 'do_raise_error_task called for non-raise_error-task %', a_task_id;
	END IF;

	--RAISE NOTICE 'do_inargsmap action_id % task_id % args % vars % ', v_action_id, a_task_id, v_args, v_vars;
	BEGIN
		v_inargs := do_inargsmap(v_action_id, a_task_id, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
		
	RAISE NOTICE 'do_raise_error_task v_inargs %', v_inargs;

	-- and what subscriptions we are actually interested in
	-- (do_inargsmap has made sure those fields exist?)
	v_msg := v_inargs->>'msg';

	RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, v_msg);
END;$function$
