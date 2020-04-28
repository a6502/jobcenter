CREATE OR REPLACE FUNCTION jobcenter.ping(a_worker_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$BEGIN
	RAISE NOTICE 'ping from %', a_worker_id;
	UPDATE workers SET
		last_ping = now()
	WHERE
		worker_id = a_worker_id
		AND stopped IS NULL;

	IF NOT FOUND THEN
		-- we have a zombie worker?
		RETURN null;
	END IF;

	RETURN 'pong';
END;$function$
