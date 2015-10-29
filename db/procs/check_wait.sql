CREATE OR REPLACE FUNCTION jobcenter.check_wait(a_action_id integer, a_wait boolean)
 RETURNS boolean
 LANGUAGE plpgsql
AS $function$BEGIN
	IF a_wait THEN
		RETURN TRUE;
	END IF;
	PERFORM true FROM actions WHERE action_id = a_action_id AND type = 'workflow';
	RETURN FOUND;
END;$function$
