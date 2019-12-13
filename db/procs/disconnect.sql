CREATE OR REPLACE FUNCTION jobcenter.disconnect(a_workername text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'jobcenter', 'pg_catalog', 'pg_temp'
AS $function$DECLARE
	v_worker_id bigint;
	v_error jsonb;
	v_job_id bigint;
	v_task_id int;
	v_workflow_id int;
BEGIN
	UPDATE workers SET
		stopped = now()
	WHERE
		name = a_workername
		AND stopped IS NULL
	RETURNING
		worker_id INTO v_worker_id;

	IF NOT FOUND THEN
		RETURN FALSE;
	END IF;

        RAISE LOG 'disconnect for % (%)', a_workername, v_worker_id;

	DELETE FROM
		 worker_actions
	WHERE worker_id = v_worker_id;

	-- add workername to msg?
	v_error := '{"error":{"class": "soft", "msg": "worker disconnected"}}'::jsonb;

	FOR v_job_id, v_task_id, v_workflow_id IN
		SELECT
			 job_id, task_id, workflow_id
		FROM
			jobs
			JOIN tasks USING (workflow_id, task_id)
			JOIN actions USING (action_id)
		WHERE
			state = 'working'
			AND (task_state->>'worker_id')::bigint = v_worker_id
			AND (config->>'retryable')::boolean = true
	LOOP
		RAISE LOG 'raising error in %', (v_workflow_id, v_task_id, v_job_id)::jobtask;
		PERFORM do_task_error((v_workflow_id, v_task_id, v_job_id)::jobtask, v_error);
	END LOOP;

	RETURN TRUE;
END$function$
