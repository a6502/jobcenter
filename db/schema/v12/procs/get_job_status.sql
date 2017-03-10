CREATE OR REPLACE FUNCTION jobcenter.get_job_status(a_job_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_state job_state;
	v_out_args jsonb;
BEGIN

	SELECT 
		state, out_args INTO STRICT v_state, v_out_args
	FROM
		jobs
	WHERE
		job_id = a_job_id
	UNION ALL SELECT
		state, out_args
	FROM
		jobs_archive
	WHERE
		job_id = a_job_id;

	IF NOT FOUND THEN
		RAISE EXCEPTION 'no job %', a_job_id;
	END IF;	

	IF v_state NOT IN ('error', 'finished') THEN
		RETURN null;
	END IF;

	IF v_state = 'error' AND v_out_args IS NULL THEN
		v_out_args := '{"error":"an unknown error occurred"}'::jsonb;
	END IF;

	RETURN v_out_args;
END$function$
