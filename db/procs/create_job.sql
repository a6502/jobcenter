CREATE OR REPLACE FUNCTION jobcenter.create_job(a_wfname text, a_args jsonb, a_tag text DEFAULT NULL::text)
 RETURNS TABLE(o_job_id bigint, o_listenstring text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_workflow_id int;
	v_task_id int;
	v_key text;
	v_type text;
	v_opt boolean;
	v_def jsonb;
	v_actual text;
	v_fields text[];
	v_val jsonb;
	v_env jsonb;
	v_tags text[] DEFAULT ARRAY['default'];
BEGIN
	IF a_tag IS NOT NULL AND a_tag <> 'default' THEN
		v_tags = string_to_array(a_tag, ':') || v_tags;
	END IF;

	-- find the worklow by name
	SELECT
		action_id, wfenv INTO v_workflow_id, v_env
	FROM 
		actions
		LEFT JOIN action_version_tags USING (action_id)
	WHERE
		type = 'workflow'
		AND name = a_wfname
		AND (tag = ANY(v_tags) OR tag IS NULL)
	ORDER BY array_position(v_tags, tag), version DESC LIMIT 1;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'no workflow named %', a_wfname;
	END IF;

	-- check parameters
	-- FIXME: code copied from inargsmap
	FOR v_key, v_type, v_opt, v_def IN SELECT "name", "type", optional, "default"
			FROM action_inputs WHERE action_id = v_workflow_id LOOP

		IF a_args ? v_key THEN
			v_val := a_args->v_key;
			v_actual := jsonb_typeof(v_val);
			IF v_actual = 'object' THEN
				SELECT fields INTO v_fields FROM jsonb_object_fields WHERE typename = v_type;
				IF NOT v_val ?& v_fields THEN
					RAISE EXCEPTION 'input parameter % with value % does have required fields %', v_key, v_val, v_fields;
				END IF;
			ELSIF v_actual = null OR v_actual = v_type THEN
				-- ok?
				NULL;
			ELSE
				RAISE EXCEPTION 'input parameter % has wrong type % (should be %)', v_key, v_actual, v_type;
			END IF;
		ELSE
			IF v_opt THEN
				-- ugh.. copy a_args?
				a_args := jsonb_set(a_args, ARRAY[v_key], v_def);
			ELSE
				RAISE EXCEPTION 'required input parameter % not found', v_key;
			END IF;
		END IF;

	END LOOP;
	
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

	SELECT jcenv FROM jcenv INTO v_val; -- hack, reuse v-val
	v_env := v_env || v_val; -- jcenv overwrites wfenv

	-- now create the new job and mark the start task 'done'
	INSERT INTO jobcenter.jobs
		(workflow_id, task_id, state, arguments, environment, task_entered, task_started, task_completed)
	VALUES
		(v_workflow_id, v_task_id, 'done', a_args, v_env, now(), now(), now())
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
