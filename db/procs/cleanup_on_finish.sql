CREATE OR REPLACE FUNCTION jobcenter.cleanup_on_finish()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$BEGIN
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
		out_args = '"aborted by parent job"'::jsonb,
		job_finished = now()
	WHERE
		parentjob_id = NEW.job_id
		AND state NOT IN ('finished','error');

	RETURN null;
END$function$
