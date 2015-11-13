CREATE OR REPLACE FUNCTION jobcenter.do_jobtask(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_action_type action_type;
	v_action_id int;
	v_actionname text;
	v_steps int;
BEGIN
	UPDATE jobs SET
		task_id = a_task_id,
		state = 'ready',
		task_entered = now(),
		task_started = null,
		task_completed = null,
		worker_id = null
	WHERE
		workflow_id = a_workflow_id
		AND job_id = a_job_id
		AND state IN ('plotting', 'error')
	RETURNING stepcounter INTO v_steps;

	IF NOT FOUND THEN
		RETURN null; -- or what?
	END IF;

	-- FIXME: make configurable
	IF v_steps > 50 THEN
		--RAISE EXCEPTION 'maximum steps exceeded: % > 50', v_steps;
		RETURN do_raise_fatal_error(a_workflow_id, a_task_id, a_job_id, format('maximum steps exceeded: %s > 50', v_steps));
	END IF;

	SELECT
		actions.type,
		actions.action_id,
		actions.name
		INTO v_action_type, v_action_id, v_actionname
	FROM
		tasks
		JOIN actions USING (action_id)
	WHERE
		task_id = a_task_id;

	CASE
		v_action_type
	WHEN 'system' THEN
		-- call the right system task handler
		CASE
			v_actionname
		WHEN 'start', 'no_op' THEN -- start is just a special no_op
			-- first mark job done
			UPDATE jobs SET
				state = 'done',
				task_started = now(),
				task_completed = now()
			WHERE
				job_id = a_job_id;
			/* naah.. to many nops
			-- log something 
			INSERT INTO job_task_log (job_id, workflow_id, task_id, task_entered, task_started, task_completed)
			SELECT job_id, workflow_id, task_id, task_entered, task_started, task_completed
			FROM jobs
			WHERE job_id = a_job_id; */
			RETURN do_jobtaskdone(a_workflow_id, a_task_id, a_job_id);
		WHEN 'end' THEN
			RETURN do_end_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'eval' THEN
			RETURN do_eval_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'branch' THEN
			RETURN do_branch_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'switch' THEN
			RETURN do_switch_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'reap_child' THEN
			RETURN do_reap_child_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'subscribe' THEN
			RETURN do_subscribe_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'unsubscribe' THEN
			RETURN do_unsubscribe_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'wait_for_event' THEN
			RETURN do_wait_for_event_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'raise_error' THEN
			RETURN do_raise_error_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'raise_event' THEN
			RETURN do_raise_event_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'wait_for_children' THEN
			RETURN do_wait_for_children_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'lock' THEN
			RETURN do_lock_task(a_workflow_id, a_task_id, a_job_id);
		WHEN 'unlock' THEN
			RETURN do_unlock_task(a_workflow_id, a_task_id, a_job_id);
		ELSE
			-- FIXME: call do_raise_error instead?
			RAISE EXCEPTION 'unknown system task %', v_actionname;
		END CASE;
	WHEN 'workflow' THEN
		-- start subflow
		RETURN do_create_childjob(a_workflow_id, a_task_id, a_job_id);
	WHEN 'action' THEN
		-- notify workers
		RETURN do_prepare_for_action(a_workflow_id, a_task_id, a_job_id);
	ELSE
		-- should not happen
		RAISE EXCEPTION 'unknown action_type % for task_id %', v_action_type, a_task_id;
	END CASE;

	-- should not get here
	RETURN null;
EXCEPTION
	WHEN deadlock_detected THEN
	-- just retry current step
	RAISE NOTICE 'deadlock detected, retrying jobtask';
	RETURN nexttask(false, a_workflow_id, a_task_id, a_job_id);
END
$function$
