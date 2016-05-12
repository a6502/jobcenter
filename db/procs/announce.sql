CREATE OR REPLACE FUNCTION jobcenter.announce(workername text, actionname text, impersonate text DEFAULT NULL::text)
 RETURNS TABLE(o_worker_id bigint, o_listenstring text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	a_workername ALIAS FOR $1;
	a_actionname ALIAS FOR $2;
	a_impersonate ALIAS FOR $3;
	v_worker_id bigint;
	v_action_id int;
	v_have_role text;
	v_should_role text;
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

	SELECT
		action_id, rolename
		INTO v_action_id, v_should_role
	FROM
		actions
	WHERE
		name = a_actionname
	ORDER BY version DESC LIMIT 1;

	IF NOT found THEN
		RAISE EXCEPTION 'no action named %.', a_actionname;
	END IF;

	-- check session user because we are in a security definer stored procedure
	IF a_impersonate IS NOT NULL THEN
		-- check if the postgresql session user is allowed to impersonate role a_impersonate
		PERFORM
			true
		FROM
			jc_impersonate_roles
		WHERE
			rolename = session_user
			AND impersonates = a_impersonate;

		IF NOT FOUND THEN
			RAISE EXCEPTION 'worker % has no right to impersonate role %', session_user, a_impersonate;
		END IF;

		v_have_role := a_impersonate;
	ELSE
		v_have_role := session_user;
	END IF;

	IF NOT do_check_role_membership(v_have_role, v_should_role) THEN
		RAISE EXCEPTION 'worker % with role % has no permission for role %', session_user, v_have_role, v_should_role;
	END IF;

	BEGIN
		INSERT INTO worker_actions(worker_id, action_id) VALUES (v_worker_id, v_action_id);
	EXCEPTION WHEN unique_violation THEN
		-- fixme: or just ignore?
		RAISE EXCEPTION 'worker % already can do action %', a_workername, a_actionname;
	END;

	v_listenstring := 'action:' || v_action_id || ':ready';
	RETURN QUERY VALUES (v_worker_id, v_listenstring);
END$function$
