CREATE OR REPLACE FUNCTION jobcenter.do_jobtaskerror(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_errortask_id int;
	v_parentjob_id bigint;
	v_parenttask_id int;
	v_parentwaitfortask_id int;	
	v_parentworkflow_id int;
	v_outargs jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT 
		on_error_task_id, parentjob_id, parenttask_id, out_args
		INTO v_errortask_id, v_parentjob_id, v_parentwaitfortask_id, v_outargs
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
	WHERE
		job_id = a_job_id
		AND task_id = a_task_id
		AND workflow_id = a_workflow_id
		AND state = 'error';
	
	IF NOT FOUND THEN
		RAISE EXCEPTION 'do_jobtaskerror called for job not in error state %', a_job_id;
	END IF;	

	IF v_errortask_id IS NOT NULL
	   AND v_outargs ? 'class' 
	   AND v_outargs ->> 'class' <> 'fatal' THEN
		RAISE NOTICE 'calling errortask %', v_errortask_id;
		RETURN nexttask(false, a_workflow_id, a_task_id, a_job_id);
	END IF;

	-- default error behaviour:
	-- first mark job finished
	UPDATE
		jobs
	SET
		job_finished = now(),
		task_started = now(),
		task_completed = now(),
		timeout = null
	WHERE
		job_id = a_job_id;

	IF v_parentjob_id IS NULL THEN
		-- throw error to the client
		RAISE NOTICE 'job:%:finished', a_job_id;
		PERFORM pg_notify('job:finished', a_job_id::TEXT);
		PERFORM pg_notify('job:' || a_job_id || ':finished', '42');
		RETURN NULL;
	END IF;

	-- raise error in parent

	-- check if the parent is already waiting for its children
	-- we need locking here to prevent a race condition with wait_for_child
	-- any deadlock error will be handled in the maestro
	--LOCK TABLE jobs IN SHARE ROW EXCLUSIVE MODE;
	LOCK TABLE jobs IN SHARE MODE;

	-- and get parentworkflow_id for do_task_error
	RAISE NOTICE 'look for parent job % task %', v_parentjob_id, v_parentwaitfortask_id;
	
	SELECT
		workflow_id, task_id INTO v_parentworkflow_id, v_parenttask_id
	FROM
		jobs
	WHERE
		job_id = v_parentjob_id
		AND state = 'blocked';

	IF FOUND THEN
		RAISE NOTICE 'unblock job %, error %', v_parentjob_id, v_outargs;
		-- and call do_task error
		-- FIXME: transform error object
		RETURN do_wait_for_children_task(v_parentworkflow_id, v_parenttask_id, v_parentjob_id);
		--PERFORM do_task_error(v_parentworkflow_id, v_parenttask_id, v_parentjob_id, v_outargs);
	END IF;

	RETURN null; -- no next task
END$function$
