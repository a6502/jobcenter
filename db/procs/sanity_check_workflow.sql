CREATE OR REPLACE FUNCTION jobcenter.sanity_check_workflow(a_workflow_id integer)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$DECLARE
	v_task_id integer;
	v_next_task_id integer;
BEGIN
	FOR v_task_id, v_next_task_id IN
			SELECT task_id, next_task_id FROM tasks WHERE workflow_id = a_workflow_id LOOP
		IF v_next_task_id IS NULL THEN
			RAISE EXCEPTION 'next_task_id may not be null in task %', v_task_id;
		END IF;

		PERFORM true FROM
			tasks
		WHERE
			task_id = v_next_task_id
			AND workflow_id = a_workflow_id;

		IF NOT FOUND THEN
			RAISE EXCEPTION 'next_task_id % not in workflow %', v_next_task_id, a_workflow_id;
		END IF;
	END LOOP;

	RETURN true;
END;$function$
