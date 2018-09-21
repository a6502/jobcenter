CREATE OR REPLACE FUNCTION jobcenter.create_job(wfname text, args jsonb, tag text DEFAULT NULL::text, impersonate text DEFAULT NULL::text, env jsonb DEFAULT NULL::jsonb)
 RETURNS TABLE(o_job_id bigint, o_listenstring text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	a_wfname ALIAS FOR $1;
	a_args ALIAS FOR $2;
	a_tag ALIAS FOR $3;
	a_impersonate ALIAS FOR $4;
	a_env ALIAS FOR $5;
	v_workflow_id int;
	v_task_id int;
	v_val jsonb;
	v_inargs jsonb;
	v_env jsonb;
	v_config jsonb;
	v_tags text[] DEFAULT ARRAY['default'];
	v_have_role text;
	v_should_role text;
	v_via_role text;
BEGIN
	IF a_tag IS NOT NULL AND a_tag <> 'default' THEN
		v_tags = string_to_array(a_tag, ':') || v_tags;
	END IF;

	-- find the worklow by name
	SELECT
		action_id, COALESCE(wfenv, '{}'::jsonb), rolename, COALESCE(config, '{}'::jsonb) INTO
		v_workflow_id, v_env, v_should_role, v_config
	FROM 
		actions
		LEFT JOIN action_version_tags AS avt USING (action_id)
	WHERE
		type = 'workflow'
		AND name = a_wfname
		AND (avt.tag = ANY(v_tags) OR avt.tag IS NULL)
	ORDER BY array_position(v_tags, avt.tag), version DESC LIMIT 1;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'no workflow named %', a_wfname;
	END IF;

	IF v_config -> 'disabled' = 'true'::jsonb THEN
		RAISE EXCEPTION 'workflow % is disabled', a_wfname;
	END IF;

	-- check session user because we are in a security definer stored procedure
	IF a_impersonate IS NOT NULL THEN
		-- check if the postgresql session user is allowed to impersonate role a_impersonate
		PERFORM
			true
		FROM
			jc_impersonate_roles 
		WHERE
			rolename = session_user
			AND impersonates = a_impersonate;

		IF NOT FOUND THEN
			RAISE EXCEPTION 'client % has no right to impersonate role %', session_user, a_impersonate;
		END IF;

		v_have_role := a_impersonate;
		v_via_role := session_user;
		--RAISE NOTICE 'v_env before: %; a_env: %', v_env, a_env;
		-- the impersonator is allowed to add 'trusted' information to the env
		v_env := COALESCE(a_env, '{}'::jsonb) || v_env; -- wfenv overwrites a_env
	ELSE
		v_have_role := session_user;
	END IF;

	IF NOT do_check_role_membership(v_have_role, v_should_role) THEN
		RAISE EXCEPTION 'client % with role % has no permission for role %', session_user, v_have_role, v_should_role;
	END IF;

	v_inargs := do_inargscheck(v_workflow_id, a_args);
	
	-- ok, now find the start task of the workflow
	SELECT 
		t.task_id INTO v_task_id
	FROM
		tasks AS t
		JOIN actions AS a ON t.action_id = a.action_id
	WHERE
		t.workflow_id = v_workflow_id
		AND a.type = 'system'
		AND a.name = 'start';

	IF NOT FOUND THEN
		RAISE EXCEPTION 'no start task in workflow % .', a_wfname;
	END IF;

	SELECT jcenv FROM jc_env INTO STRICT v_val; -- hack, reuse v-val
	v_env := v_env || v_val; -- jcenv overwrites wfenv/a_env
	v_env := jsonb_set(v_env, '{client}', to_jsonb(v_have_role));
	IF v_via_role IS NOT NULL THEN
		v_env := jsonb_set(v_env, '{via}', to_jsonb(v_via_role));
	END IF;
	-- copy the max_depth config into the environment so that child jobs inherit this value
	-- maybe max_depth should move back to wfenv?
	IF v_config->'max_depth' IS NOT NULL THEN
		v_env := jsonb_set(v_env, '{max_depth}', v_config->'max_depth');
	END IF;

	-- now create the new job and mark the start task 'done'
	INSERT INTO jobcenter.jobs
		(workflow_id, task_id, state, arguments,
		 environment, max_steps, current_depth, task_entered,
		 task_started, task_completed)
	VALUES
		(v_workflow_id, v_task_id, 'done', v_inargs,
		 v_env, COALESCE((v_config->>'max_steps')::integer, 99), 1, now(),
		 now(), now())
	RETURNING
		job_id INTO o_job_id;

	-- wake up maestro
	--RAISE NOTICE 'NOTIFY "jobtaskdone", %', (v_workflow_id::TEXT || ':' || v_task_id::TEXT || ':' || o_job_id::TEXT );
	PERFORM pg_notify( 'jobtaskdone',  ( '(' || v_workflow_id || ',' || v_task_id || ',' || o_job_id || ')' ));
	
	o_listenstring := 'job:' || o_job_id::TEXT || ':finished';
	-- and inform the caller
	RETURN NEXT;
	RETURN;
END$function$
