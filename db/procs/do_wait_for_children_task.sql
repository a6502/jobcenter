CREATE OR REPLACE FUNCTION jobcenter.do_wait_for_children_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_state job_state;
	v_childjob_id bigint;
	v_action_type action_type;
	v_errargs jsonb;
	v_out_args jsonb;
BEGIN
	-- this functions can be called in two ways:
	-- 1. from do_jobtask direcetly
	-- 2. from do_end_task of a child job.
	-- paranoia check
	SELECT
		state, actions.type INTO v_state, v_action_type
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_job_id
		AND workflow_id = a_workflow_id
		AND task_id= a_task_id
		AND state IN ('ready', 'blocked')
		AND (
			(actions.type = 'system' AND actions.name = 'wait_for_children')
			OR (actions.type = 'workflow' and tasks.wait = true)
		);

	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_wait_for_children called for non-do_wait_for_children-task %', a_task_id;
	END IF;

	IF v_state = 'ready' THEN
		-- mark job as blocked
		-- we need locking here to prevent a race condition with wait_for_children
		-- any deadlock error will be handled in do_jobtask		
		LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;

		UPDATE jobs SET
			state = 'blocked',
			task_started = now()
		WHERE
			job_id = a_job_id;
	END IF;

	RAISE NOTICE 'look for children of job %', a_job_id;

	-- check for errors
	SELECT
		job_id, out_args INTO v_childjob_id, v_errargs 
	FROM
		jobs 
	WHERE
		parentjob_id = a_job_id
		AND state = 'error'
	LIMIT 1; -- FIXME: order?

	IF FOUND THEN -- raise error
		v_errargs = jsonb_build_object(
			'error', jsonb_build_object(
				'msg', format('childjob %s raised error', v_childjob_id),
				'class', 'childerror',
				'error', v_errargs -> 'error'
			)
		);
		PERFORM do_task_error(a_workflow_id, a_task_id, a_job_id, v_errargs);
		RETURN null;
	END IF;

	-- check if all children are finished
	PERFORM * FROM jobs WHERE parentjob_id = a_job_id AND state <> 'zombie';

	IF FOUND THEN -- not finished
		-- the childjob will unblock us when it is finished (we hope)
		RAISE NOTICE 'child not found %', now();
		RETURN null;
	END IF;

	RAISE NOTICE 'all children of % are zombies', a_job_id;

	IF v_action_type = 'workflow' THEN
		-- reap child directly
		UPDATE
			jobs
		SET
			state = 'finished',
			job_finished = now(),
			task_completed = now()
		WHERE
			parenttask_id = a_task_id
			AND parentjob_id = a_job_id
			AND state = 'zombie'
		RETURNING job_id, out_args INTO v_childjob_id, v_out_args;

		RAISE NOTICE 'child job % done', v_childjob_id;
		-- mark us as done
		PERFORM do_task_done(a_workflow_id, a_task_id, a_job_id, v_out_args, false);

	ELSE
		-- a reap_child_job task will to the reaping
		-- mark as done so that do_jobtaskdone works
		UPDATE jobs SET
			state = 'done',
			task_completed = now()
		WHERE
			job_id = a_job_id;
	END IF;

	RETURN do_jobtaskdone(a_workflow_id, a_task_id, a_job_id);
END
$function$
