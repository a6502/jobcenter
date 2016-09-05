CREATE OR REPLACE FUNCTION jobcenter.do_is_workflow(integer)
 RETURNS boolean
 LANGUAGE sql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$ select exists ( select 1 from actions where action_id = $1 and type = 'workflow' ); $function$
