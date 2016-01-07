CREATE OR REPLACE FUNCTION jobcenter.do_raise_error(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_errmsg text)
 RETURNS nexttask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_error jsonb;
BEGIN
	v_error = jsonb_build_object(
		'error', jsonb_build_object(
			'msg', a_errmsg,
			'class', 'normal'
		)
	);

	UPDATE jobs SET
		state = 'error',
		task_completed = now(),
		waitfortask_id = NULL,
		timeout = NULL,
		out_args = v_error
	WHERE job_id = a_job_id;
	INSERT INTO job_task_log (job_id, workflow_id, task_id, variables, task_entered, task_started,
			task_completed, worker_id, task_outargs)
		SELECT job_id, workflow_id, task_id, variables, task_entered, task_started,
			task_completed, worker_id, out_args as task_outargs
		FROM jobs
		WHERE job_id = a_job_id;		

	RETURN nexttask(true, a_workflow_id, a_task_id, a_job_id);
END$function$
