CREATE OR REPLACE FUNCTION jobcenter.do_prepare_for_action(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_action_id int;
	v_conf jsonb;
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_in_args jsonb;
	v_workers bigint[];
	v_payload jsonb;
BEGIN
	-- get the arguments and such
	SELECT
		action_id, config, arguments, environment, variables
		INTO v_action_id, v_conf, v_args, v_env, v_vars
	FROM 
		actions
		JOIN tasks USING (action_id)
		JOIN jobs USING (workflow_id, task_id)
	WHERE
		workflow_id = a_jobtask.workflow_id
		AND task_id = a_jobtask.task_id
		AND job_id = a_jobtask.job_id
		AND type = 'action';

	IF NOT FOUND THEN
		-- FIXME: or is this a do_raiserror kind of error?
		RAISE EXCEPTION 'no action found for workflow % task %.', a_jobtask.workflow_id, a_jobtask.task_id;
	END IF;

	BEGIN
		v_in_args := do_inargsmap(v_action_id, a_jobtask, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;

	-- 'abuse' the out_args field to store the calulated in_args
	UPDATE jobs SET
		out_args = v_in_args
	WHERE
		job_id = a_jobtask.job_id;

	-- if filtering is allowed
	IF v_conf ? 'filter' THEN
		-- see which workers have matching filters
		SELECT
			array_agg(worker_id) INTO v_workers
		FROM
			worker_actions
		WHERE
			action_id = v_action_id
			AND (filter IS NULL
			     OR v_in_args @> filter);

		IF v_workers IS NULL THEN
			RAISE NOTICE 'no worker for action_id % in_args %', v_action_id, v_in_args;
			RETURN null; -- no next task
		END IF;
		-- RAISE NOTICE 'action_id % in_args % workers %',	v_action_id, v_in_args, v_workers;
		v_payload = jsonb_build_object('job_id', a_jobtask.job_id, 'workers', v_workers);
	ELSE
		v_payload = jsonb_build_object('job_id', a_jobtask.job_id);
	END IF;

	RAISE NOTICE 'NOTIFY "action:%:ready", %', v_action_id, v_payload;
	PERFORM pg_notify('action:' || v_action_id || ':ready', v_payload::text);
	RETURN null; -- no next task
END$function$
