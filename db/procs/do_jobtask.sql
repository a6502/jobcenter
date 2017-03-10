CREATE OR REPLACE FUNCTION jobcenter.do_jobtask(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_action_type action_type;
	v_action_id int;
	v_actionname text;
	v_steps int;
	v_max_steps int;
	v_aborted boolean;
	v_nexttask_id int;
BEGIN
	UPDATE jobs SET
		task_id = a_jobtask.task_id,
		cookie = null,
		out_args = null,
		state = 'ready',
		task_entered = now(),
		task_started = null,
		task_completed = null,
		task_state = null,
		timeout = null
	WHERE
		workflow_id = a_jobtask.workflow_id
		AND job_id = a_jobtask.job_id
		AND state IN ('plotting', 'error')
	RETURNING stepcounter, max_steps, aborted INTO v_steps, v_max_steps, v_aborted;

	IF NOT FOUND THEN
		RETURN null; -- or what?
	END IF;

	-- check for fatal errors first
	IF v_steps > v_max_steps THEN
		-- raise fatal error
		RETURN do_raise_error(a_jobtask, format('maximum step count exceeded: %s > %s', v_steps, v_max_steps), 'fatal');
	END IF;

	IF v_aborted THEN
		-- raise abort error
		RETURN do_raise_error(a_jobtask, 'aborted by parent job', 'abort');
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
		task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id;

	CASE
		v_action_type
	WHEN 'system' THEN
		-- call the right system task handler
		CASE
			v_actionname
		WHEN 'start', 'no_op' THEN -- start is just a special no_op
			-- don't log, just go straight to the next task
			UPDATE jobs SET
				state = 'plotting',
				task_started = now(),
				task_completed = now()
			WHERE
				job_id = a_jobtask.job_id;

			SELECT next_task_id INTO STRICT v_nexttask_id FROM tasks WHERE task_id = a_jobtask.task_id;

			IF v_nexttask_id = a_jobtask.task_id THEN
				RAISE EXCEPTION 'next_task_id equals task_id %', a_jobtask.task_id;
			END IF;

			RETURN (false, (a_jobtask.workflow_id, v_nexttask_id, a_jobtask.job_id)::jobtask)::nextjobtask;
		WHEN 'end' THEN
			RETURN do_end_task(a_jobtask);
		WHEN 'eval' THEN
			RETURN do_eval_task(a_jobtask);
		WHEN 'branch' THEN
			RETURN do_branch_task(a_jobtask);
		WHEN 'switch' THEN
			RETURN do_switch_task(a_jobtask);
		WHEN 'reap_child' THEN
			RETURN do_reap_child_task(a_jobtask);
		WHEN 'subscribe' THEN
			RETURN do_subscribe_task(a_jobtask);
		WHEN 'unsubscribe' THEN
			RETURN do_unsubscribe_task(a_jobtask);
		WHEN 'wait_for_event' THEN
			RETURN do_wait_for_event_task(a_jobtask);
		WHEN 'raise_error' THEN
			RETURN do_raise_error_task(a_jobtask);
		WHEN 'raise_event' THEN
			RETURN do_raise_event_task(a_jobtask);
		WHEN 'wait_for_children' THEN
			RETURN do_wait_for_children_task(a_jobtask);
		WHEN 'lock' THEN
			RETURN do_lock_task(a_jobtask);
		WHEN 'unlock' THEN
			RETURN do_unlock_task(a_jobtask);
		WHEN 'sleep' THEN
			RETURN do_sleep_task(a_jobtask);
		ELSE
			-- FIXME: call do_raise_error instead?
			RAISE EXCEPTION 'unknown system task %', v_actionname;
		END CASE;
	WHEN 'workflow' THEN
		-- start subflow
		RETURN do_create_childjob(a_jobtask);
	WHEN 'action' THEN
		-- notify workers
		RETURN do_prepare_for_action(a_jobtask);
	WHEN 'procedure' THEN
		-- call stored procedure
		RETURN do_call_stored_procedure(a_jobtask);
	ELSE
		-- should not happen
		RAISE EXCEPTION 'unknown action_type % for task_id %', v_action_type, a_jobtask.task_id;
	END CASE;

	-- should not get here
	RETURN null;
END
$function$
