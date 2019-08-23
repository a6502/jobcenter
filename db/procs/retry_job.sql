CREATE OR REPLACE FUNCTION jobcenter.retry_job(a_job_id bigint, a_reason text DEFAULT ''::text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_workflow_id int;
	v_task_id int;
	v_job_finished timestamp with time zone;
	v_state job_state;
BEGIN
	SELECT
		workflow_id, job_finished, state
		INTO v_workflow_id, v_job_finished, v_state
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

	IF v_state <> 'error' THEN
		RETURN format('job %s is not in state error', a_job_id);
	END IF;

	IF v_job_finished IS NULL THEN
		RETURN format('job %s is not finished', a_job_id);
	END IF;

	-- ok, now find the start task of the workflow
	SELECT 
		t.task_id INTO v_task_id
	FROM
		tasks AS t
		JOIN actions AS a ON t.action_id = a.action_id
	WHERE
		t.workflow_id = v_workflow_id
		AND a.type = 'system'
		AND a.name = 'start';

	-- should exist?

	UPDATE
		jobs
	SET
		task_id = v_task_id,
		state = 'done',
		stepcounter = 0,
		job_finished = NULL, -- unfinish..
		task_entered = now(),
		task_started = now(),
		task_completed = now(),
		task_state = NULL,
		timeout = NULL
	WHERE
		job_id = a_job_id;

	PERFORM do_log(a_job_id, false, jsonb_build_object('retry initiated', a_reason), null);

	-- wake up maestro
	--RAISE NOTICE 'NOTIFY "jobtaskdone", %', (v_workflow_id::TEXT || ':' || v_task_id::TEXT || ':' || o_job_id::TEXT );
	PERFORM pg_notify( 'jobtaskdone',  ( '(' || v_workflow_id || ',' || v_task_id || ',' || a_job_id || ')' ));

	RETURN 'retry initiated';
END$function$
