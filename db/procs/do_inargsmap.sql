CREATE OR REPLACE FUNCTION jobcenter.do_inargsmap(a_action_id integer, a_jobtask jobtask, a_args jsonb, a_env jsonb, a_vars jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_key text;
	v_type text;
	v_opt boolean;
	v_def jsonb;
	v_code text;
	v_actual text;
	v_fields text[];
	v_val jsonb;
	v_inargs jsonb;
BEGIN
	a_env = do_populate_env(a_jobtask, a_env);
	SELECT attributes->>'imapcode' INTO v_code FROM tasks WHERE task_id = a_jobtask.task_id;
	v_inargs := do_imap(v_code, a_args, a_env, a_vars);

	v_inargs := do_inargscheck(a_action_id, v_inargs);

	RETURN v_inargs;
END$function$
