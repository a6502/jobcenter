CREATE OR REPLACE FUNCTION jobcenter.do_archival_and_cleanup(dummy text DEFAULT 'dummy'::text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$
-- mark dead/gone/whatever workers as stopped
UPDATE workers SET
	stopped = now()
WHERE
	stopped IS NULL
	AND last_ping + interval '3 minutes' < now();
-- move finished jobs to the jobs_archive table
WITH jobrecords AS (
	DELETE FROM
		jobs
	WHERE
		state = 'finished'
		AND job_finished < now() - interval '1 minute'
	RETURNING
		job_id,
		workflow_id,
		parentjob_id,
		state,
		arguments,
		job_created,
		job_finished,
		stepcounter,
		out_args,
		environment,
		max_steps,
		current_depth
)
INSERT INTO jobs_archive SELECT * FROM jobrecords;
$function$
