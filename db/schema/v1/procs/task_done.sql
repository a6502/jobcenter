CREATE OR REPLACE FUNCTION jobcenter.task_done(a_jobcookie text, a_out_args jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_job_id bigint;
	v_workflow_id int;
	v_task_id int;
BEGIN
	RAISE NOTICE 'task_done(%, %)', a_jobcookie, a_out_args;

	UPDATE jobs SET
		cookie = NULL
	WHERE
		cookie = a_jobcookie::uuid
		AND state IN ('working')
	RETURNING  job_id, task_id, workflow_id INTO v_job_id, v_task_id, v_workflow_id;

	IF NOT FOUND THEN
		--RAISE EXCEPTION 'no working job found for eventcookie %', a_jobcookie;
		-- maybe the job got aborted?
		RETURN;
	END IF;	

	PERFORM do_task_done(v_workflow_id, v_task_id, v_job_id, a_out_args, true);
END$function$
