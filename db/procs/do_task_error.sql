CREATE OR REPLACE FUNCTION jobcenter.do_task_error(a_jobtask jobtask, a_errargs jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
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
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id;
	
	PERFORM do_log(a_jobtask.job_id, false, null, a_errargs);

	-- wake up maestro
	--RAISE NOTICE 'NOTIFY "jobtaskdone", %', (v_workflow_id::TEXT || ':' || v_task_id::TEXT || ':' || v_job_id::TEXT );
	PERFORM pg_notify( 'jobtaskerror',  a_jobtask::text );
END$function$
