CREATE OR REPLACE FUNCTION jobcenter.cleanup_on_finish()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_job_id bigint;
	v_locktype text;
	v_lockvalue text;
	v_contended boolean;
	v_waitjob_id bigint;
	v_waittask_id int;
	v_waitworkflow_id int;
BEGIN
	-- paranoia
	IF NEW.job_finished IS NULL THEN
		RETURN null;
	END IF;

	-- delete subscribtions
	DELETE FROM event_subscriptions WHERE job_id = NEW.job_id;
	-- fkey cascaded delete should delete from job_events
	-- now delete events that no-one is waiting for anymore
	-- FIXME: use knowledge of what was deleted?
	DELETE FROM queued_events WHERE event_id NOT IN (SELECT event_id FROM job_events);
	-- abort any child jobs
	UPDATE
		jobs
	SET
		state = 'error',
		out_args = '{"error":{"msg":"aborted by parent job","class":"abort"}}'::jsonb,
		job_finished = now(),
		timeout = null
	WHERE
		parentjob_id = NEW.job_id
		AND state NOT IN ('finished','error');

	-- unlock all locks
	LOCK TABLE locks IN SHARE ROW EXCLUSIVE MODE;
	FOR v_locktype, v_lockvalue, v_contended IN
			DELETE FROM locks WHERE job_id=NEW.job_id RETURNING locktype, lockvalue LOOP
		IF v_contended THEN
			SELECT 
				job_id, task_id, workflow_id
				INTO v_waitjob_id, v_waittask_id, v_waitworkflow_id
			FROM
				jobs
			WHERE
				waitforlocktype = v_locktype
				AND waitforlockvalue = v_lockvalue
				AND state = 'sleeping'
			FOR UPDATE OF jobs;
			
			IF FOUND THEN
				-- create lock for blocked task
				INSERT INTO locks (job_id, locktype, lockvalue) VALUES (v_waitjob_id, v_locktype, v_lockvalue);
				-- mark task done
				UPDATE jobs SET
					state = 'done',
					waitforlocktype = null,
					waitforlockvalue = null,
					task_completed = now()
				WHERE
					job_id = v_waitjob_id;
				-- log something
				INSERT INTO job_task_log (job_id, workflow_id, task_id, task_entered, task_started, task_completed)
				SELECT job_id, workflow_id, task_id, task_entered, task_started, task_completed
				FROM jobs
				WHERE job_id = v_waitjob_id;
				-- wake up maestro
				PERFORM pg_notify( 'jobtaskdone',  (v_waitworkflow_id::TEXT || ':' || v_waittask_id::TEXT || ':' || v_waitjob_id::TEXT ));
			END IF;
				
		END IF;
	END LOOP;
	-- done cleaning up?
	RETURN null;
END$function$
