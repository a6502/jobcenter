CREATE OR REPLACE FUNCTION jobcenter.find_jobs(a_filter jsonb, a_state text DEFAULT NULL::text)
 RETURNS bigint[]
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_jobs bigint[];
BEGIN
	IF a_filter = '{}'::jsonb THEN
		RAISE EXCEPTION 'using an empty filter is not allowed';
	END IF;

	v_jobs := array(
		SELECT 
			job_id
		FROM
			jobs
		WHERE
			arguments @> a_filter
	);

	RETURN v_jobs;
END$function$
