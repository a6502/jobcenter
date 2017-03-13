CREATE OR REPLACE FUNCTION jobcenter.do_raise_error(a_jobtask jobtask, a_errmsg text, a_class text DEFAULT 'normal'::text)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_error jsonb;
BEGIN
	v_error = jsonb_build_object(
		'error', jsonb_build_object(
			'msg', a_errmsg,
			'class', a_class
		)
	);

	UPDATE jobs SET
		state = 'error',
		task_completed = now(),
		timeout = NULL,
		task_state = COALESCE(task_state, '{}'::jsonb) || v_error
	WHERE job_id = a_jobtask.job_id;
	PERFORM do_log(a_jobtask.job_id, false, null, v_error);

	RETURN (true, a_jobtask)::nextjobtask;
END$function$
