CREATE OR REPLACE FUNCTION jobcenter.get_job_status(INOUT a_job_id bigint, OUT o_out_args jsonb)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_state job_state;
BEGIN

	SELECT 
		state, out_args INTO v_state, o_out_args
	FROM
		jobs
	WHERE
		job_id = a_job_id;

	IF NOT FOUND THEN -- in the archive then?
		SELECT
			state, out_args INTO v_state, o_out_args
		FROM
			jobs_archive
		WHERE
			job_id = a_job_id;

		IF NOT FOUND THEN
			--RAISE EXCEPTION 'no job %', a_job_id;
			o_out_args := format('{"error":"no job %s"}', a_job_id)::jsonb;
			a_job_id := null;
			RETURN;
		END IF;
	END IF;	

	IF v_state NOT IN ('error', 'finished') THEN
		a_job_id := null;
		o_out_args := null;
	ELSIF v_state = 'error' AND o_out_args IS NULL THEN
		o_out_args := '{"error":"an unknown error occurred"}'::jsonb;
	END IF;

	RETURN;
END$function$
