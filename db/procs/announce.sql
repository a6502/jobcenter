CREATE OR REPLACE FUNCTION jobcenter.announce(a_workername text, a_actionname text)
 RETURNS TABLE(o_worker_id bigint, o_listenstring text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
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
		-- we could get a unique-key failure, so use on conflict do nothing
		INSERT INTO workers(name) VALUES (a_workername) INTO v_worker_id ON CONFLICT DO NOTHING RETURNING worker_id;
		EXIT WHEN found; -- exit loop when insert succeeded
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
