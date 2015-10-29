CREATE OR REPLACE FUNCTION jobcenter.check_job_is_waiting(bigint, boolean)
 RETURNS boolean
 LANGUAGE sql
AS $function$
select exists (
	select 1 from jobs where 
	job_id = $1
	and case when $2 THEN state='waiting' ELSE state<>'waiting' end
); 
$function$
