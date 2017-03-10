CREATE OR REPLACE FUNCTION jobcenter.raise_event(a_eventdata jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_event_id bigint;
	v_when timestamptz;
	v_sub_id bigint;
	v_job_id bigint;
	v_name text;
	v_task_id int;
	v_workflow_id int;
	v_eventdata jsonb;
	v_wait boolean;
	v_flag boolean DEFAULT false;
BEGIN
	-- store and get event_id
	INSERT INTO queued_events (eventdata)
		VALUES (a_eventdata)
		RETURNING event_id, "when" INTO v_event_id, v_when;

	-- see if the event matches any subscriptions
	FOR v_sub_id, v_name, v_job_id, v_wait IN SELECT subscription_id, "name", job_id, waiting FROM event_subscriptions WHERE a_eventdata @> mask LOOP
		SELECT workflow_id, task_id INTO v_workflow_id, v_task_id FROM jobs WHERE job_id = v_job_id AND state = 'eventwait';
		IF FOUND AND v_wait THEN
			-- wake the task that is waiting
			v_eventdata = jsonb_build_object(
				'name', v_name,
				'event_id', v_event_id,
				'when', v_when,
				'data', a_eventdata
			);
			v_eventdata = jsonb_build_object(
				'event', v_eventdata
			);

			PERFORM do_task_done((v_workflow_id, v_task_id, v_job_id)::jobtask, v_eventdata);
		ELSE
			INSERT INTO job_events VALUES (v_sub_id, v_event_id);
			v_flag := true;
		END IF;
	END LOOP;

	IF NOT v_flag THEN
		-- no job is waiting for this event
		DELETE FROM queued_events WHERE event_id = v_event_id;
	END IF;

	RETURN true;
END;$function$
