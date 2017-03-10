CREATE OR REPLACE FUNCTION jobcenter.do_reap_child_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_reapfromtask_id int;
	v_subjob_id bigint;
	v_in_args jsonb;
	v_out_args jsonb;
	v_maptask_id integer; -- task we use the map defintions from
	v_mapaction_id integer;
	v_changed boolean;
	v_newvars jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT
		(tasks.attributes->>'reapfromtask_id')::int INTO v_reapfromtask_id
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND workflow_id = a_jobtask.workflow_id
		AND task_id= a_jobtask.task_id
		AND state = 'ready'
		AND actions.type = 'system'
		AND actions.name = 'reap_child';

	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_reap_child called for non-reap_child-task %', a_jobtask.task_id;
	END IF;

	IF v_reapfromtask_id IS NULL THEN
		RAISE EXCEPTION 'reap_from_task field required for reap_child task %', a_jobtask.task_id;
	END IF;

	RAISE NOTICE 'look for child job of % task %', a_jobtask.job_id, v_reapfromtask_id;
	-- the child job should be a zombie already
	UPDATE
		jobs
	SET
		state = 'finished',
		job_finished = now(),
		task_completed = now()
	WHERE
		(job_state->>'parenttask_id')::integer = v_reapfromtask_id
		AND parentjob_id = a_jobtask.job_id
		AND state = 'zombie'
	RETURNING job_id, arguments, out_args INTO v_subjob_id, v_in_args, v_out_args;

	IF NOT FOUND THEN
		RETURN do_raise_error(a_jobtask, 'no zombie childjob found in reap_child_task');
	END IF;

	RAISE NOTICE 'child job % finished', v_subjob_id;

	-- we want the output definitios and maps from the original task that started this
	-- childjob, so we use v_reapfromtask_id in the do_outargsmap
	BEGIN
		SELECT
			vars_changed, newvars
			INTO v_changed, v_newvars
		FROM
			do_outargsmap((a_jobtask.workflow_id, v_reapfromtask_id, a_jobtask.job_id)::jobtask, v_out_args);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_outargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM)::jsonb);
	END;

	RAISE NOTICE 'reap_child newvars: %', v_newvars;

	RETURN do_task_epilogue(a_jobtask, v_changed, v_newvars, v_in_args, v_out_args);
END
$function$
