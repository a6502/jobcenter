CREATE OR REPLACE FUNCTION jobcenter.is_workflow(integer)
 RETURNS boolean
 LANGUAGE sql
AS $function$ select exists ( select 1 from actions where action_id = $1 and type = 'workflow' ); $function$
