CREATE OR REPLACE FUNCTION jobcenter.do_wait_for_children_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_state job_state;
	v_task_id int;
	v_waitjobtask jobtask;
	v_childjob_id bigint;
	v_in_args jsonb;
	v_errargs jsonb;
	v_out_args jsonb;
	v_changed boolean;
	v_newvars jsonb;
BEGIN
	-- this functions can be called in two ways:
	-- 1. from do_jobtask directly
	-- 2. from do_end_task of a child job (only in the non-wait case)
	-- in either way the current job task should be a wait_for_children task
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
		AND state in  ('ready','childwait')
		AND actions.type = 'system'
		AND actions.name = 'wait_for_children'
	FOR UPDATE OF jobs;

	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_wait_for_children called for non-do_wait_for_children-task %', a_jobtask;
	END IF;

	-- HACK: because we may be called from do_end_task of our childjobs the task_id in a_jobtask can be
	-- that of the task that spawned that childjob. create a usable jobtask tuple here
	v_waitjobtask = (a_jobtask.workflow_id, v_task_id, a_jobtask.job_id)::jobtask;

	IF v_state = 'ready' THEN
		-- mark job as waiting for children
		-- we need locking here to prevent a race condition with do_end_task
		-- any deadlock error will be handled in do_jobtask		
		--LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;

		UPDATE jobs SET
			state = 'childwait',
			task_started = now()
		WHERE
			job_id = a_jobtask.job_id;
	END IF;

	RAISE NOTICE 'look for children of job %', a_jobtask.job_id;

	-- check for errors
	SELECT
		job_id, out_args INTO v_childjob_id, v_out_args 
	FROM
		jobs 
	WHERE
		parentjob_id = a_jobtask.job_id
		AND state = 'error'
	LIMIT 1; -- FIXME: order?

	IF FOUND THEN -- raise error
		v_errargs = jsonb_build_object(
			'error', jsonb_build_object(
				'msg', format('childjob %s raised error', v_childjob_id),
				'class', 'childerror',
				'error', v_out_args -> 'error'
			)
		);
		UPDATE jobs SET
			state = 'error',
			task_completed = now(),
			timeout = NULL,
			out_args = v_errargs
		WHERE job_id = a_jobtask.job_id;
		PERFORM do_log(a_jobtask.job_id, false, null, v_errargs);
		RETURN (true, v_waitjobtask)::nextjobtask;
	END IF;

	-- check if all children are finished
	PERFORM * FROM jobs WHERE parentjob_id = a_jobtask.job_id AND state <> 'zombie' FOR UPDATE OF jobs;

	IF FOUND THEN -- not finished
		-- the childjob will unblock us when it is finished (we hope)
		RAISE NOTICE 'not all children of job % are zombies yet', a_jobtask.job_id;
		RETURN null;
	END IF;

	RAISE NOTICE 'all children of % are zombies', a_jobtask.job_id;

	-- a reap_child_job task will to the actual reaping
	RETURN do_task_epilogue(v_waitjobtask, false, null, null, null);
END
$function$
