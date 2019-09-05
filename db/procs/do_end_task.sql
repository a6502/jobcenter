CREATE OR REPLACE FUNCTION jobcenter.do_end_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_parentjob_id bigint;
	v_parentworkflow_id int;
	v_parenttask_id int;
	v_parentjobtask jobtask;
	v_parentwait boolean;
	--v_args jsonb;
	--v_env jsonb;
	--v_vars jsonb;
	v_inargs jsonb;
	v_outargs jsonb;
	v_changed boolean;
	v_newvars jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT
		parentjob_id, (job_state->>'parenttask_id')::bigint, (job_state->>'parentwait')::boolean
		INTO v_parentjob_id, v_parenttask_id, v_parentwait
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND workflow_id = a_jobtask.workflow_id
		AND task_id= a_jobtask.task_id
		AND state = 'ready'
		AND actions.type = 'system'
		AND actions.name = 'end';

	IF NOT FOUND THEN
		RAISE EXCEPTION 'do_end_task called for non-end-task %', a_jobtask.task_id;
	END IF;

	BEGIN
		v_outargs := do_workflowoutargsmap(a_jobtask);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_workflowoutargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
			
	--RAISE NOTICE 'do_end_task wf % task % job % vars % => outargs %', a_jobtask.workflow_id, a_jobtask.task_id, a_jobtask.job_id, v_vars, v_outargs;

	IF v_parentjob_id IS NOT NULL AND NOT v_parentwait THEN
		-- special handling for asynchonous child jobs in split/join
		-- become a zombie
		UPDATE
			jobs
		SET
			state = 'zombie',
			task_started = now(),
			out_args = v_outargs
		WHERE
			job_id = a_jobtask.job_id;

		PERFORM do_cleanup_on_finish(a_jobtask);

		-- check if the parent is already waiting for us
		-- we need locking here to prevent a race condition with wait_for_children
		-- any deadlock error will be handled in do_jobtask
		--LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;
		--LOCK TABLE jobs IN SHARE MODE;

		SELECT
			workflow_id
			INTO v_parentworkflow_id
		FROM
			jobs
		WHERE
			job_id = v_parentjob_id
			AND state = 'childwait'
		FOR SHARE OF jobs;

		IF FOUND THEN
			-- poke parent
			-- RETURN do_wait_for_children_task((v_parentworkflow_id, v_parenttask_id, v_parentjob_id)::jobtask);
			-- get the maestro to wake the parent
			RAISE LOG 'NOTIFY "wait_for_children", %', (v_parentworkflow_id, v_parenttask_id, v_parentjob_id)::jobtask::text;
			PERFORM pg_notify('wait_for_children', (v_parentworkflow_id, v_parenttask_id, v_parentjob_id)::jobtask::text);
		ELSE
			-- remain a zombie, the parent will look for us sometime
			RAISE LOG 'parentjob % not waiting for us', v_parentjob_id;
			-- RETURN null; -- no next task
		END IF;
		RETURN null; -- no next task
	END IF;

	-- mark job as finished
	UPDATE
		jobs
	SET
		state = 'finished',
		job_finished = now(),
		task_started = now(),
		task_completed = now(),
		out_args = v_outargs
	WHERE
		job_id = a_jobtask.job_id
	RETURNING arguments INTO v_inargs;

	PERFORM do_cleanup_on_finish(a_jobtask);

	IF v_parentjob_id IS NULL THEN
		-- and let any waiting clients know
		RAISE NOTICE 'NOTIFY job:%:finished', a_jobtask.job_id;
		PERFORM pg_notify('job:finished', a_jobtask.job_id::TEXT);
		PERFORM pg_notify('job:' || a_jobtask.job_id || ':finished', '42');
		RETURN null; -- no next task
	END IF;

	-- sanity checks: we should have a parent waiting for us here
	IF NOT v_parentwait THEN
		RAISE EXCEPTION 'should not get here!';
	END IF;	

	-- sanity check parent
	SELECT
		workflow_id INTO
		v_parentworkflow_id
	FROM
		jobs
	WHERE
		job_id = v_parentjob_id
		AND task_id = v_parenttask_id
		AND state = 'childwait'
	FOR UPDATE OF jobs;
	
	IF NOT FOUND THEN
		-- what?
		RAISE EXCEPTION 'parentjob % not found?', v_parentjob_id;
	END IF;

	RAISE NOTICE 'child job % of parent job % done', a_jobtask.job_id, v_parentjob_id;

	v_parentjobtask := (v_parentworkflow_id, v_parenttask_id, v_parentjob_id)::jobtask;

	-- now do the task done processing for the parent
	BEGIN
		SELECT vars_changed, newvars INTO v_changed, v_newvars FROM do_outargsmap(v_parentjobtask, v_outargs);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(v_parentjobtask, format('caught exception in do_outargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;

	-- and continue with the parentjob
	RETURN do_task_epilogue(v_parentjobtask, v_changed, v_newvars, v_inargs, v_outargs);

END;$function$
