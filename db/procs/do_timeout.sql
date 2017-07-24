CREATE OR REPLACE FUNCTION jobcenter.do_timeout()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_job_id bigint;
	v_task_id integer;
	v_action_id integer;
	v_conf jsonb;
	v_payload jsonb;
	v_in_args jsonb;
	v_workers bigint[];
	v_workflow_id integer;
	v_state job_state;
	v_next integer;
	v_eventdata jsonb;
	v_jobtask jobtask;
	v_slept interval;
BEGIN
	FOR v_job_id, v_task_id, v_workflow_id, v_state IN SELECT job_id, task_id, workflow_id, state
			FROM jobs WHERE timeout <= now() LOOP
		RAISE NOTICE 'job % state %', v_job_id, v_state;
		v_jobtask := (v_workflow_id, v_task_id, v_job_id)::jobtask;
		CASE v_state
		WHEN 'eventwait' THEN
			-- waiting for event timed out
			v_eventdata = jsonb_build_object(
				'name', 'timeout',
				'event_id', null,
				'when', now(),
				'data', null
			);
			v_eventdata = jsonb_build_object(
				'event', v_eventdata
			);
			RAISE NOTICE 'eventwait timeout for job %', v_job_id;
			PERFORM do_task_done(v_jobtask, v_eventdata);
		WHEN 'retrywait' THEN
			-- simpels?
			SELECT
				action_id, config INTO v_action_id, v_conf
			FROM
				actions
				JOIN tasks USING (action_id)
			WHERE task_id=v_task_id;

			UPDATE
				jobs
			SET
				state = 'ready',
				timeout = null, -- done with this timeout
				task_state = jsonb_set(COALESCE(task_state,'{}'::jsonb), '{tries}', to_jsonb(COALESCE((task_state->>'tries')::integer,0) + 1))
			WHERE
				job_id = v_job_id
			RETURNING
				out_args INTO v_in_args;
			-- RAISE NOTICE 'timeout for job %', v_job_id;

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
					CONTINUE;
				END IF;
				-- RAISE NOTICE 'action_id % in_args % workers %',	v_action_id, v_in_args, v_workers;
				v_payload = jsonb_build_object('job_id', v_job_id, 'workers', v_workers);
			ELSE
				v_payload = jsonb_build_object('job_id', v_job_id);
			END IF;

			RAISE NOTICE 'retry action % for %', v_action_id, v_job_id;
			RAISE NOTICE 'NOTIFY "action:%:ready", %', v_action_id, v_payload;
			PERFORM pg_notify('action:' || v_action_id || ':ready', v_payload::text);
		WHEN 'working' THEN
			v_eventdata = jsonb_build_object(
				'error', jsonb_build_object(
					'class', 'soft',
					'msg', 'timeout'
				)
			);
			RAISE NOTICE 'timeout for job %', v_job_id;
			PERFORM do_task_error(v_jobtask, v_eventdata);
		WHEN 'sleeping' THEN
			-- done sleeping
			SELECT
				now() - task_started INTO v_slept
			FROM
				jobs
			WHERE
				job_id = v_job_id;
			v_eventdata = jsonb_build_object(
				'slept', v_slept::text
			);
			RAISE NOTICE 'timeout for job %', v_job_id;
			PERFORM do_task_done(v_jobtask, v_eventdata);
		WHEN 'working' THEN
			RAISE NOTICE 'job % timed out in task %', v_job_id, v_task_id;
			v_eventdata = jsonb_build_object(
				'error', jsonb_build_object(
					'msg', format('job %s timed out in task %s', v_job_id, v_task_id)
					'class', 'timeout',
					'when', now()
				)
			);			
			PERFORM do_task_error(v_jobtask, v_eventdata);
		ELSE -- this should not happen
			UPDATE
				jobs
			SET
				timeout = null -- done with this timeout
			WHERE
				job_id = v_job_id;
			RAISE NOTICE 'got spurious timeout for job % in state %', v_job_id, v_state;
		END CASE;
	END LOOP;

	SELECT
		(EXTRACT(EPOCH FROM MIN(timeout))
		- EXTRACT(EPOCH FROM now()))::integer
		AS seconds INTO v_next
	FROM
		jobs;

	RAISE NOTICE 'do_timeout: next %', v_next;
	RETURN v_next;
END;$function$
