CREATE OR REPLACE FUNCTION jobcenter.do_jobtaskdone(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_nexttask_id int;
BEGIN
	RAISE NOTICE 'do_jobtaskdone(%, %, %)', a_jobtask.workflow_id, a_jobtask.task_id, a_jobtask.job_id;

	UPDATE jobs
		SET state = 'plotting'
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id
		AND state = 'done';
	
	IF NOT FOUND THEN
		-- FIXME: ignore? throw error?
		RETURN null;
	END IF;
	
	SELECT next_task_id INTO STRICT v_nexttask_id FROM tasks WHERE task_id = a_jobtask.task_id;

	IF v_nexttask_id = a_jobtask.task_id THEN
		RAISE EXCEPTION 'next_task_id equals task_id %', a_jobtask.task_id;
	END IF;

	--RAISE NOTICE 'v_nexttask_id: %', v_nexttask_id;
	
	RETURN (false, (a_jobtask.workflow_id, v_nexttask_id, a_jobtask.job_id)::jobtask)::nextjobtask;
END$function$
