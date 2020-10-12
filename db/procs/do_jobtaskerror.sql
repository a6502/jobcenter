CREATE OR REPLACE FUNCTION jobcenter.do_jobtaskerror(a_jobtask jobtask, a_magic boolean DEFAULT false)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_errortask_id int;
	v_parentjob_id bigint;
	v_parenttask_id int;
	v_parentworkflow_id int;
	v_parentwait boolean;	
	v_parentjobtask jobtask;
	v_env jsonb;
	v_eo jsonb; -- error object
	v_errargs jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT 
		on_error_task_id, parentjob_id,
		(job_state->>'parenttask_id')::bigint, (job_state->>'parentwait')::boolean,
		environment, COALESCE(task_state->'error', '{}'::jsonb)
		INTO
		v_errortask_id, v_parentjob_id,
		v_parenttask_id, v_parentwait,
		v_env, v_eo
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id
		AND state = 'error'
	FOR UPDATE OF jobs;
	
	IF NOT FOUND THEN
		RAISE EXCEPTION 'do_jobtaskerror called for job not in error state %', a_jobtask.job_id;
	END IF;	

	RAISE NOTICE 'v_erortask_id %, v_eo %', v_errortask_id, v_eo;
	IF v_errortask_id IS NOT NULL -- we have an error task
		AND (
			(v_eo ? 'class' AND v_eo ->> 'class' <> 'fatal')
			OR (NOT v_eo ? 'class') -- and the error is not fatal
		) THEN -- call errortask
		RAISE NOTICE 'calling errortask %', v_errortask_id;
		-- insert the error object into the environment so that it becomes visible in the 
		-- catch block as $e{_error}
		v_env := jsonb_set(COALESCE(v_env, '{}'::jsonb), ARRAY['_error'], v_eo);
		UPDATE jobs SET
			environment = v_env,
			aborted = false	-- need to clear abort flag to prevent a loop
		WHERE
			job_id = a_jobtask.job_id;
		-- FIXME: logging?
		RETURN (false, (a_jobtask.workflow_id, v_errortask_id, a_jobtask.job_id)::jobtask)::nextjobtask;
	END IF;

	-- default error behaviour:
	-- first mark job finished
	UPDATE
		jobs
	SET
		job_finished = now(),
		task_started = now(),
		task_completed = now(),
		out_args = jsonb_build_object('error', v_eo),
		timeout = NULL
	WHERE
		job_id = a_jobtask.job_id;

	PERFORM do_cleanup_on_finish(a_jobtask);

	IF v_parentjob_id IS NULL THEN
		-- throw error to the client
		RETURN NULL;
	END IF;

	-- raise error in parent
	IF v_parentwait THEN
		-- we can do that directly
		-- sanity check parent
		SELECT
			workflow_id INTO
			v_parentworkflow_id
		FROM
			jobs
		WHERE
			job_id = v_parentjob_id
			AND task_id = v_parenttask_id
			AND state = 'childwait';

		IF NOT FOUND THEN
			-- what?
			IF a_magic THEN
				RAISE NOTICE 'parentjob % not found? ignoring', v_parentjob_id;
				RETURN null;
			ELSE
				RAISE EXCEPTION 'parentjob % not found?', v_parentjob_id;
			END IF;
		END IF;

		v_parentjobtask = (v_parentworkflow_id, v_parenttask_id, v_parentjob_id)::jobtask;

		v_errargs = jsonb_build_object(
			'error', jsonb_build_object(
				'msg', format('childjob %s raised error', a_jobtask.job_id),
				'class', 'childerror',
				'error', v_eo
			)
		);

		UPDATE jobs SET
			state = 'error',
			task_completed = now(),
			timeout = NULL,
			out_args = NULL,
			task_state = COALESCE(task_state, '{}'::jsonb) || v_errargs
		WHERE job_id = v_parentjob_id;

		PERFORM do_log(v_parentjob_id, false, null, v_errargs);

		IF a_magic THEN
			-- wake up maestro
			RAISE LOG 'NOTIFY "jobtaskerror", %', '' || v_parentjobtask::text || '';
			PERFORM pg_notify('jobtaskerror', v_parentjobtask::text );
			RETURN null;
		ELSE
			-- we were called by the maestro
			RETURN (true, v_parentjobtask)::nextjobtask;
		END IF;
	END IF;

	-- check if the parent is already waiting for its children
	-- we need locking here to prevent a race condition with wait_for_child
	-- any deadlock error will be handled in the maestro
	--LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;
	--LOCK TABLE jobs IN SHARE MODE;

	-- and get parentworkflow_id for do_wait_for_children_task
	RAISE NOTICE 'look for parent job %', v_parentjob_id;
	
	SELECT
		workflow_id, task_id INTO v_parentworkflow_id, v_parenttask_id
	FROM
		jobs
	WHERE
		job_id = v_parentjob_id
		AND state = 'childwait';

	v_parentjobtask = (v_parentworkflow_id, v_parenttask_id, v_parentjob_id)::jobtask;

	IF FOUND THEN
		RAISE NOTICE 'unblock job %, error %', v_parentjob_id, v_errargs;
		-- and call do_task error
		-- FIXME: transform error object
		--RETURN do_wait_for_children_task((v_parentworkflow_id, v_parenttask_id, v_parentjob_id)::jobtask);
		RAISE LOG 'NOTIFY "wait_for_children", %', v_parentjobtask::text;
		PERFORM pg_notify('wait_for_children', v_parentjobtask::text);
	END IF;

	RETURN null; -- no next task
END$function$
