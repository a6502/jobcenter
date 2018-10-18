CREATE OR REPLACE FUNCTION jobcenter.disconnect(a_workername text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$
BEGIN
	RETURN BOOL_AND(do_withdraw(a_workername, a.name, disconnecting => TRUE)) 
		FROM workers AS w 
		JOIN worker_actions AS wa USING(worker_id) 
		JOIN actions AS a USING(action_id) 
		WHERE w.name = a_workername;
END$function$

