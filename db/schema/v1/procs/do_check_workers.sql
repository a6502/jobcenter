CREATE OR REPLACE FUNCTION jobcenter.do_check_workers()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$
update workers set
	stopped = now()
where
	stopped IS NULL
	and last_ping + interval '12 minutes' < now();
$function$
