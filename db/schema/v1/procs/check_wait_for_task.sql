CREATE OR REPLACE FUNCTION jobcenter.check_wait_for_task(a_action_id integer, a_wait_for_task integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$BEGIN
	PERFORM true FROM actions WHERE action_id = a_action_id AND type = 'system' AND name = 'wait_for';
	IF FOUND THEN
		RETURN a_wait_for_task IS NOT NULL;
	ELSE
		RETURN a_wait_for_task IS NULL;
	END IF;
END;$function$
