CREATE OR REPLACE FUNCTION jobcenter.poll_tasks(a_worker_ids bigint[])
 RETURNS TABLE(listenstring text, worker_ids bigint[], count bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'jobcenter', 'pg_catalog', 'pg_temp'
AS $function$
	SELECT
		'action:' || wa.action_id || ':ready' AS listenstring,
		CASE WHEN wa.filter IS NOT NULL THEN
			array_agg(distinct(wa.worker_id))
		ELSE
			null
		END AS workers,
		count(distinct(j.job_id)) AS "count"
	FROM
		worker_actions wa
		JOIN tasks USING (action_id)
		JOIN jobs j USING (workflow_id, task_id)
	WHERE
		wa.worker_id = ANY(a_worker_ids)
		AND j.state = 'ready'
		AND ( wa.filter IS NULL
		      OR j.out_args @> wa.filter )
	GROUP BY
		wa.action_id, wa.filter;
$function$
