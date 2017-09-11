CREATE OR REPLACE FUNCTION jobcenter.do_populate_env(a_jobtask jobtask, a_env jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$
SELECT
	COALESCE(a_env, '{}'::jsonb)
	|| jsonb_build_object(
		'workflow_id', a_jobtask.workflow_id,
		'job_id', a_jobtask.job_id,
		'task_id', a_jobtask.task_id);
$function$
