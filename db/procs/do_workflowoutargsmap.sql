CREATE OR REPLACE FUNCTION jobcenter.do_workflowoutargsmap(a_jobtask jobtask, a_args jsonb, a_env jsonb, a_vars jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_code text;
	v_outargs jsonb;
	v_key text;
	v_type text;
	v_opt boolean;
	v_val jsonb;
	v_actual text;
	v_fields text[];
BEGIN
	SELECT wfmapcode INTO v_code FROM actions WHERE action_id = a_jobtask.workflow_id;

	a_env = do_populate_env(a_jobtask, a_env);

	v_outargs := do_wfomap(v_code, a_args, a_env, a_vars);
	
	PERFORM do_outargscheck(a_jobtask.workflow_id, v_outargs);

	RETURN v_outargs;
END$function$
