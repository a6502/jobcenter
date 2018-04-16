CREATE OR REPLACE FUNCTION jobcenter.do_create_childjob(a_parentjobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_job_id BIGINT;
	v_workflow_id INT;
	v_task_id INT;
	v_wait boolean;
	v_args JSONB;
	v_parent_env JSONB;
	v_jcenv JSONB;
	v_env JSONB;
	v_config JSONB;
	v_vars JSONB;
	v_inargs JSONB;
	v_curdepth integer;
	v_maxdepth integer;
BEGIN
	-- find the sub-worklow using the task in the parent
	-- get the arguments and variables as well
	SELECT
		action_id, COALESCE( (attributes->>'wait')::boolean, true), arguments,
		COALESCE(environment, '{}'::jsonb), variables, current_depth
		INTO v_workflow_id, v_wait, v_args, v_parent_env, v_vars, v_curdepth
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

	BEGIN
		v_inargs := do_inargsmap(v_workflow_id, a_parentjobtask, v_args, v_parent_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_parentjobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
	
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

	--RAISE NOTICE 'do_create_childjob: v_wait is %', v_wait;

	-- now create the new job and mark the start task 'done'
	INSERT INTO jobcenter.jobs
		(workflow_id, task_id, parentjob_id, state, arguments, environment,
		 max_steps, current_depth, task_entered, task_started, task_completed,
		 job_state)
	VALUES
		(v_workflow_id, v_task_id, a_parentjobtask.job_id, 'done', v_inargs, v_env,
		 COALESCE((v_config->>'max_steps')::integer, 99), v_curdepth + 1, now(), now(), now(),
		 jsonb_build_object('parenttask_id', a_parentjobtask.task_id, 'parentwait', v_wait))
	RETURNING
		job_id INTO v_job_id;

	IF v_wait THEN
		-- mark the parent job as waiting for a child job
		UPDATE jobs SET
			state = 'childwait',
			task_started = now(),
			out_args = jsonb_build_object('childjob_id', v_job_id) -- store child job_id somewhere
		WHERE job_id = a_parentjobtask.job_id;
		-- and continue with the childjob
		RETURN do_task_epilogue((v_workflow_id, v_task_id, v_job_id)::jobtask, false, null, null, null);
	ELSE
		-- wake up the maestro for the new job
		--RAISE NOTICE 'NOTIFY "jobtaskdone", %', (v_workflow_id::TEXT || ':' || v_task_id::TEXT || ':' || v_job_id::TEXT );
		PERFORM pg_notify( 'jobtaskdone',  ( '(' || v_workflow_id || ',' || v_task_id || ',' || v_job_id || ')' ));
		-- and continue to next task
		-- logging the child job_id in the out_args field
		RETURN do_task_epilogue(a_parentjobtask, false, null, null, to_jsonb(v_job_id));
	END IF;
	
	-- not reached
END$function$
