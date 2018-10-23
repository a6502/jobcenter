CREATE OR REPLACE FUNCTION jobcenter.withdraw(a_workername text, a_actionname text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'jobcenter', 'pg_catalog', 'pg_temp'
AS $function$DECLARE
	v_worker_id bigint;
	v_action_id int;
BEGIN
	SELECT
		worker_id, action_id
		INTO v_worker_id, v_action_id
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

	RETURN true;
END$function$
