CREATE OR REPLACE FUNCTION jobcenter.do_check_job_is_waiting(bigint, boolean)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$
select exists (
	select 1 from jobs where 
	job_id = $1
	and case when $2 THEN state='eventwait' ELSE state<>'eventwait' end
); 
$function$
