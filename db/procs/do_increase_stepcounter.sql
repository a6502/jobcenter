CREATE OR REPLACE FUNCTION jobcenter.do_increase_stepcounter()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$BEGIN
	NEW.stepcounter = OLD.stepcounter + 1;
	-- RAISE NOTICE 'stepcounter job_id % task_id % steps %', NEW.job_id, NEW.task_id, NEW.stepcounter;
	RETURN NEW;
END;$function$
