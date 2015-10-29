CREATE OR REPLACE FUNCTION jobcenter.notify_timerchange()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
	PERFORM
		pg_notify('timer'::text,
			(EXTRACT(EPOCH FROM MIN(timeout))
			 - EXTRACT(EPOCH FROM now()))::text
		)
	FROM
		jobs;
	RETURN NULL;
END$function$
