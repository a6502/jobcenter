CREATE OR REPLACE FUNCTION jobcenter.do_check_workers()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
update workers set
	stopped = now()
where
	stopped IS NULL
	and last_ping + interval '12 minutes' < now();
$function$
