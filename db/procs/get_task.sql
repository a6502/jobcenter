CREATE OR REPLACE FUNCTION jobcenter.get_task(a_workername text, a_actionname text, a_job_id bigint DEFAULT NULL::bigint, OUT o_job_id bigint, OUT o_job_cookie text, OUT o_in_args jsonb, OUT o_env jsonb)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_action_id int;
	v_config jsonb;
	v_worker_id bigint;
	v_workflow_id int;
	v_task_id int;
	v_filter jsonb;
BEGIN
	SELECT
		worker_id, action_id, a.config, wa.filter
		INTO v_worker_id, v_action_id, v_config, v_filter
	FROM
		workers w
		JOIN worker_actions wa USING (worker_id)
		JOIN actions a USING (action_id)
	WHERE
		w.name = a_workername
		AND w.stopped IS NULL
		AND a.name = a_actionname
		AND type = 'action';

	IF NOT FOUND THEN
		RAISE EXCEPTION 'no workeraction for worker % action %.', a_workername, a_actionname;
	END IF;

	-- let's assume that the jsonb patternmatching is cheap enough..

	IF a_job_id IS NOT NULL THEN
		SELECT
			job_id, workflow_id, task_id
			INTO o_job_id, v_workflow_id, v_task_id
		FROM
			jobs AS j
			JOIN tasks AS t USING (task_id, workflow_id)
		WHERE
			j.job_id = a_job_id
			AND t.action_id = v_action_id
			AND state = 'ready'
			AND (v_filter IS NULL
			     OR out_args @> v_filter)
		FOR UPDATE OF j SKIP LOCKED; -- sigh: because of jobs as j
	ELSE
		-- poll
		SELECT
			job_id, workflow_id, task_id
			INTO o_job_id, v_workflow_id, v_task_id
		FROM
			jobs AS j
			JOIN tasks AS t USING (task_id, workflow_id)
		WHERE
			state = 'ready'
			AND t.action_id = v_action_id
			AND (v_filter IS NULL
			     OR out_args @> v_filter)
		ORDER BY job_id LIMIT 1
		FOR UPDATE OF j SKIP LOCKED; -- sigh: because of jobs as j
	END IF;

	IF NOT FOUND THEN
		-- RAISE LOG 'task not found for job_id % and action_id %', a_job_id, v_action_id;
		RETURN;
	END IF;

	UPDATE jobs SET
		task_started = now(),
		state = 'working',
		task_state = COALESCE(task_state, '{}'::jsonb) || jsonb_build_object('worker_id', v_worker_id),
		cookie = md5('cookie' || workflow_id::text || task_id::text || job_id::text || now()::text || random()::text)::uuid,
		timeout = CASE WHEN v_config ? 'timeout' THEN now() + (v_config->>'timeout')::interval ELSE null END
	WHERE
		job_id = o_job_id
		AND task_id = v_task_id
		AND state = 'ready'
	RETURNING
		cookie,
		COALESCE(out_args, '{}'::jsonb),
		COALESCE(task_state -> 'env', '{}'::jsonb) ||
			CASE WHEN task_state ? 'tries'
				THEN jsonb_build_object('tries', task_state->'tries')
				ELSE '{}'::jsonb
			END
		INTO o_job_cookie, o_in_args, o_env;

	IF NOT FOUND THEN
		-- should not happen because of select for update?
		RAISE LOG 'task gone for job_id % and action_id %', o_job_id, v_action_id;
		RETURN;
	END IF;

	RAISE LOG 'get_task: o_job_id % o_cookie % o_in_args % o_env %', o_job_id, o_job_cookie, o_in_args, o_env;
	RETURN;
END$function$
