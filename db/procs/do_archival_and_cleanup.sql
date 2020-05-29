CREATE OR REPLACE FUNCTION jobcenter.do_archival_and_cleanup(dummy text DEFAULT 'dummy'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'jobcenter', 'pg_catalog', 'pg_temp'
AS $function$DECLARE
	v_last timestamp with time zone;
	v_name text;
	v_calls bigint;
BEGIN
	-- mark dead/gone/whatever workers as disconnected
	PERFORM
		disconnect(name)
	FROM
		workers
	WHERE
		stopped IS NULL
		AND last_ping + interval '3 minutes' < now();
	-- update statistics before cleaning up jobs table
	v_last := COALESCE((SELECT last FROM call_stats_collected), '-infinity');
	FOR v_name, v_calls IN 
		SELECT 
			a.name, COUNT(*)
		FROM 
			jobs AS j JOIN actions AS a 
		ON 
			j.workflow_id = a.action_id
		WHERE 
			j.job_created > v_last
		GROUP BY 
			a.name
	LOOP
		INSERT INTO
			call_stats (name, calls)
		VALUES
			(v_name, v_calls)
		ON CONFLICT
			(name)
		DO UPDATE SET calls = call_stats.calls + EXCLUDED.calls;
	END LOOP;
	-- record last collection time
	INSERT INTO
		 call_stats_collected (last)
	VALUES
		 (now())
	ON CONFLICT
		 (unique_id)
	DO UPDATE SET last = EXCLUDED.last;
	-- move finished jobs to the jobs_archive table
	WITH jobrecords AS (
		DELETE FROM
			jobs p
		WHERE
			state = 'finished'
			AND job_finished < now() - interval '1 minute'
			AND NOT EXISTS (
				SELECT
					true
				FROM
					jobs c
				WHERE
					c.parentjob_id=p.job_id
				LIMIT 1
			)
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
END$function$
