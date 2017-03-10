CREATE OR REPLACE FUNCTION jobcenter.do_task_done(a_jobtask jobtask, a_outargs jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_error jsonb;
	v_inargs jsonb;
	v_changed boolean;
	v_newvars jsonb;
BEGIN
	-- check for error status
	IF a_outargs ? 'error' THEN
		PERFORM do_task_error(a_jobtask, a_outargs);
		RETURN;
	END IF;

	BEGIN
		SELECT vars_changed, newvars INTO v_changed, v_newvars FROM do_outargsmap(a_jobtask, a_outargs);
	EXCEPTION WHEN OTHERS THEN
		v_error = jsonb_build_object(
			'error', jsonb_build_object(
				'msg',  format('caught exception in do_outargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM),
				'class', 'normal'
			)
		);
		PERFORM do_task_error(a_jobtask, v_error);
		RETURN;
	END;

	-- bleh.. we want the 'old' value of outargs..
	SELECT out_args INTO v_inargs FROM jobs WHERE job_id = a_jobtask.job_id; -- FOR UPDATE OF jobs;

	UPDATE jobs SET
		state = 'done',
		variables = v_newvars,
		task_completed = now(),
		cookie = NULL,
		timeout = NULL
	WHERE job_id = a_jobtask.job_id;

	PERFORM do_log(a_jobtask.job_id, v_changed, v_inargs, a_outargs);

	-- wake the maestro
	RAISE NOTICE 'NOTIFY "jobtaskdone", %', a_jobtask::text;
	PERFORM pg_notify('jobtaskdone', a_jobtask::text);

	RETURN;
END$function$
