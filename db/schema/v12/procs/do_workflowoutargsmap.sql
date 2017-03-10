CREATE OR REPLACE FUNCTION jobcenter.do_workflowoutargsmap(a_jobtask jobtask)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_args jsonb;
	v_env jsonb;
	v_vars jsonb;
	v_code text;
	v_outargs jsonb;
	v_key text;
	v_type text;
	v_opt boolean;
	v_val jsonb;
	v_actual text;
	v_fields text[];
BEGIN
	--SELECT wfmapcode INTO v_code FROM actions WHERE action_id = a_jobtask.workflow_id;

	SELECT
		arguments, environment, variables, attributes->>'wfmapcode'
		INTO v_args, v_env, v_vars, v_code
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND workflow_id = a_jobtask.workflow_id
		AND task_id= a_jobtask.task_id;

	v_env = do_populate_env(a_jobtask, v_env);

	RAISE NOTICE 'do_workflowoutargsmap wfmapcode % env %', v_code, v_env;

	v_outargs := do_wfomap(v_code, v_args, v_env, v_vars);

	RAISE NOTICE 'do_workflowoutargsmap wf % task % job % vars % => outargs %', a_jobtask.workflow_id, a_jobtask.task_id, a_jobtask.job_id, v_vars, v_outargs;
	
	PERFORM do_outargscheck(a_jobtask.workflow_id, v_outargs);

	RETURN v_outargs;
END$function$
