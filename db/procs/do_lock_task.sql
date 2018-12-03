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
	v_lockwait text;
	v_stringcode text;
	v_newvars jsonb;
	v_contended integer;
	v_parentjob_id bigint;
	v_top_level_job_id bigint;
	v_inheritable boolean;
	v_lockjob_id bigint;
	v_deadlockpath bigint[];
	v_timeout timestamptz;
BEGIN
	-- paranoia check with side effects
	SELECT
		arguments, environment, variables, action_id, parentjob_id,
		attributes->>'locktype', attributes->>'lockvalue', (attributes->>'lockinherit')::boolean,
		attributes->>'stringcode', COALESCE(attributes->>'lockwait', 'yes')
		INTO v_args, v_env, v_vars, v_action_id, v_parentjob_id,
		v_locktype, v_lockvalue, v_lockinherit, v_stringcode, v_lockwait
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

	IF v_lockvalue IS NULL AND v_stringcode IS NOT NULL THEN
		BEGIN
			SELECT
				 * INTO v_lockvalue, v_newvars
			FROM
				 do_stringcode(v_stringcode, v_args, v_env, v_vars);
		EXCEPTION WHEN OTHERS THEN
			RETURN do_raise_error(a_jobtask,
				format('caught exception in do_stringcode sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM));
		END;
	END IF;
		
	IF v_lockvalue IS NULL THEN
		RETURN do_raise_error(a_jobtask,
			format('no lockvalue for locktype %s', v_locktype));
	END IF;

	RAISE NOTICE 'do_lock_task locktype "%" lockvalue "%"', v_locktype, v_lockvalue;

	INSERT INTO 
		locks (job_id, locktype, lockvalue, inheritable,
			top_level_job_id)
	VALUES
		(a_jobtask.job_id, v_locktype, v_lockvalue, v_lockinherit,
		 CASE WHEN v_lockinherit THEN a_jobtask.job_id ELSE NULL END)
	ON CONFLICT
		(locktype, lockvalue)
	DO UPDATE
		SET contended = locks.contended + 1
	WHERE
		locks.locktype=v_locktype AND locks.lockvalue = v_lockvalue
	RETURNING
		job_id, contended, inheritable INTO v_lockjob_id, v_contended, v_inheritable;

	IF v_contended = 0 AND v_lockjob_id = a_jobtask.job_id THEN
		-- now that was easy
		RETURN do_task_epilogue(a_jobtask, false, null, jsonb_build_object('locktype', v_locktype, 'lockvalue', v_lockvalue), null);
	END IF;

	IF v_lockjob_id = a_jobtask.job_id THEN
		RETURN do_raise_error(a_jobtask, format('reacquired locktype %s lockvalue %s', v_locktype, v_lockvalue));
	END IF;

	IF v_contended = 0 THEN
		RETURN do_raise_error(a_jobtask, format('uncontended locktype %s lockvalue %s not owned by us but by %s', v_locktype, v_lockvalue, v_lockjob_id));
	END IF;
	
	-- see if we can inherit the lock
	IF v_lockjob_id = v_parentjob_id AND v_inheritable THEN
		PERFORM true FROM jobs WHERE job_id = v_parentjob_id AND state = 'childwait';
		IF FOUND THEN
			-- we can actually inherit the lock
			UPDATE locks SET
				job_id = a_jobtask.job_id,
				contended = contended - 1,
				inheritable = v_lockinherit
			WHERE
				locktype= v_locktype
				AND lockvalue = v_lockvalue
				AND job_id = v_lockjob_id;
			-- fixme: check found?
			RETURN do_task_epilogue(a_jobtask, false, null, jsonb_build_object('locktype', v_locktype, 'lockvalue', v_lockvalue), null);
		END IF;
	END IF;

	IF v_lockwait = 'no' THEN
		-- raise error;
		RETURN do_raise_error(a_jobtask,
				format('failed to get locktype %s lockvalue %s',
					v_locktype, v_lockvalue
				)
			);
	ELSIF v_lockwait = 'yes' THEN
		v_timeout = null;
	ELSE
		-- catch?
		v_timeout = now() + v_lockwait::interval;
	END IF;

	-- mark ourselves as waiting for this lock
	-- fixme: log inargs?
	UPDATE jobs SET
		state = 'lockwait',
		task_state = jsonb_build_object(
			'waitforlocktype', v_locktype,
			'waitforlockvalue', v_lockvalue,
			'waitforlockinherit', v_lockinherit),
		task_started = now(),
		timeout = v_timeout
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
				AND state = 'lockwait'
		UNION ALL
			SELECT
				l.job_id,
				path || l.job_id,
				l.job_id = ANY(path)
			FROM
				jobs j
				JOIN locks l on j.task_state->>'waitforlocktype'=l.locktype AND j.task_state->>'waitforlockvalue'=l.lockvalue
				JOIN detect_deadlock dd ON j.job_id = dd.job_id
			WHERE
				j.state = 'lockwait' AND
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
