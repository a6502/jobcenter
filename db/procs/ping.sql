CREATE OR REPLACE FUNCTION jobcenter.ping(a_worker_id bigint)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
AS $function$
UPDATE workers SET
	last_ping = now()
WHERE
	worker_id = a_worker_id
	AND stopped IS NULL;
SELECT pg_notify('ping', a_worker_id::text);
SELECT 'pong'::text; -- dummy return value
$function$
