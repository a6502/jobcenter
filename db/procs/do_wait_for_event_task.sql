CREATE OR REPLACE FUNCTION jobcenter.do_wait_for_event_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_action_id integer;
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_inargs jsonb;
	v_timeout timestamptz;
	v_names text[];
	v_name text;
	v_sub_id bigint;
	v_event_id bigint;
	v_when timestamptz;
	v_eventdata jsonb;
	v_changed boolean;
	v_newvars jsonb;
BEGIN
	-- first mark job waiting
	UPDATE jobs SET
		state = 'waiting',
		task_started = now()
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id
	RETURNING
		arguments, environment, variables INTO v_args, v_env, v_vars;

	IF NOT FOUND THEN
		-- FIXME: should not happen, as this is an internal function
		RAISE EXCEPTION 'do_wait_for_event task % not found', a_jobtask.task_id;
	END IF;

	SELECT
		action_id INTO STRICT v_action_id
	FROM
		actions
	WHERE
		"type" = 'system'
		AND name = 'wait_for_event';
	
	--RAISE NOTICE 'do_inargsmap action_id % task_id % argstrue % vars % ', v_action_id, a_task_id, v_args, v_vars;
	BEGIN
		v_inargs := do_inargsmap(v_action_id, a_jobtask.task_id, v_args, v_env, v_vars);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raiseerror(a_jobtask, format('caught exception in do_inargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
	END;	
	--RAISE NOTICE 'v_inargs %', v_inargs;

	-- now find out how long we are supposed to wait for that event..
	v_timeout = now() + (v_inargs->>'timeout')::interval;
	RAISE NOTICE 'wait until %', v_timeout;

	-- and what events we are actually interested in
	SELECT array_agg(bla) INTO v_names FROM jsonb_array_elements_text(v_inargs->'events') AS bla;
	RAISE NOTICE 'wait for %', v_names;

	-- check if any of those subscriptions have a event waiting
	SELECT
		subscription_id, "name", event_id, "when", eventdata INTO v_sub_id, v_name, v_event_id, v_when, v_eventdata
	FROM
		event_subscriptions
		JOIN job_events USING (subscription_id)
		JOIN queued_events USING (event_id)
	WHERE
		job_id = a_jobtask.job_id
		AND name = ANY(v_names)
	ORDER BY event_id
	LIMIT 1 FOR UPDATE OF job_events, queued_events;

	IF FOUND THEN
		-- delete this job_event
		DELETE FROM job_events WHERE subscription_id = v_sub_id AND event_id = v_event_id;
		-- delete the queued event if it is now orphaned
		DELETE FROM queued_events WHERE event_id = v_event_id AND event_id NOT IN (SELECT event_id FROM job_events WHERE event_id = v_event_id);

		-- add event_id and timestamp to evendata
		v_eventdata = jsonb_build_object(
			'name', v_name,
			'event_id', v_event_id,
			'when', v_when,
			'data', v_eventdata
		);
		v_eventdata = jsonb_build_object(
			'event', v_eventdata
		);

		BEGIN
			SELECT vars_changed, newvars INTO v_changed, v_newvars FROM do_outargsmap(a_jobtask, v_eventdata);
		EXCEPTION WHEN OTHERS THEN
			RETURN do_raise_error(a_jobtask, format('caught exception in do_outargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM)::jsonb);
		END;

		RETURN do_task_epilogue(a_jobtask, v_changed, v_newvars, v_inargs, v_eventdata);
	END IF;

	-- actually need to wait, mark which subscriptions we are waiting on
	UPDATE event_subscriptions SET
		waiting = true
	WHERE
		job_id = a_jobtask.job_id
		AND "name" = ANY(v_names);

	RAISE NOTICE 'waiting for %', v_names;

	-- and set the timeout
	UPDATE jobs SET
		timeout = v_timeout
	WHERE
		job_id = a_jobtask.job_id;

	RETURN null; -- no next task
END
$function$
