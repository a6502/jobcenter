CREATE OR REPLACE FUNCTION jobcenter.get_task(a_workername text, a_actionname text, a_job_id bigint DEFAULT NULL::bigint, a_pattern jsonb DEFAULT NULL::jsonb)
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
	v_havepat jsonb DEFAULT '{}'::jsonb;
	v_havenotpat jsonb DEFAULT 'null'::jsonb;
BEGIN
	SELECT
		worker_id INTO v_worker_id
	FROM
		workers
	WHERE
		name = a_workername 
		AND stopped IS NULL;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'no worker named %.', a_workername;
	END IF;

	SELECT
		action_id, config INTO v_action_id, v_config
	FROM
		actions
	WHERE
		name = a_actionname
		AND type = 'action'
	ORDER BY version DESC LIMIT 1; -- FIXME

	IF NOT FOUND THEN
		RAISE EXCEPTION 'no action named %.', a_actionname;
	END IF;

	PERFORM 
		true
	FROM
		worker_actions
	WHERE
		worker_id = v_worker_id
		AND action_id = v_action_id;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'worker % has not announced action %.', a_workername, a_actionname;
	END IF;

	IF a_pattern IS NOT NULL THEN
		v_havenotpat = '{}'::jsonb;

		FOR v_key, v_val IN SELECT * FROM jsonb_each(a_pattern) LOOP
			IF v_key ~~ '!%' THEN
				v_havenotpat := jsonb_set(v_havenotpat, ARRAY[right(v_key,-1)], v_val);
			ELSE
				v_havepat := jsonb_set(v_havepat, ARRAY[v_key], v_val);
			END IF;
		END LOOP;

		IF v_havenotpat = '{}'::jsonb THEN
			v_havenotpat = 'null'::jsonb;
		END IF;

		RAISE NOTICE 'havepat % havenotpat %', v_havepat, v_havenotpat;
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
			AND out_args @> v_havepat
			AND NOT out_args @> v_havenotpat
		FOR UPDATE OF j SKIP LOCKED; -- sigh: because of jobs as j
	ELSE
		SELECT
			job_id, workflow_id, task_id
			INTO o_job_id, v_workflow_id, v_task_id
		FROM
			jobs AS j
			JOIN tasks AS t USING (task_id, workflow_id)
		WHERE
			state = 'ready'
			AND t.action_id = v_action_id
			AND out_args @> v_havepat
			AND NOT out_args @> v_havenotpat
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
	RETURNING cookie, out_args INTO o_job_cookie, o_in_args;

	IF NOT FOUND THEN
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
