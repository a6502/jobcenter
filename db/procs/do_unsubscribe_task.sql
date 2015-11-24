CREATE OR REPLACE FUNCTION jobcenter.do_unsubscribe_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_action_id int;
	v_name text;
	v_inargs jsonb;
	v_mask jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, environment, variables, action_id INTO v_args, v_env, v_vars, v_action_id
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_job_id
		AND task_id = a_task_id
		AND workflow_id = a_workflow_id
		AND actions.type = 'system'
		AND actions.name = 'unsubscribe';


	IF NOT FOUND THEN
		-- FIXME: call do_raiseerror instead?
		RAISE EXCEPTION 'do_unsubscribe called for non-unsubscribe-task %', a_task_id;		
	END IF;

	BEGIN
		v_inargs := do_inargsmap(v_action_id, a_task_id, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
	
	v_name := v_inargs->>'name';

	DELETE FROM event_subscriptions WHERE job_id = a_job_id AND "name" = v_name;
	-- fkey cascaded delete should delete from job_events
	-- now delete events that no-one is waiting for anymore
	-- FIXME: use knowledge of what was deleted?
	DELETE FROM queued_events WHERE event_id NOT IN (SELECT event_id FROM job_events);

	UPDATE jobs SET
		state = 'done',
		task_started = now(),
		task_completed = now()
	WHERE
		job_id = a_job_id;
	-- log something
	INSERT INTO job_task_log (job_id, workflow_id, task_id, task_entered, task_started, task_completed)
	SELECT job_id, workflow_id, task_id, task_entered, task_started, task_completed
	FROM jobs
	WHERE job_id = a_job_id;

	RETURN do_jobtaskdone(a_workflow_id, a_task_id, a_job_id);
END;$function$
