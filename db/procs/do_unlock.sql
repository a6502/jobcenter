CREATE OR REPLACE FUNCTION jobcenter.do_unlock(a_locktype text, a_lockvalue text, a_contended integer, a_job_id bigint, a_parentjob_id bigint)
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
	IF a_contended > 0 THEN
		SELECT 
			job_id, task_id, workflow_id, waitforlockinherit
			INTO v_waitjob_id, v_waittask_id, v_waitworkflow_id, v_waitinherit
		FROM
			jobs
		WHERE
			waitforlocktype = a_locktype
			AND waitforlockvalue = a_lockvalue
			AND state = 'sleeping'
		-- try to give locks to our siblings first?
		ORDER BY coalesce(parentjob_id=a_parentjob_id, false) DESC, job_id nulls LAST LIMIT 1
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
				AND locktype = v_locktype
				AND lockvalue = v_lockvalue;

			-- mark task done
			UPDATE jobs SET
				state = 'done',
				waitforlocktype = null,
				waitforlockvalue = null,
				waitforlockinherit = null,
				task_completed = now()
			WHERE
				job_id = v_waitjob_id;

			-- log completion of lock task
			v_waitjobtask = (v_waitworkflow_id,v_waittask_id,v_waitjob_id)::jobtask;
			PERFORM do_log(v_waitjob_id, false, jsonb_build_object('locktype', v_locktype, 'lockvalue', v_lockvalue), null);
			-- wake up maestro
			PERFORM pg_notify( 'jobtaskdone', v_waitjobtask::text);
		-- ELSE
		-- FIXME: raise an error?
		END IF;
	ELSE
		-- just delete
		DELETE FROM
			locks
		WHERE
			job_id = a_job_id
			AND locktype =  a_locktype
			AND lockvalue = a_lockvalue;
	END IF;
END;$function$
