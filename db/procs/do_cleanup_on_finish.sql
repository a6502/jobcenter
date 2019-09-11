CREATE OR REPLACE FUNCTION jobcenter.do_cleanup_on_finish(a_jobtask jobtask)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_parentjob_id bigint;
	v_locktype text;
	v_lockvalue text;
	v_contended integer;
	v_top_level_job_id bigint;
BEGIN
	RAISE NOTICE 'do_cleanup_on_finish %', a_jobtask;
	-- paranoia
	SELECT
		parentjob_id INTO v_parentjob_id
	FROM
		jobs
	WHERE
		job_id = a_jobtask.job_id
		AND (
			(state IN ('finished', 'error') AND job_finished IS NOT NULL)
			OR
			state IN ('zombie')
		);

	IF NOT FOUND THEN
		RAISE NOTICE 'cleanup_on_finish: nothing to clean up?';
		RETURN;
	END IF;

	-- delete subscriptions
	DELETE FROM event_subscriptions WHERE job_id = a_jobtask.job_id;
	-- fkey cascaded delete should delete from job_events
	-- now delete events that no-one is waiting for anymore
	-- FIXME: use knowledge of what was deleted?
	DELETE FROM queued_events WHERE event_id NOT IN (SELECT event_id FROM job_events);

	-- signal any remaining child jobs to abort cq raise an abort error
	UPDATE
		jobs
	SET
		aborted = true
	WHERE
		parentjob_id = a_jobtask.job_id
		AND job_finished IS NULL
		AND state NOT IN ('finished', 'error', 'zombie');

	-- unlock all remaining locks
	--LOCK TABLE locks IN SHARE ROW EXCLUSIVE MODE;
	FOR v_locktype, v_lockvalue, v_contended, v_top_level_job_id IN
			SELECT locktype, lockvalue, contended, top_level_job_id
				FROM locks WHERE job_id=a_jobtask.job_id FOR UPDATE LOOP
		PERFORM do_unlock(v_locktype, v_lockvalue, v_contended, a_jobtask.job_id, v_parentjob_id, v_top_level_job_id);
	END LOOP;

	-- done cleaning up?
	RETURN;
END$function$
