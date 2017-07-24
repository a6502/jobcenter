CREATE OR REPLACE FUNCTION jobcenter.get_task(a_workername text, a_actionname text, a_job_id bigint DEFAULT NULL::bigint)
 RETURNS TABLE(o_job_id bigint, o_job_cookie text, o_in_args jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_action_id int;
	v_config jsonb;
	v_timeout timestamptz DEFAULT null;
	v_worker_id bigint;
	v_workflow_id int;
	v_task_id int;
	v_key text;
	v_val jsonb;
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
			job_id, workflow_id, task_id, out_args
			INTO o_job_id, v_workflow_id, v_task_id, o_in_args
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
			job_id, workflow_id, task_id, out_args
			INTO o_job_id, v_workflow_id, v_task_id, o_in_args
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
		-- RAISE NOTICE 'task not found for job_id % and action_id %', a_job_id, v_action_id;
		RETURN;
	END IF;

	IF v_config ? 'timeout' THEN
		v_timeout = now() + (v_config->>'timeout')::interval;
	END IF;

	UPDATE jobs SET
		task_started = now(),
		state = 'working',
		task_state = COALESCE(task_state, '{}'::jsonb) || jsonb_build_object('worker_id', v_worker_id),
		cookie = md5('cookie' || workflow_id::text || task_id::text || job_id::text || now()::text || random()::text)::uuid,
		timeout = v_timeout
	WHERE
		job_id = o_job_id
		AND task_id = v_task_id
		AND state = 'ready'
	RETURNING cookie INTO o_job_cookie;

	IF NOT FOUND THEN
		-- should not happen because of select for update?
		RAISE NOTICE 'task gone for job_id % and action_id %', o_job_id, v_action_id;
		RETURN;
	END IF;

	IF o_in_args IS NULL THEN
		-- maybe we should do this in the client?
		o_in_args = '{}'::jsonb;
	END IF;
	RAISE NOTICE 'get_task: o_in_args %', o_in_args;
	RETURN NEXT;
	RETURN;
END$function$
