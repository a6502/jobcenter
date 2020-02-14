CREATE OR REPLACE FUNCTION jobcenter.do_wait_for_children(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_state job_state;
	v_task_id int;
	v_waitjobtask jobtask;
	v_childjob_id bigint;
	v_in_args jsonb;
	v_errargs jsonb;
	v_childerr jsonb;
BEGIN
	-- this could end up being called a lot, so try to bail out as early as possible


	-- but first we need to serialize accesses to the parent job
	-- and we need to do that before we hold any other locks
	PERFORM pg_advisory_xact_lock(a_jobtask.job_id);

	-- this function is called directly by the maestro in reponse to a notification
	-- the current jobs task should be a wait_for_children task
	-- but the task_id we got in the arguments might be of the create_childjob task
	-- paranoia check
	SELECT
		task_id, state INTO v_task_id, v_state
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND workflow_id = a_jobtask.workflow_id
		--AND task_id = a_jobtask.task_id
		AND state = 'childwait'
		AND actions.type = 'system'
		AND actions.name = 'wait_for_children';

	IF NOT FOUND THEN
		-- this can happen because all children call us on finish so some other
		-- notification might already have done this
		RAISE LOG 'bailing out of wait_for_children job % task %', a_jobtask.job_id, a_jobtask.task_id;
		RETURN null;
	END IF;

	-- because we may be called from do_end_task of our childjobs the task_id in a_jobtask can be
	-- that of the task that spawned that childjob. create a usable jobtask tuple here
	v_waitjobtask = (a_jobtask.workflow_id, v_task_id, a_jobtask.job_id)::jobtask;

	RAISE LOG 'look for children of job %', a_jobtask.job_id;

	-- check for errors
	SELECT
		job_id, COALESCE(task_state->'error', '{"msg":"uh?"}'::jsonb) INTO v_childjob_id, v_childerr
	FROM
		jobs 
	WHERE
		parentjob_id = a_jobtask.job_id
		AND job_finished IS NOT NULL
		AND state = 'error'
	FETCH FIRST ROW ONLY FOR UPDATE OF jobs; -- FIXME: order?

	IF FOUND THEN -- raise error
		v_errargs = jsonb_build_object(
			'error', jsonb_build_object(
				'msg', format('childjob %s raised error', v_childjob_id),
				'class', 'childerror',
				'error', v_childerr
			)
		);
		UPDATE jobs SET
			state = 'error',
			task_completed = now(),
			timeout = NULL,
			out_args = NULL,
			task_state = COALESCE(task_state, '{}'::jsonb) || v_errargs
		WHERE job_id = a_jobtask.job_id;
		PERFORM do_log(a_jobtask.job_id, false, null, v_errargs);
		RETURN (true, v_waitjobtask)::nextjobtask;
	END IF;

	BEGIN
		PERFORM * FROM jobs WHERE 
			parentjob_id = a_jobtask.job_id
			AND state <> 'zombie'
			AND job_finished IS null
			FOR KEY SHARE OF jobs NOWAIT;
			-- using locking here can lead to deadlocks with unrelated queries (task_done)
			-- so we try to be as gentle as possible

		IF FOUND THEN -- not finished
			-- the childjob will unblock us when it is finished (we hope)
			RAISE LOG 'not all children of job % are zombies yet', a_jobtask.job_id;
			RETURN null;
		END IF;

		RAISE LOG 'all children of % are zombies', a_jobtask.job_id;

		-- a reap_child_job task will to the actual reaping
		RETURN do_task_epilogue(v_waitjobtask, false, null, null, null);

	EXCEPTION WHEN lock_not_available THEN
		-- loop after waiting for a bit
		RAISE LOG 'could not get share lock on all children of job %', a_jobtask.job_id;
		PERFORM pg_notify('wait_for_children', a_jobtask::text);
		RETURN null;
	END;

	-- not reached
END
$function$
