CREATE OR REPLACE FUNCTION jobcenter.do_jobtaskerror(a_jobtask jobtask)
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
	v_outargs jsonb;
	v_aborted boolean;
	v_errargs jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT 
		on_error_task_id, parentjob_id, parenttask_id, parentwait, out_args, aborted
		INTO v_errortask_id, v_parentjob_id, v_parenttask_id, v_parentwait, v_outargs, v_aborted
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id
		AND state = 'error';
	
	IF NOT FOUND THEN
		RAISE EXCEPTION 'do_jobtaskerror called for job not in error state %', a_jobtask.job_id;
	END IF;	

	RAISE NOTICE 'v_erortask_id %, v_outargs %', v_errortask_id, v_outargs;
	IF v_errortask_id IS NOT NULL -- we have an error task
		AND v_outargs ? 'error' -- and some sort of error object
		AND (
			( v_outargs -> 'error' ? 'class' AND v_outargs #>> '{error,class}' <> 'fatal')
			OR (NOT v_outargs -> 'error' ? 'class') -- and the error is not fatal
		) THEN -- call errortask
		RAISE NOTICE 'calling errortask %', v_errortask_id;
		IF v_aborted THEN
			-- need to clear abort flag to prevent a loop
			UPDATE jobs SET aborted = false WHERE job_id = a_jobtask.job_id;
		END IF;
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
		timeout = null
	WHERE
		job_id = a_jobtask.job_id;

	PERFORM do_cleanup_on_finish(a_jobtask);

	IF v_parentjob_id IS NULL THEN
		-- throw error to the client
		RAISE NOTICE 'job:%:finished', a_jobtask.job_id;
		PERFORM pg_notify('job:finished', a_jobtask.job_id::TEXT);
		PERFORM pg_notify('job:' || a_jobtask.job_id || ':finished', '42');
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
			AND state = 'blocked';

		IF NOT FOUND THEN
			-- what?
			RAISE EXCEPTION 'parentjob % not found?', v_parentjob_id;
		END IF;

		v_errargs = jsonb_build_object(
			'error', jsonb_build_object(
				'msg', format('childjob %s raised error', a_jobtask.job_id),
				'class', 'childerror',
				'error', v_outargs -> 'error'
			)
		);

		-- fixme: copied from do_raise_error
		UPDATE jobs SET
			state = 'error',
			task_completed = now(),
			timeout = NULL,
			out_args = v_errargs
		WHERE job_id = v_parentjob_id;

		PERFORM do_log(v_parentjob_id, false, null, v_errargs);

		RETURN (true, (v_parentworkflow_id, v_parenttask_id, v_parentjob_id)::jobtask)::nextjobtask;
	END IF;

	-- check if the parent is already waiting for its children
	-- we need locking here to prevent a race condition with wait_for_child
	-- any deadlock error will be handled in the maestro
	--LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;
	--LOCK TABLE jobs IN SHARE MODE;

	-- and get parentworkflow_id for do_task_error
	RAISE NOTICE 'look for parent job %', v_parentjob_id;
	
	SELECT
		workflow_id, task_id INTO v_parentworkflow_id, v_parenttask_id
	FROM
		jobs
	WHERE
		job_id = v_parentjob_id
		AND state = 'blocked';

	IF FOUND THEN
		RAISE NOTICE 'unblock job %, error %', v_parentjob_id, v_outargs;
		-- and call do_task error
		-- FIXME: transform error object
		RETURN do_wait_for_children_task((v_parentworkflow_id, v_parenttask_id, v_parentjob_id)::jobtask);
		--PERFORM do_task_error(v_parentworkflow_id, v_parenttask_id, v_parentjob_id, v_outargs);
	END IF;

	RETURN null; -- no next task
END$function$
