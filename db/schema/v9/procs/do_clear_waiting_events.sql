CREATE OR REPLACE FUNCTION jobcenter.do_clear_waiting_events()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$BEGIN
	IF NEW.state <> 'waiting' THEN
		UPDATE event_subscriptions SET waiting = false WHERE job_id = NEW.job_id;
	END IF;
	RETURN null;
END$function$
