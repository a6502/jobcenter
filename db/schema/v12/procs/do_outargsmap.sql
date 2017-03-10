CREATE OR REPLACE FUNCTION jobcenter.do_outargsmap(a_jobtask jobtask, a_outargs jsonb)
 RETURNS TABLE(vars_changed boolean, newvars jsonb)
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_action_id integer;
	v_oldvars jsonb;
	v_args jsonb;
	v_env jsonb;
	v_key text;
	v_type text;
	v_opt boolean;
	v_actual text;
	v_code text;
	v_fields text[];
	v_val jsonb;
BEGIN
	-- the job may not actually be in the state the jobtask tuple suggest
	-- because we may be reaping a child job started by a older task
	-- so we need 2 queries:
	-- first get the vars using our job_id
	SELECT
		arguments, environment, variables
		INTO v_args, v_env, v_oldvars
	FROM
		jobs
	WHERE
		job_id = a_jobtask.job_id;
	--FOR UPDATE OF jobs;

	IF NOT FOUND THEN
		RAISE NOTICE 'do_outargsarsmap: job_id % not found', a_jobtask.job_id;
		RETURN;
	END IF;

	-- now get the rest using the task_id and workflow_id
	SELECT
		action_id, attributes->>'omapcode'
		INTO v_action_id, v_code
	FROM
		tasks
		JOIN actions USING (action_id)
	WHERE
		task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id;

	IF NOT FOUND THEN
		RAISE NOTICE 'do_outargsarsmap: task % not found', a_jobtask.task_id;
		RETURN;
	END IF;

	a_outargs := COALESCE(a_outargs, '{}'::jsonb);
	-- omap also initializes oldvars to empty, but then we would log a change if newvars is also empty
	v_oldvars := COALESCE(v_oldvars, '{}'::jsonb);

	RAISE NOTICE 'do_outargsmap: v_oldvars % a_outargs %', v_oldvars, a_outargs;

	PERFORM do_outargscheck(v_action_id, a_outargs);

	v_env = do_populate_env(a_jobtask, v_env);

	-- now run the mapping code
	newvars := do_omap(v_code, v_args, v_env, v_oldvars, a_outargs);

	vars_changed := v_oldvars IS DISTINCT FROM newvars;

	RETURN NEXT;
	RETURN;
END$function$
