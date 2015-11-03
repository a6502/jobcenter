CREATE OR REPLACE FUNCTION jobcenter.do_jobtaskdone(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$DECLARE
	v_nexttask nexttask;
	v_nexttask_id int;
BEGIN
	--RAISE NOTICE 'do_next_task % % %', a_workflow_id, a_task_id, a_job_id;

	UPDATE jobs
		SET state = 'plotting'
	WHERE
		job_id = a_job_id
		AND task_id = a_task_id
		AND workflow_id = a_workflow_id
		AND state = 'done';
	
	IF NOT FOUND THEN
		-- FIXME: ignore? throw error?
		RETURN null;
	END IF;
	
	SELECT next_task_id INTO STRICT v_nexttask_id FROM tasks WHERE task_id = a_task_id;

	IF v_nexttask_id = a_task_id THEN
		RAISE EXCEPTION 'next_task_id equals task_id %', a_task_id;
	END IF;

	--RAISE NOTICE 'v_nexttask_id: %', v_nexttask_id;
	
	RETURN nexttask(false, a_workflow_id, v_nexttask_id, a_job_id);
END$function$
