CREATE OR REPLACE FUNCTION jobcenter.do_task_error(a_jobtask jobtask, a_outargs jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO 'jobcenter', 'pg_catalog', 'pg_temp'
AS $function$DECLARE
	v_task_state jsonb;
	v_config jsonb;
	v_tries integer;
	v_maxtries integer;
	v_timeout timestamptz;
BEGIN
	--RAISE LOG 'in do_task_error!';
	-- figure out if this is a soft error we can retry
	IF a_outargs ? 'error' AND a_outargs->'error' ? 'class'
		AND a_outargs #>> '{error,class}' = 'soft' THEN

		SELECT
			task_state, config
			INTO v_task_state, v_config
		FROM
			jobs
			JOIN tasks USING (workflow_id, task_id)
			JOIN actions USING (action_id)
		WHERE
			job_id = a_jobtask.job_id
			AND task_id = a_jobtask.task_id
			AND workflow_id = a_jobtask.workflow_id;

		v_tries = COALESCE((v_task_state->>'tries')::integer,1);
		v_maxtries = COALESCE((v_config#>>'{retry,tries}')::integer,0);
		-- if there is no retry policy tries will be > maxtries

		IF v_config ? 'retry' THEN

			RAISE LOG 'do_task_error tries % max_tries %', v_tries, v_maxtries;

			IF v_maxtries < 0 OR v_tries < v_maxtries THEN
				-- interval exists?
				BEGIN
					v_timeout = now() + (v_config#>>'{retry,interval}')::interval;

					RAISE LOG 'do_task_error timeout %', v_timeout;

					UPDATE jobs SET
						state = 'retrywait',
						cookie = NULL,
						timeout = v_timeout,
						-- save soft error in task_state
						task_state = COALESCE(task_state, '{}'::jsonb) || a_outargs
					WHERE
						job_id = a_jobtask.job_id
						AND task_id = a_jobtask.task_id
						AND workflow_id = a_jobtask.workflow_id;

					RETURN;
				EXCEPTION WHEN OTHERS THEN -- or just catch invalid_datetime_format?
					a_outargs = jsonb_build_object(
						'error', jsonb_build_object(
							'msg',  format('error calculating retry timeout sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM),
							'class', 'normal',
							'olderror', a_outargs
						)
					);
				END;

			END IF;
		END IF;
	END IF;

	UPDATE jobs SET
		state = 'error',
		task_completed = now(),
		--waitfortask_id = NULL,
		cookie = NULL,
		timeout = NULL,
		-- save error in task_state
		task_state = COALESCE(task_state, '{}'::jsonb) || a_outargs
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id;
	
	PERFORM do_log(a_jobtask.job_id, false, null, a_outargs);

	-- wake up maestro
	RAISE LOG 'NOTIFY "jobtaskerror", %', '' || a_jobtask::text || '';
	PERFORM pg_notify( 'jobtaskerror',  a_jobtask::text );
END$function$
