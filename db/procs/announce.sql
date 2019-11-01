CREATE OR REPLACE FUNCTION jobcenter.announce(workername text, actionname text, impersonate text DEFAULT NULL::text, filter jsonb DEFAULT NULL::jsonb, OUT worker_id bigint, OUT listenstring text)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'jobcenter', 'pg_catalog', 'pg_temp'
AS $function$DECLARE
	a_workername ALIAS FOR $1;
	a_actionname ALIAS FOR $2;
	a_impersonate ALIAS FOR $3;
	a_filter ALIAS FOR $4;
	o_worker_id ALIAS FOR $5;
	o_listenstring ALIAS FOR $6;
	v_action_id int;
	v_have_role text;
	v_should_role text;
	v_config jsonb;
	v_allowed_filter jsonb;
	v_key text;
BEGIN
	-- create worker if it does not exist already
	-- see Example 40.2 in http://www.postgresql.org/docs/current/static/plpgsql-control-structures.html
	LOOP
		SELECT
			workers.worker_id INTO o_worker_id
		FROM
			workers
		WHERE
			name = a_workername AND stopped IS NULL;

		EXIT WHEN found;
		-- not there, so try to insert the worker
		-- if someone else inserts the same worker concurrently,
		-- we could get a unique-key failure, so use on conflict do nothing
		INSERT INTO
			workers (name)
		VALUES (a_workername) INTO o_worker_id
			ON CONFLICT DO NOTHING RETURNING workers.worker_id;

		EXIT WHEN found; -- exit loop when insert succeeded
	END LOOP;

	SELECT
		action_id, rolename, config->'filter'
		INTO v_action_id, v_should_role, v_allowed_filter
	FROM
		actions
	WHERE
		name = a_actionname
		AND type = 'action'
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

	IF a_filter IS NOT NULL THEN
		IF v_allowed_filter IS NULL OR jsonb_typeof(v_allowed_filter) <> 'array' THEN
			RAISE EXCEPTION 'filtering is not allowed for action %', a_actionname;
		END IF;
		IF jsonb_typeof(a_filter) <> 'object' THEN
			RAISE EXCEPTION 'filter needs to be a json object %', a_filter;
		END IF;

		FOR v_key IN SELECT jsonb_object_keys(a_filter) LOOP
			IF NOT v_allowed_filter ? v_key THEN
				RAISE EXCEPTION 'filtering is not allowed for key %',v_key;
			END IF;
		END LOOP;
	ELSE
		IF v_allowed_filter IS NOT NULL
			AND jsonb_typeof(v_allowed_filter) = 'array'
			AND NOT v_allowed_filter ? '_*_' THEN
				RAISE EXCEPTION 'filtering is required for action %', a_actionname;
		END IF;
	END IF;

	BEGIN
		INSERT INTO worker_actions(worker_id, action_id, filter) VALUES (o_worker_id, v_action_id, a_filter);
	EXCEPTION WHEN unique_violation THEN
		-- fixme: or just ignore?
		RAISE EXCEPTION 'worker % already can do action %', a_workername, a_actionname;
	END;

	o_listenstring := 'action:' || v_action_id || ':ready';
	RETURN;
END$function$
