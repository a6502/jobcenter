CREATE OR REPLACE FUNCTION jobcenter.do_wait_for_children_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$BEGIN
	-- this function can be called in two ways:
	-- 1. from do_jobtask directly
	-- 1. directly by the maestro
	-- 2. from do_end_task of a child job (only in the non-wait case)
	-- in either way the current job task should be a wait_for_children task
	-- paranoia check
	UPDATE jobs SET
		state = 'childwait',
		task_started = now()
	WHERE job_id = (SELECT
		job_id
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND workflow_id = a_jobtask.workflow_id
		AND task_id = a_jobtask.task_id
		AND state = 'ready'
		AND actions.type = 'system'
		AND actions.name = 'wait_for_children');

	IF NOT FOUND THEN
		RAISE EXCEPTION 'do_wait_for_children called for non-do_wait_for_children-task %', a_jobtask;
	END IF;

	-- we need to use the notification here as well because
	-- otherwise we run into deadlocks in do_wait_for_children
	RAISE LOG 'NOTIFY "wait_for_children", %', a_jobtask::text;
	PERFORM pg_notify('wait_for_children', a_jobtask::text);

	RETURN null;
END
$function$
