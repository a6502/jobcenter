CREATE OR REPLACE FUNCTION jobcenter.task_failed(a_cookie text, a_errmsg text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_job_id bigint;
	v_workflow_id int;
	v_task_id int;
	v_errargs jsonb;
BEGIN
	RAISE NOTICE 'task_failed(%, %)', a_jobcookie, a_errormsg;

	UPDATE jobs SET
		cookie = NULL
	WHERE
		cookie = a_jobcookie::uuid
		AND state IN ('working')
	RETURNING  job_id, task_id, workflow_id INTO v_job_id, v_task_id, v_workflow_id;

	IF NOT FOUND THEN
		-- FIXME: or just return silently?
		--RAISE EXCEPTION 'no working job found for eventcookie %', a_jobcookie;
		RETURN;
	END IF;	

	v_errargs = jsonb_build_object(
		'error', jsonb_build_object(
			'class', 'trappable',
			'msg', a_errmsg
		)
	);	
	-- v_errargs = jsonb_build_object('error', v_errarrgs);

	PERFORM do_task_error((v_workflow_id, v_task_id, v_job_id)::jobtask, v_errargs);
END$function$
