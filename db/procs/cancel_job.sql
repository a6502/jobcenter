CREATE OR REPLACE FUNCTION jobcenter.cancel_job(a_job_id bigint, a_reason text DEFAULT ''::text, a_force boolean DEFAULT false)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_workflow_id int;
	v_task_id int;
	v_action_id int;
	v_state job_state;
	v_job_finished timestamp with time zone;
	v_error jsonb;
	v_res text;
BEGIN
	SELECT
		workflow_id, task_id, action_id, job_finished, state
		INTO v_workflow_id, v_task_id, v_action_id, v_job_finished, v_state
	FROM 
		actions
		JOIN tasks USING (action_id)
		JOIN jobs USING (workflow_id, task_id)
	WHERE
		job_id = a_job_id
	FOR UPDATE OF jobs;

	IF NOT FOUND THEN
		RETURN format('job %s not found', a_job_id);
	END IF;

	IF v_job_finished IS NOT NULL THEN
		RETURN format('job %s already finished', a_job_id);
	END IF;

	CASE
		v_state
	WHEN 'ready', 'working', 'eventwait', 'sleeping', 'done', 'plotting', 'retrywait', 'lockwait', 'error', 'zombie', 'childwait' THEN

		IF v_state IN ('working', 'done', 'plotting') AND a_force = false THEN
			RETURN format('refusing to cancel job %s in state %s without force flag', a_job_id, v_state);
		END IF;

		v_error := jsonb_build_object(
			'error', jsonb_build_object(
				'msg', format('job cancelled: %s', a_reason),
				'class', 'fatal'
			)
		);

		UPDATE
			jobs
		SET
			state = 'error',
			task_started = COALESCE(task_started, now()),
			task_entered = COALESCE(task_entered, now()),
			task_completed = now(),
			task_state = COALESCE(task_state, '{}'::jsonb) || v_error,
			timeout = NULL
		WHERE
			job_id = a_job_id;

		-- call the normal processing with some extra magic
		PERFORM do_jobtaskerror((v_workflow_id, v_task_id, a_job_id)::jobtask, true);

		RETURN format('job %s cancelled', a_job_id);

	--WHEN 'zombie' THEN
	--	RETURN format('cancel parent job of %s instead', a_job_id);
	--WHEN 'childwait' THEN
	--	RETURN format('cancel child job of %s instead', a_job_id);
	WHEN 'finished' THEN
		RETURN format('huh? job %s in state finished but job_finsihed is null??', a_job_id);
	ELSE
		RETURN format('unknown job state %s for job %s', v_state, a_job_id);
	END CASE;		

	-- not reached
END$function$
