CREATE OR REPLACE FUNCTION jobcenter.do_eval_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_oldvars jsonb;
	v_code text;
	v_newvars jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, environment, variables, imapcode INTO v_args, v_env, v_oldvars, v_code
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
		AND actions.name = 'eval';		

	IF NOT FOUND THEN
		-- FIXME: should not happen, as this is an internal function
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_eval_task called for non eval task %', a_task_id;
	END IF;

	BEGIN
		v_newvars := do_eval(v_code, v_args, v_oldvars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, format('caught exception in do_eval sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;

	IF v_newvars IS DISTINCT FROM v_oldvars THEN
		UPDATE jobs SET
			state = 'done',
			variables = v_newvars,
			task_started = now(),
			task_completed = now()
		WHERE job_id = a_job_id;
		INSERT INTO job_task_log (job_id, workflow_id, task_id, variables, task_entered, task_started,
				task_completed, worker_id)
			SELECT job_id, workflow_id, task_id, variables, task_entered, task_started,
				task_completed, worker_id
			FROM jobs
			WHERE job_id = a_job_id;		
	ELSE
		UPDATE jobs SET
			state = 'done',
			task_started = now(),
			task_completed = now()
		WHERE job_id = a_job_id;
		INSERT INTO job_task_log (job_id, workflow_id, task_id, task_entered, task_started,
				task_completed, worker_id)
			SELECT job_id, workflow_id, task_id, task_entered, task_started, task_completed,
				worker_id
			FROM jobs
			WHERE job_id = a_job_id;		
	END IF;

	RETURN do_jobtaskdone(a_workflow_id, a_task_id, a_job_id);
END;$function$
