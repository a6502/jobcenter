CREATE OR REPLACE FUNCTION jobcenter.do_subscribe_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_action_id int;
	v_name text;
	v_inargs jsonb;
	v_mask jsonb;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, environment, variables, action_id INTO v_args, v_env, v_vars, v_action_id
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id
		AND actions.type = 'system'
		AND actions.name = 'subscribe';
		
	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_subscribe_task called for non-subscribe-task %', a_jobtask.task_id;
	END IF;

	--RAISE NOTICE 'do_inargsmap action_id % task_id % args % vars % ', v_action_id, a_task_id, v_args, v_vars;
	BEGIN
		v_inargs := do_inargsmap(v_action_id, a_jobtask, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;
		
	RAISE NOTICE 'do_subscribe_task v_inargs %', v_inargs;

	-- and what subscriptions we are actually interested in
	-- (do_inargsmap has made sure those fields exist?)
	v_name := v_inargs->>'name';
	v_mask := v_inargs->'mask';

	INSERT INTO event_subscriptions (job_id, "name", mask) VALUES (a_jobtask.job_id, v_name, v_mask) ON CONFLICT DO NOTHING;
	-- fixme: just ignore duplicates or throw an error?

	RETURN do_task_epilogue(a_jobtask, false, null, v_inargs, null);
END;$function$
