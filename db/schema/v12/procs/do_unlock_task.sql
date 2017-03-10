CREATE OR REPLACE FUNCTION jobcenter.do_unlock_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_action_id int;
	v_parentjob_id bigint;
	v_locktype text;
	v_lockvalue text;
	v_stringcode text;
	v_contended integer;
	v_top_level_job_id bigint;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, environment, variables, action_id, parentjob_id,
		attributes->>'locktype', attributes->>'lockvalue', attributes->>'stringcode'
		INTO v_args, v_env, v_vars, v_action_id, v_parentjob_id,
		v_locktype, v_lockvalue, v_stringcode
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id
		AND actions.type = 'system'
		AND actions.name = 'unlock';
		
	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_unlock_task called for non-unlock-task %', a_jobtask.task_id;
	END IF;

	IF v_lockvalue IS NULL THEN
		BEGIN
			v_lockvalue := do_stringcode(v_stringcode, v_args, v_env, v_vars);
		EXCEPTION WHEN OTHERS THEN
			RETURN do_raise_error(a_jobtask,
				format('caught exception in do_stringcode sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
		END;
	END IF;

	RAISE NOTICE 'do_unlock_task locktype "%" lockvalue "%:', v_locktype, v_lockvalue;

	SELECT
		contended, top_level_job_id
		INTO v_contended, v_top_level_job_id
	FROM
		locks
	WHERE
		job_id = a_jobtask.job_id
		AND locktype =  v_locktype
		AND lockvalue = v_lockvalue
	FOR UPDATE OF locks;

	IF NOT FOUND THEN
		-- or do a warning instead?
		RETURN do_raise_error(a_jobtask, format('tried to unlock not held lock locktype %s lockvalue %s', v_locktype, v_lockvalue));
	END IF;

	PERFORM do_unlock(v_locktype, v_lockvalue, v_contended, a_jobtask.job_id, v_parentjob_id, v_top_level_job_id);

	RETURN do_task_epilogue(a_jobtask, false, null, jsonb_build_object('locktype', v_locktype, 'lockvalue', v_lockvalue), null);
END;$function$
