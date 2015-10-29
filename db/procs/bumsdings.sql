CREATE OR REPLACE FUNCTION jobcenter.bumsdings(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$DECLARE
	v_errargs jsonb;
BEGIN
	BEGIN
		--RAISE NOTICE 'before';
		PERFORM do_next_task(a_workflow_id, a_task_id, a_job_id);
		--RAISE NOTICE 'after';
	EXCEPTION
		WHEN raise_exception THEN
			RAISE NOTICE 'caught exception sqlerrm %', SQLERRM;
			v_errargs = jsonb_build_object('error', SQLERRM);
			PERFORM do_task_error(a_workflow_id, a_task_id, a_job_id, v_errargs);
		WHEN OTHERS THEN
			RAISE NOTICE 'caught exception sqlstate % sqlerrm %', SQLSTATE, SQLERRM;
			v_errargs = jsonb_build_object('error', SQLSTATE || ' ' || SQLERRM);
			PERFORM do_task_error(a_workflow_id, a_task_id, a_job_id, v_errargs);
	END;

	RETURN true;
END$function$
