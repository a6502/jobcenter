CREATE OR REPLACE FUNCTION jobcenter.do_call_stored_procedure(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_action_id int;
	v_procname text;
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_in_args jsonb;
	v_out_args jsonb;
	v_user name;
	v_changed boolean;
	v_newvars jsonb;
BEGIN
	-- get the arguments and variables
	SELECT
		action_id, name, arguments, environment, variables
		INTO v_action_id, v_procname, v_args, v_env, v_vars
	FROM 
		actions
		JOIN tasks USING (action_id)
		JOIN jobs USING (workflow_id, task_id)
	WHERE
		workflow_id = a_jobtask.workflow_id
		AND task_id = a_jobtask.task_id
		AND job_id = a_jobtask.job_id
		AND type = 'procedure';

	IF NOT FOUND THEN
		-- FIXME: or is this a do_raiserror kind of error?
		RAISE EXCEPTION 'no procedure found for workflow % task %.', a_jobtask.workflow_id, a_jobtask.task_id;
	END IF;

	-- first mark job working
	UPDATE jobs SET
		state = 'working',
		task_started = now()
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id	;

	BEGIN
		v_in_args := do_inargsmap(v_action_id, a_jobtask, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
	
	--RAISE NOTICE 'in do_call_stored_procedure: session_user: % current user: %', session_user, current_user;

	--IF NOT has_function_privilege(session_user, v_procname || '(jsonb)', 'execute') THEN
	--	RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('user %s may not call function %s', session_user, v_procname));
	--END IF;

	BEGIN
		-- FIXME: do something like v_procname = join('.', map { quote_ident($_) } split /\./ v_procname;
		EXECUTE 'SELECT * FROM ' || v_procname || '( $1 )' INTO STRICT v_out_args USING v_in_args;
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in stored procedure %s sqlstate %s sqlerrm %s', v_procname, SQLSTATE, SQLERRM));
	END;

	BEGIN
		SELECT vars_changed, newvars INTO v_changed, v_newvars FROM do_outargsmap(a_jobtask, v_out_args);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_outargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;

	RETURN do_task_epilogue(a_jobtask, v_changed, v_newvars, v_in_args, v_out_args);
END$function$
