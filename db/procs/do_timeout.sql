CREATE OR REPLACE FUNCTION jobcenter.do_timeout()
 RETURNS integer
 LANGUAGE plpgsql
AS $function$DECLARE
	v_job_id bigint;
	v_task_id integer;
	v_workflow_id integer;
	v_state job_state;
	v_next integer;
	v_eventdata jsonb;
BEGIN
	FOR v_job_id, v_task_id, v_workflow_id, v_state IN SELECT job_id, task_id, workflow_id, state
			FROM jobs WHERE timeout < now() LOOP
		RAISE NOTICE 'job % state %', v_job_id, v_state;
		CASE v_state
		WHEN 'waiting', 'sleeping' THEN
			-- done waiting or sleeping then
			v_eventdata = jsonb_build_object(
				'name', 'timeout',
				'event_id', null,
				'when', now(),
				'data', null
			);
			v_eventdata = jsonb_build_object(
				'event', v_eventdata
			);
			RAISE NOTICE 'timeout of job %', v_job_id;
			PERFORM do_task_done(v_workflow_id, v_task_id, v_job_id, v_eventdata, true);
		WHEN 'working' THEN
			RAISE NOTICE 'job % timed out in task %', v_job_id, v_task_id;
			v_eventdata = jsonb_build_object(
				'name', 'timeout',
				'when', now()
			);			
			PERFORM do_task_error(v_workflow_id, v_task_id, v_job_id, v_eventdata);
		END CASE;
	END LOOP;

	SELECT
		(EXTRACT(EPOCH FROM MIN(timeout))
		- EXTRACT(EPOCH FROM now()))::integer
		AS seconds INTO v_next
	FROM
		jobs;
	RETURN v_next;
END;$function$
