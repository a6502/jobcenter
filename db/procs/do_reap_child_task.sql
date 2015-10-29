CREATE OR REPLACE FUNCTION jobcenter.do_reap_child_task(a_workflow_id integer, a_task_id integer, a_job_id bigint)
 RETURNS nexttask
 LANGUAGE plpgsql
AS $function$DECLARE
	v_reapfromtask_id int;
	v_subjob_id bigint;
	v_out_args jsonb;
BEGIN
	-- what are we waiting for then?
	-- paranoia check with side effects
	SELECT
		reapfromtask_id INTO v_reapfromtask_id
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_job_id
		AND workflow_id = a_workflow_id
		AND task_id= a_task_id
		AND state = 'ready'
		AND actions.type = 'system'
		AND actions.name = 'reap_child';

	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_reap_child called for non-reap_child-task %', a_task_id;
	END IF;

	IF v_reapfromtask_id IS NULL THEN
		RAISE EXCEPTION 'reap_from_task field required for reap_child task %', a_task_id;
	END IF;

	-- mark job as blocked, so that do_task_done will work
	UPDATE jobs SET
		state = 'blocked',
		task_started = now()
	WHERE
		job_id = a_job_id;

	RAISE NOTICE 'look for child job of % task %', a_job_id, v_reapfromtask_id;
	-- see if the child job is a zombie already
	UPDATE
		jobs
	SET
		state = 'finished',
		job_finished = now(),
		task_completed = now()
	WHERE
		parenttask_id = v_reapfromtask_id
		AND parentjob_id = a_job_id
		AND state = 'zombie'
	RETURNING job_id, out_args INTO v_subjob_id, v_out_args;

	IF NOT FOUND THEN
		RETURN do_raise_error(a_workflow_id, a_task_id, a_job_id, 'no zombie childjob found in reap_child_task');
	END IF;

	RAISE NOTICE 'child job % done', v_subjob_id;
	-- mark us as done
	PERFORM do_task_done(a_workflow_id, a_task_id, a_job_id, v_out_args, false);

	RETURN do_jobtaskdone(a_workflow_id, a_task_id, a_job_id);
END
$function$
