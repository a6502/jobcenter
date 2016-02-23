CREATE OR REPLACE FUNCTION jobcenter.do_task_done(a_jobtask jobtask, a_outargs jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_inargs jsonb;
	v_changed boolean;
	v_newvars jsonb;
BEGIN
	-- check error status
	IF a_outargs ? 'error' THEN
		PERFORM do_task_error(a_jobtask, a_outargs->'error');
		RETURN;
	END IF;

	BEGIN
		SELECT vars_changed, newvars INTO v_changed, v_newvars FROM do_outargsmap(a_jobtask, a_outargs);
	EXCEPTION WHEN OTHERS THEN
		PERFORM do_task_error(a_jobtask, to_jsonb(format('caught exception in do_outargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM)));
		RETURN;
	END;

	-- bleh.. we want the 'old' value of out args..
	SELECT out_args INTO v_inargs FROM jobs WHERE job_id = a_jobtask.job_id FOR UPDATE OF jobs;

	UPDATE jobs SET
		state = 'done',
		variables = CASE WHEN v_changed THEN v_newvars ELSE null END,
		task_completed = now(),
		waitfortask_id = NULL,
		cookie = NULL,
		timeout = NULL
	WHERE job_id = a_jobtask.job_id;

	PERFORM do_log(a_jobtask.job_id, v_changed, v_inargs, a_outargs);

	-- wake the maestro
	PERFORM pg_notify('jobtaskdone', a_jobtask::text);

	RETURN;
END$function$
