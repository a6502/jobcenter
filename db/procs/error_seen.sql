CREATE OR REPLACE FUNCTION jobcenter.error_seen(a_job_id bigint, a_who text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_job_finished timestamp with time zone;
	v_state job_state;
	v_seen jsonb;
BEGIN
	IF a_who IS NULL OR a_who = '' THEN
		RETURN format('usage error_seeen(<job_id>, <who>)');
	END IF;

	SELECT
		job_finished, state INTO v_job_finished, v_state
	FROM 
		jobs
	WHERE
		job_id = a_job_id
	FOR UPDATE OF jobs;

	IF NOT FOUND THEN
		RETURN format('job %s not found', a_job_id);
	END IF;

	IF v_state <> 'error' THEN
		RETURN format('job %s is not in an error state', a_job_id);
	END IF;

	IF v_job_finished IS NULL THEN
		RETURN format('job %s is not finished (cancel first?)', a_job_id);
	END IF;

	v_seen := jsonb_build_object('who', a_who, 'when', now());

	UPDATE
		jobs
	SET
		job_state = COALESCE(job_state, '{}'::jsonb) || jsonb_build_object('error_seen', v_seen)
	WHERE
		job_id = a_job_id;

	RETURN format('set error_seen for job %s to %s', a_job_id, v_seen);
END$function$
