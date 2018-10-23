CREATE OR REPLACE FUNCTION jobcenter.do_crash_recovery(dummy text DEFAULT 'dummy'::text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$
-- move 'plotting' jobs back to 'done'
UPDATE
	jobs
SET
	state = 'done'
WHERE
	state = 'plotting';
-- now notify the maestro for each job in 'done'
SELECT
	pg_notify('jobtaskdone', ( '(' || workflow_id || ',' || task_id || ',' || job_id || ')' ))
FROM
	jobs
WHERE
	state='done';
$function$
