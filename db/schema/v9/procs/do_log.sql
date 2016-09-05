CREATE OR REPLACE FUNCTION jobcenter.do_log(a_job_id bigint, a_logvars boolean, a_inargs jsonb, a_outargs jsonb)
 RETURNS void
 LANGUAGE sql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$
INSERT INTO
	job_task_log (
		job_id,
		workflow_id,
		task_id,
		variables,
		task_entered,
		task_started,
		task_completed,
		worker_id,
		task_inargs,
		task_outargs
	)
SELECT
	job_id,
	workflow_id,
	task_id,
	CASE WHEN a_logvars THEN variables ELSE null END,
	task_entered,
	task_started,
	task_completed,
	worker_id,
	a_inargs as task_inargs,
	a_outargs as task_outargs
FROM jobs
WHERE job_id = a_job_id;
$function$
