CREATE OR REPLACE FUNCTION jobcenter.get_task(a_workername text, a_actionname text, a_job_id bigint)
 RETURNS TABLE(o_job_cookie text, o_in_args jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$DECLARE
	v_action_id int;
	v_worker_id bigint;
	v_workflow_id int;
	v_task_id int;
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
		action_id INTO v_action_id
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

	SELECT 
		workflow_id, task_id INTO v_workflow_id, v_task_id
	FROM
		tasks AS t
		JOIN jobs AS j USING (task_id, workflow_id)
	WHERE
		j.job_id = a_job_id
		AND t.action_id = v_action_id
		AND state = 'ready'
		AND pg_try_advisory_xact_lock(job_id)
	FOR UPDATE OF j; -- sigh: because of jobs as j

	IF NOT FOUND THEN
		-- RAISE NOTICE 'task not found for job_id % and action_id %', a_job_id, v_action_id;
		RETURN;
	END IF;

	UPDATE jobs SET
		task_started = now(),
		state = 'working',
		worker_id = v_worker_id,
		cookie = md5('cookie' || workflow_id::text || task_id::text || job_id::text || now()::text || random()::text)::uuid,
		timeout = now() + '00:05:00'::interval -- FIXME: make configurable
	WHERE
		job_id = a_job_id
		AND task_id = v_task_id
		AND state = 'ready'
	RETURNING cookie, out_args INTO o_job_cookie, o_in_args;

	IF NOT FOUND THEN
		RAISE NOTICE 'task gone for job_id % and action_id %', a_job_id, v_action_id;
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
