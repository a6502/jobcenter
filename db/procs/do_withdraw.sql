CREATE OR REPLACE FUNCTION jobcenter.do_withdraw(a_workername text, a_actionname text, disconnecting bool)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_worker_id bigint;
	v_action_id int;
	v_config jsonb;
	v_error jsonb;
	v_jobtask jobtask;
	v_job_id bigint;
	v_task_id int;
	v_workflow_id int;
	v_state job_state;
BEGIN
	SELECT
		worker_id, action_id, config
		INTO v_worker_id, v_action_id, v_config
	FROM
		workers AS w
		JOIN worker_actions AS wa USING (worker_id)
		JOIN actions AS a USING (action_id)
	WHERE
		w.name = a_workername
		AND w.stopped IS NULL
		AND a.name = a_actionname;
		-- FIXME: AND version?

	IF NOT FOUND THEN
		-- maybe throw an exception instead?
		RETURN FALSE;
	END IF;

	DELETE FROM
		worker_actions
	WHERE
		worker_id = v_worker_id
		AND action_id = v_action_id;
	
	-- stop worker if this was the last action
	UPDATE
		workers
	SET
		stopped = now()
	WHERE
		worker_id = v_worker_id 
		AND worker_id NOT IN (
			SELECT worker_id FROM worker_actions WHERE worker_id = v_worker_id
		);
	
	-- set jobs belonging to worker to retry state
	IF disconnecting AND NOT COALESCE((v_config->>'persistent')::bool, FALSE) THEN

		v_error := '{"error":{"class": "soft", "msg": "worker disconnected"}}'::jsonb;

		FOR v_job_id, v_task_id, v_workflow_id, v_state IN 
			SELECT job_id, task_id, workflow_id, state
			FROM jobs 
			WHERE state = 'working'
			      AND (task_state->>'worker_id')::bigint = v_worker_id 
		LOOP

			v_jobtask := (v_workflow_id, v_task_id, v_job_id)::jobtask;
			PERFORM do_task_error(v_jobtask, v_error);
		END LOOP;
	END IF;
	
	RETURN true;
END$function$

