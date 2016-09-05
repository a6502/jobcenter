create role $JCPERL;

grant $JCPERL to $JCSYSTEM;

GRANT $JCCLIENT to $JCADMIN;

GRANT ALL ON SCHEMA jobcenter TO $JCPERL;

CREATE EXTENSION IF NOT EXISTS plperl;

drop extension plperlu;

DROP FUNCTION IF EXISTS jobcenter.nexttask(error boolean, workflow_id integer, task_id integer, job_id bigint);

DROP FUNCTION IF EXISTS jobcenter.do_raise_fatal_error(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_errmsg text);

drop type nexttask;

update _schema set version = 9;

