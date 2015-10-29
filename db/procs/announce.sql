CREATE OR REPLACE FUNCTION jobcenter.announce(a_workername text, a_actionname text)
 RETURNS TABLE(o_worker_id bigint, o_listenstring text)
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$DECLARE
	v_worker_id bigint;
	v_action_id int;
	v_listenstring text;
BEGIN
	-- create worker if it does not exist already
	-- see Example 40.2 in http://www.postgresql.org/docs/current/static/plpgsql-control-structures.html
	LOOP
		SELECT worker_id INTO v_worker_id FROM workers WHERE name = a_workername AND stopped IS NULL;
		EXIT WHEN found;
		-- not there, so try to insert the worker
		-- if someone else inserts the same worker concurrently,
		-- we could get a unique-key failure
		BEGIN
			INSERT INTO workers(name) VALUES (a_workername) RETURNING worker_id INTO v_worker_id;
			EXIT; /* exit loop when insert succeeded */
		EXCEPTION WHEN unique_violation THEN
			-- Do nothing, and loop to try the UPDATE again.
		END;
	END LOOP;
	SELECT action_id INTO v_action_id FROM actions WHERE name = a_actionname ORDER BY version DESC LIMIT 1;
	IF NOT found THEN
		RAISE EXCEPTION 'no action named %.', a_actionname;
	END IF;
	BEGIN
		INSERT INTO worker_actions(worker_id, action_id) VALUES (v_worker_id, v_action_id);
	EXCEPTION WHEN unique_violation THEN
		RAISE EXCEPTION 'worker % already can do action %', a_workername, a_actionname;
	END;
	v_listenstring := 'action:' || v_action_id || ':ready';
	RETURN QUERY VALUES (v_worker_id, v_listenstring);
END$function$
