CREATE OR REPLACE FUNCTION jobcenter.do_task_epilogue(a_jobtask jobtask, a_vars_changed boolean, a_newvars jsonb, a_inargs jsonb, a_outargs jsonb)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_nexttask_id int;
BEGIN
	-- the task prologue is in do_jobtask
	-- this implements the most common epilogue
	-- some tasks may have to implement their own versions

	UPDATE jobs SET
		state = 'plotting',
		variables = CASE WHEN a_vars_changed THEN a_newvars ELSE variables END,
		task_started = CASE WHEN task_started IS NULL THEN now() ELSE task_started END,
		task_completed = now()
	WHERE job_id = a_jobtask.job_id;

	PERFORM do_log(a_jobtask.job_id, a_vars_changed, a_inargs, a_outargs);

	SELECT next_task_id INTO STRICT v_nexttask_id FROM tasks WHERE task_id = a_jobtask.task_id;

	IF v_nexttask_id = a_jobtask.task_id THEN
		RAISE EXCEPTION 'next_task_id equals task_id %', a_jobtask.task_id;
	END IF;

	RETURN (false, (a_jobtask.workflow_id, v_nexttask_id, a_jobtask.job_id)::jobtask)::nextjobtask;
END$function$
