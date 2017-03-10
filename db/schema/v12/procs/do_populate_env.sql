CREATE OR REPLACE FUNCTION jobcenter.do_populate_env(a_jobtask jobtask, a_env jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$
BEGIN
	IF a_env IS NULL THEN
		a_env = '{}'::jsonb;
	END IF;

	a_env := jsonb_set(a_env, '{workflow_id}', to_jsonb(a_jobtask.workflow_id));
	a_env := jsonb_set(a_env, '{job_id}', to_jsonb(a_jobtask.job_id));
	a_env := jsonb_set(a_env, '{task_id}', to_jsonb(a_jobtask.task_id));

	RETURN a_env;
END;$function$
