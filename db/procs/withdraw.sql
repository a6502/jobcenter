CREATE OR REPLACE FUNCTION jobcenter.withdraw(a_workername text, a_actionname text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$
BEGIN
	PERFORM do_withdraw(a_workername, a_actionname, disconnecting => false);
	RETURN true;
END$function$
