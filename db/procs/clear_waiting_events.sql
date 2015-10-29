CREATE OR REPLACE FUNCTION jobcenter.clear_waiting_events()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$BEGIN
	IF NEW.state <> 'waiting' THEN
		UPDATE event_subscriptions SET waiting = false WHERE job_id = NEW.job_id;
	END IF;
	RETURN null;
END$function$
