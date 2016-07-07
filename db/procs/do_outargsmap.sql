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
		arguments, environment variables
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

	-- now get the rest using the task and job_id
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

	-- first check if all the required outargs are there
	FOR v_key, v_type, v_opt IN SELECT "name", "type", optional
			FROM action_outputs WHERE action_id = v_action_id LOOP

		IF NOT a_outargs ? v_key THEN
			IF NOT v_opt THEN
				RAISE EXCEPTION 'required output parameter % not found', v_key;
			ELSE
				CONTINUE;
			END IF;
		END IF;

		v_val := a_outargs->v_key;
		v_actual := jsonb_typeof(v_val);
		RAISE NOTICE 'v_key % v_type % v_opt % v_val % v_actual %', v_key, v_type, v_opt, v_val, v_actual;

		IF v_actual = 'object' THEN
			SELECT fields INTO v_fields FROM jsonb_object_fields WHERE typename = v_type;
			IF NOT v_val ?& v_fields THEN
				RAISE EXCEPTION 'output parameter % with value % does have required fields %', v_key, v_val, v_fields;
			END IF;
		ELSIF v_actual = null OR v_actual = v_type THEN
			-- ok?
			NULL;
		ELSE
			RAISE EXCEPTION 'ouput parameter % has wrong type % (should be %)', v_key, v_actual, v_type;
		END IF;
	END LOOP;

	-- now run the mapping code
	--SELECT omapcode INTO v_code FROM tasks WHERE task_id = a_jobtask.task_id;
	newvars := do_omap(v_code, v_args, v_env, v_oldvars, a_outargs);

	vars_changed := v_oldvars IS DISTINCT FROM newvars;

	RETURN NEXT;
	RETURN;
END$function$
