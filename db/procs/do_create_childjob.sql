CREATE OR REPLACE FUNCTION jobcenter.do_create_childjob(a_parentjobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_job_id BIGINT;
	v_workflow_id INT;
	v_task_id INT;
	v_wait boolean;
	v_detach boolean;
	v_map text;
	v_args JSONB;
	v_parent_env JSONB;
	v_jcenv JSONB;
	v_env JSONB;
	v_config JSONB;
	v_vars JSONB;
	v_inargs JSONB;
	v_curdepth integer;
	v_maxdepth integer;
	v_array jsonb;
	v_i bigint;
	v_v jsonb;
	v_children bigint[] := '{}';
BEGIN
	-- find the sub-worklow using the task in the parent
	-- get the arguments and variables as well
	SELECT
		action_id, COALESCE( (attributes->>'wait')::boolean, true),
		COALESCE( (attributes->>'detach')::boolean, false),
		attributes->>'map', arguments,
		COALESCE(environment, '{}'::jsonb), variables, current_depth
		INTO v_workflow_id, v_wait, v_detach, v_map, v_args, v_parent_env, v_vars, v_curdepth
	FROM 
		actions
		JOIN tasks USING (action_id)
		JOIN jobs USING (workflow_id, task_id)
	WHERE
		workflow_id = a_parentjobtask.workflow_id
		AND task_id = a_parentjobtask.task_id
		AND job_id = a_parentjobtask.job_id
		AND type = 'workflow';

	IF NOT FOUND THEN
		-- FIXME: or is this a do_raiserror kind of error?
		RAISE EXCEPTION 'no workflow found for workflow % task %.', a_parentjobtask.workflow_id, a_parentjobtask.task_id;
	END IF;

	-- fixme: harcoded default
	v_maxdepth := COALESCE((v_parent_env->>'max_depth')::integer, 9);

	IF v_curdepth >= v_maxdepth THEN
		RETURN do_raise_error(a_parentjobtask, format('maximum call depth would be exceeded: %s >= %s', v_curdepth, v_maxdepth), 'fatal');
	END IF;

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

	-- setup childjob env: copy parent env but overwrite with the per workflow
	-- and global env (in that order)
	SELECT
		COALESCE(wfenv, '{}'::jsonb), COALESCE(config, '{}'::jsonb)
		INTO v_env, v_config
	FROM
		actions
	WHERE
		action_id = v_workflow_id;
	SELECT jcenv FROM jc_env INTO STRICT v_jcenv;
	v_env := v_parent_env || v_env || v_jcenv;
	-- jcenv overwrites wfenv overwrites parent_env
	v_env := jsonb_set(v_env, '{max_depth}', to_jsonb(v_maxdepth));

	-- todo: unify this with the non-map case
	IF v_map IS NOT NULL THEN
		v_array := CASE WHEN v_map LIKE 'a.%' THEN v_args->substring(v_map,3) WHEN v_map LIKE 'v.%' THEN v_vars->substring(v_map,3) END;
		--RAISE LOG 'hiero! %', v_array;
		IF v_array IS NULL THEN
			RETURN do_raise_error(a_parentjobtask, format('map variable %s does not exist?', v_map));
		END IF;
		IF jsonb_typeof(v_array) <> 'array' THEN
			RETURN do_raise_error(a_parentjobtask, format('map variable %s is not an array', v_map));
		END IF;
		FOR v_i, v_v IN SELECT ordinality, value FROM jsonb_array_elements(v_array) WITH ORDINALITY LOOP
			BEGIN
				v_inargs := do_inargsmap(v_workflow_id, a_parentjobtask, v_args, v_parent_env || jsonb_build_object('_i', v_i::int, '_v', v_v), v_vars);
			EXCEPTION WHEN OTHERS THEN
				RETURN do_raise_error(a_parentjobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
			END;

			-- now create the new job and mark the start task 'done'
			INSERT INTO jobcenter.jobs
				(workflow_id, task_id, state, arguments, environment,
				 max_steps, current_depth, task_entered, task_started, task_completed,
				 parentjob_id, job_state)
			VALUES
				(v_workflow_id, v_task_id, 'done', v_inargs, v_env,
				 COALESCE((v_config->>'max_steps')::integer, 99), v_curdepth + 1, now(), now(), now(),
				 a_parentjobtask.job_id,
				 jsonb_build_object('parenttask_id', a_parentjobtask.task_id, 'parentwait', v_wait) )
			RETURNING
				job_id INTO v_job_id;

			-- wake up the maestro for the new job
			--RAISE NOTICE 'NOTIFY "jobtaskdone", %', (v_workflow_id::TEXT || ':' || v_task_id::TEXT || ':' || v_job_id::TEXT );
			PERFORM pg_notify( 'jobtaskdone',  ( '(' || v_workflow_id || ',' || v_task_id || ',' || v_job_id || ')' ));

			v_children = array_append(v_children, v_job_id);
		END LOOP;
		-- log the created child job_ids in the task_state
		UPDATE jobs SET
			task_state = jsonb_build_object('childjob_ids', to_jsonb(v_children))
		WHERE job_id = a_parentjobtask.job_id;
		-- and continue with the parentjob
		RETURN do_task_epilogue(a_parentjobtask, false, null, v_array, null);
	END IF;

	BEGIN
		v_inargs := do_inargsmap(v_workflow_id, a_parentjobtask, v_args, v_parent_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_parentjobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
	
	--RAISE NOTICE 'do_create_childjob: v_wait is %', v_wait;

	-- now create the new job and mark the start task 'done'
	INSERT INTO jobcenter.jobs
		(workflow_id, task_id, state, arguments, environment,
		 max_steps, current_depth, task_entered, task_started, task_completed,
		 parentjob_id, job_state)
	VALUES
		(v_workflow_id, v_task_id, 'done', v_inargs, v_env,
		 COALESCE((v_config->>'max_steps')::integer, 99), v_curdepth + 1, now(), now(), now(),
		 CASE WHEN v_detach THEN null ELSE a_parentjobtask.job_id END,
		 CASE WHEN v_detach THEN null ELSE
			jsonb_build_object('parenttask_id', a_parentjobtask.task_id, 'parentwait', v_wait)
		 END)
	RETURNING
		job_id INTO v_job_id;

	IF v_wait AND NOT v_detach THEN
		-- mark the parent job as waiting for a child job
		-- and log child job_id in task_state
		UPDATE jobs SET
			state = 'childwait',
			task_started = now(),
			task_state = jsonb_build_object('childjob_id', v_job_id)
		WHERE job_id = a_parentjobtask.job_id;
		-- and continue with the childjob
		RETURN do_task_epilogue((v_workflow_id, v_task_id, v_job_id)::jobtask, false, null, null, null);
	ELSE
		-- wake up the maestro for the new job
		--RAISE NOTICE 'NOTIFY "jobtaskdone", %', (v_workflow_id::TEXT || ':' || v_task_id::TEXT || ':' || v_job_id::TEXT );
		PERFORM pg_notify( 'jobtaskdone',  ( '(' || v_workflow_id || ',' || v_task_id || ',' || v_job_id || ')' ));
		-- log the child job_id in the task_state field
		UPDATE jobs SET
			task_state = jsonb_build_object('childjob_id', v_job_id)
		WHERE job_id = a_parentjobtask.job_id;
		-- and continue to next task
		RETURN do_task_epilogue(a_parentjobtask, false, null, v_inargs, null);
	END IF;
	
	-- not reached
END$function$
