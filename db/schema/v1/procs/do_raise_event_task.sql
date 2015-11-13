CREATE OR REPLACE FUNCTION jobcenter.do_raise_event_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_vars jsonb;
	v_code text;
	v_action_id int;
	v_inargs jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, variables, imapcode, action_id INTO v_args, v_vars, v_code, v_action_id
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_job_id
		AND task_id = a_task_id
		AND workflow_id = a_workflow_id
		AND state = 'ready'
		AND actions.type = 'system'
		AND actions.name = 'raise_event';		

	IF NOT FOUND THEN
		-- FIXME: should not happen, as this is an internal function
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_raise_event_task called for non raise_event task %', a_task_id;
	END IF;

	BEGIN
		v_inargs := do_inargsmap(v_action_id, a_task_id, v_args, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
	
	RAISE NOTICE 'do_raise_event_task v_inargs %', v_inargs;

	-- (do_inargsmap has made sure those fields exist?)

	PERFORM raise_event(v_inargs->'event');

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
