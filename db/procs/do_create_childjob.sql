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
	v_vars JSONB;
	v_in_args JSONB;
	v_curdepth integer;
	v_maxdepth integer;
BEGIN
	-- find the sub worklow using the task in the parent
	-- get the arguments and variables as well
	SELECT
		action_id, wait, arguments, environment, variables, current_depth
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
		v_in_args := do_inargsmap(v_workflow_id, a_parentjobtask, v_args, v_parent_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_parentjobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
	
	-- ok, now find the start task of the workflow
	SELECT 
		t.task_id, a.wfenv
		INTO v_task_id, v_env
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

	-- setup childjob env
	SELECT jcenv FROM jc_env INTO STRICT v_jcenv;
	v_env := COALESCE(v_env, '{}'::jsonb) || v_jcenv; -- jcenv overwrites wfenv
	v_env := jsonb_set(v_env, '{max_depth}', to_jsonb(v_maxdepth));
	-- copy some values from parent env
	v_env := jsonb_set(v_env, '{client}', v_parent_env->'client');

	-- now create the new job and mark the start task 'done'
	INSERT INTO jobcenter.jobs
		(workflow_id, task_id, parentjob_id, parenttask_id,
		 parentwait, state, arguments, environment,
		 max_steps, current_depth, task_entered, task_started,
		 task_completed)
	VALUES
		(v_workflow_id, v_task_id, a_parentjobtask.job_id, a_parentjobtask.task_id,
		 v_wait, 'done', v_in_args, v_env,
		 COALESCE((v_env->>'max_steps')::integer, 99), v_curdepth + 1, now(), now(),
		 now())
	RETURNING
		job_id INTO v_job_id;

	IF v_wait THEN
		-- mark the parent job as blocked
		UPDATE jobs SET
			state = 'blocked',
			task_started = now(),
			out_args = to_jsonb(v_job_id) -- store child job_id somewhere
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
