CREATE OR REPLACE FUNCTION jobcenter.do_task_error(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_errargs jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$DECLARE
	v_oldvars jsonb;
BEGIN
	UPDATE jobs SET
		state = 'error',
		task_completed = now(),
		waitfortask_id = NULL,
		cookie = NULL,
		timeout = NULL,
		out_args = a_errargs
	WHERE
		job_id = a_job_id
		AND task_id = a_task_id
		AND workflow_id = a_workflow_id
		AND state IN ('working','waiting','sleeping','blocked');

	IF NOT FOUND THEN
		RETURN;
	END IF;
	
	INSERT INTO job_task_log (job_id, workflow_id, task_id, variables, task_entered, task_started,
			task_completed, worker_id, task_outargs)
		SELECT job_id, workflow_id, task_id, variables, task_entered, task_started,
			task_completed, worker_id, a_errargs as task_outargs
		FROM jobs
		WHERE job_id = a_job_id;		

	-- wake up maestro
	--RAISE NOTICE 'NOTIFY "jobtaskdone", %', (v_workflow_id::TEXT || ':' || v_task_id::TEXT || ':' || v_job_id::TEXT );
	PERFORM pg_notify( 'jobtaskerror',  (a_workflow_id::TEXT || ':' || a_task_id::TEXT || ':' || a_job_id::TEXT ));
END$function$
