CREATE OR REPLACE FUNCTION jobcenter.ping(a_worker_id bigint)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$BEGIN
	RAISE NOTICE 'ping from %', a_worker_id;
	UPDATE workers SET
		last_ping = now()
	WHERE
		worker_id = a_worker_id
		AND stopped IS NULL;

	IF NOT FOUND THEN
		-- we have a zombie worker?
		RETURN null;
	END IF;

	-- see if there is some work for this worker
	PERFORM
		pg_notify(
			'action:' || wa.action_id || ':ready',
			 CASE WHEN wa.filter IS NOT NULL THEN
				jsonb_build_object(
					'poll', 'prettyplease',
					'workers', array[a_worker_id]
				)::text
			ELSE
				jsonb_build_object(
					'poll', 'prettyplease'
				)::text
			END
		)
	FROM
		jobs j
		JOIN tasks t USING (workflow_id, task_id)
		JOIN actions a USING (action_id)
		JOIN worker_actions wa USING (action_id)
	WHERE
		wa.worker_id = a_worker_id
		AND j.state = 'ready'
		AND j.task_entered < now() - interval '1 minute'
		AND ( wa.filter IS NULL
		      OR j.out_args @> wa.filter )
	GROUP BY
		wa.action_id, wa.filter;

	RETURN 'pong';
END;$function$
