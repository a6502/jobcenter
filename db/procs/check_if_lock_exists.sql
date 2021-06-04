CREATE OR REPLACE FUNCTION jobcenter.check_if_lock_exists(a_locktype text, a_lockvalue text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$BEGIN
	-- check for valid locktype

	PERFORM
		locktype
	FROM
		locktypes
	WHERE

		locktype = a_locktype;

	IF NOT FOUND THEN
		RETURN null;
	END IF;

	PERFORM
		job_id
	FROM
		locks
	WHERE
		locktype = a_locktype
		AND lockvalue = a_lockvalue;

	RETURN FOUND;
END$function$
