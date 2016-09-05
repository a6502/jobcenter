CREATE OR REPLACE FUNCTION jobcenter.do_check_role_membership(a_have_role text, a_should_role text)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_roletmp text;
BEGIN
	IF a_should_role IS NULL THEN
		-- no role required
		RETURN true;
	END IF;

	IF a_have_role IS NULL THEN
		-- we have no role?
		RETURN false;
	END IF;

	IF a_have_role = a_should_role THEN
		-- now that was easy
		RETURN true;
	END IF;

	-- FIXME: recursion?
	PERFORM
		true
	FROM
		jc_role_members
	WHERE
		rolename = a_have_role
		AND member_of = a_should_role;

	IF FOUND THEN
		RETURN true;
	END IF;

	RETURN false;
END$function$
