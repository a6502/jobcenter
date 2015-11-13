
CREATE SCHEMA jobcenter AUTHORIZATION $JCADMIN;
ALTER SCHEMA jobcenter OWNER TO $JCADMIN;

SET search_path = jobcenter, pg_catalog, pg_temp;

REVOKE ALL ON SCHEMA jobcenter FROM PUBLIC;
GRANT ALL ON SCHEMA jobcenter TO $JCADMIN;
GRANT USAGE ON SCHEMA jobcenter TO $JCCLIENT;
GRANT USAGE ON SCHEMA jobcenter TO $JCMAESTRO;
--GRANT USAGE ON SCHEMA jobcenter TO $JCSYSTEM;
GRANT ALL ON SCHEMA jobcenter TO $JCSYSTEM;

CREATE TYPE action_type AS ENUM (
    'system',
    'action',
    'workflow'
);
ALTER TYPE action_type OWNER TO $JCADMIN;

CREATE TYPE job_state AS ENUM (
    'ready',
    'working',
    'waiting',
    'blocked',
    'sleeping',
    'done',
    'plotting',
    'zombie',
    'finished',
    'error'
);
ALTER TYPE job_state OWNER TO $JCADMIN;

COMMENT ON TYPE job_state IS 'ready: waiting for a worker to pick this jobtask
working: waiting for a worker to finish this jobtask
waiting: waiting for some external event or timeout
blocked: waiting for a subjob to finish
done: waiting for the maestro to start plotting
plotting: waiting for the maestro to decide
zombie: waiting for a parent job to wait for us
finished: done waiting
error: ?';

CREATE TYPE nexttask AS (
	error boolean,
	workflow_id integer,
	task_id integer,
	job_id bigint
);
ALTER TYPE nexttask OWNER TO $JCADMIN;

