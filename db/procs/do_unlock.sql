CREATE OR REPLACE FUNCTION jobcenter.do_unlock(a_locktype text, a_lockvalue text, a_contended integer, a_job_id bigint, a_parentjob_id bigint, a_top_level_job_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_waitjob_id bigint;
	v_waittask_id int;
	v_waitworkflow_id int;
	v_waitinherit boolean;
	v_waitjobtask jobtask;
BEGIN
	-- determine if we inherited the lock
	IF a_parentjob_id IS NOT NULL -- we have a parent
			AND a_top_level_job_id IS NOT NULL -- and the lock was inheritable
			AND a_top_level_job_id <> a_job_id THEN-- and we actually inherited the lock

		IF a_contended > 0 THEN	-- see if one of our siblings is waiting for the lock
			SELECT 
				job_id, task_id, workflow_id, waitforlockinherit
				INTO v_waitjob_id, v_waittask_id, v_waitworkflow_id, v_waitinherit
			FROM
				jobs
			WHERE
				parentjob_id = a_parentjob_id
				AND task_state->>'waitforlocktype' = a_locktype
				AND task_state->>'waitforlockvalue' = a_lockvalue
				AND state = 'lockwait'
			ORDER BY job_id LIMIT 1
			FOR UPDATE OF jobs;

			-- ok, found a sibling
			IF FOUND THEN
				-- create lock for blocked task
				UPDATE
					locks
				SET
					job_id = v_waitjob_id,
					contended = contended - 1,
					inheritable = v_waitinherit
				WHERE
					job_id = a_job_id
					AND locktype = a_locktype
					AND lockvalue = a_lockvalue;

				-- mark task done
				UPDATE jobs SET
					state = 'done',
					task_completed = now()
				WHERE
					job_id = v_waitjob_id;

				-- log completion of lock task
				v_waitjobtask = (v_waitworkflow_id,v_waittask_id,v_waitjob_id)::jobtask;
				PERFORM do_log(v_waitjob_id, false, jsonb_build_object('locktype', a_locktype, 'lockvalue', a_lockvalue), null);
				-- wake up maestro
				PERFORM pg_notify( 'jobtaskdone', v_waitjobtask::text);

				RETURN; -- and done
			END IF;
			-- none-siblings cannot get the lock at this point
			-- because it actually belongs to our parent
		END IF;

		-- just give it back to the parent
		UPDATE
			locks
		SET
			job_id = a_parentjob_id,
			inheritable = true -- we got it so it was inheritable?
		WHERE
			job_id = a_job_id
			AND locktype = a_locktype
			AND lockvalue = a_lockvalue;
		RETURN;
	END IF;

	-- the lock is really ours to unlock
	IF a_contended > 0 THEN
		SELECT 
			job_id, task_id, workflow_id, (task_state->>'waitforlockinherit')::boolean
			INTO v_waitjob_id, v_waittask_id, v_waitworkflow_id, v_waitinherit
		FROM
			jobs
		WHERE
			task_state->>'waitforlocktype' = a_locktype
			AND task_state->>'waitforlockvalue' = a_lockvalue
			AND state = 'lockwait'
		ORDER BY job_id LIMIT 1 -- give to the oldest job first?
		FOR UPDATE OF jobs;
		
		IF FOUND THEN
			-- create lock for blocked task
			UPDATE
				locks
			SET
				job_id = v_waitjob_id,
				contended = contended - 1,
				inheritable = v_waitinherit
			WHERE
				job_id = a_job_id
				AND locktype = a_locktype
				AND lockvalue = a_lockvalue;

			-- mark task done
			UPDATE jobs SET
				state = 'done',
				--waitforlocktype = null,
				--waitforlockvalue = null,
				--waitforlockinherit = null,
				task_completed = now()
			WHERE
				job_id = v_waitjob_id;

			-- log completion of lock task
			v_waitjobtask = (v_waitworkflow_id,v_waittask_id,v_waitjob_id)::jobtask;
			PERFORM do_log(v_waitjob_id, false, jsonb_build_object('locktype', a_locktype, 'lockvalue', a_lockvalue), null);
			-- wake up maestro
			PERFORM pg_notify( 'jobtaskdone', v_waitjobtask::text);
			RETURN; -- and done
		-- ELSE
		-- the lock is contended but nobody is waiting?
		-- this can happen when a lock timed out..
		END IF;
	END IF;
	-- just delete
	DELETE FROM
		locks
	WHERE
		job_id = a_job_id
		AND locktype =  a_locktype
		AND lockvalue = a_lockvalue;
END;$function$
