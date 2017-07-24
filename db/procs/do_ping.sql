CREATE OR REPLACE FUNCTION jobcenter.do_ping(a_worker_id bigint)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$
/* not used anymore
-- do notify for all jobs in the ready state for this worker
-- that are older than 1 minute
-- FIXME: make timeout configurable?
SELECT
	pg_notify('action:' || action_id || ':ready', '{"poll":"prettyplease"}')
FROM
	jobs 
	JOIN tasks USING (workflow_id, task_id)
	JOIN actions USING (action_id) 
	JOIN worker_actions using (action_id)
WHERE
	worker_actions.worker_id = a_worker_id
	AND jobs.state = 'ready'
	AND jobs.task_entered < now() - interval '1 minute'
GROUP BY
	action_id;
*/
$function$
