CREATE OR REPLACE FUNCTION jobcenter.do_eval_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_oldvars jsonb;
	v_code text;
	v_newvars jsonb;
	v_changed boolean;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, environment, variables, imapcode INTO v_args, v_env, v_oldvars, v_code
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
		AND actions.name = 'eval';		

	IF NOT FOUND THEN
		-- FIXME: should not happen, as this is an internal function
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_eval_task called for non eval task %', a_jobtask.task_id;
	END IF;

	BEGIN
		v_newvars := do_eval(v_code, v_args, v_env, v_oldvars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_eval sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;

	v_changed = v_oldvars IS DISTINCT FROM v_newvars;

	RETURN do_task_epilogue(a_jobtask, v_changed, v_newvars, null, null);
END;$function$
