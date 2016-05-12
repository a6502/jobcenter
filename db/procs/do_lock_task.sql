CREATE OR REPLACE FUNCTION jobcenter.do_lock_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_action_id int;
	v_locktype text;
	v_lockvalue text;
	v_lockinherit boolean;
	v_stringcode text;
	v_gotlock boolean DEFAULT false;
	v_parentjob_id bigint;
	v_lockjob_id bigint;
	v_deadlockpath bigint[];
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, environment, variables, action_id, parentjob_id,
		attributes->>'locktype', attributes->>'lockvalue', (attributes->>'lockinherit')::boolean,
		attributes->>'stringcode'
		INTO v_args, v_env, v_vars, v_action_id, v_parentjob_id,
		v_locktype, v_lockvalue, v_lockinherit,
		v_stringcode
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND task_id = a_jobtask.task_id
		AND workflow_id = a_jobtask.workflow_id
		AND actions.type = 'system'
		AND actions.name = 'lock';
		
	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_lock_task called for non-lock-task %', a_jobtask.task_id;
	END IF;

	IF v_lockvalue IS NULL THEN
		BEGIN
			v_lockvalue := do_stringcode(v_stringcode, v_args, v_env, v_vars);
		EXCEPTION WHEN OTHERS THEN
			RETURN do_raise_error(a_jobtask,
				format('caught exception in do_stringcode sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
		END;
	END IF;
		
	RAISE NOTICE 'do_lock_task locktype "%" lockvalue "%"', v_locktype, v_lockvalue;

	INSERT INTO 
		locks (job_id, locktype, lockvalue, inheritable)
	VALUES
		(a_jobtask.job_id, v_locktype, v_lockvalue, v_lockinherit)
	ON CONFLICT (locktype, lockvalue) DO UPDATE
	SET contended = locks.contended + 1 WHERE locks.locktype=v_locktype AND locks.lockvalue = v_lockvalue
	RETURNING job_id INTO v_lockjob_id;

	IF v_lockjob_id = a_jobtask.job_id THEN
		-- now that was easy
		RETURN do_task_epilogue(a_jobtask, false, null, jsonb_build_object('locktype', v_locktype, 'lockvalue', v_lockvalue), null);
	END IF;
	
	-- see if we can inherit the lock
	--IF v_lockjob_id = v_parentjob_id

	-- mark ourselves as waiting for this lock
	-- fixme: log inargs?
	UPDATE jobs SET
		state = 'sleeping', -- FIXME: whut
		waitforlocktype = v_locktype,
		waitforlockvalue = v_lockvalue,
		waitforlockinherit = v_lockinherit,
		task_started = now()
	WHERE
		job_id = a_jobtask.job_id;

	-- now see if we have a cycle of sleeping jobs
	WITH RECURSIVE detect_deadlock(job_id, path, cycle) AS (
			SELECT
				 job_id,
				 ARRAY[job_id] as path,
				 false as cycle
			FROM
				 jobs
			WHERE
				job_id = v_lockjob_id
				AND state = 'sleeping'
		UNION ALL
			SELECT
				l.job_id,
				path || l.job_id,
				l.job_id = ANY(path)
			FROM
				jobs j
				JOIN locks l on j.waitforlocktype=l.locktype AND j.waitforlockvalue=l.lockvalue
				JOIN detect_deadlock dd ON j.job_id = dd.job_id
			WHERE
				j.state = 'sleeping' AND
				NOT cycle
	)
	SELECT path INTO v_deadlockpath FROM detect_deadlock WHERE cycle=true;

	IF v_deadlockpath IS NOT NULL THEN
		-- now what?
		-- if the error proves fatal then the cleanup
		-- will cleanup our locks and unlock the other job(s)
		RETURN do_raise_error(a_jobtask,
				format('deadlock trying to get locktype %s lockvalue %s path %s',
					v_locktype, v_lockvalue, array_to_string(v_deadlockpath, ', ')
				)
			);
	END IF;

	RETURN null; -- no next task
END;$function$
