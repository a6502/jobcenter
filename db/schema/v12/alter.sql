create index on jobs (timeout);

insert into actions (action_id, name, type, version) values (-15, 'sleep', 'system', 0);

insert into action_inputs(action_id, name, type, optional) values (-15, 'timeout', 'string', false);

alter table jobs add column task_state jsonb;

alter table job_task_log add column task_state jsonb;

alter table jobs add column job_state jsonb;

create index on jobs (state);

alter table actions add column config jsonb;

update only tasks t set attributes=jsonb_build_object('wfmapcode', wfmapcode) from actions a where t.workflow_id=a.action_id and t.action_id=-1;

alter table actions drop column wfmapcode;

update tasks set attributes=jsonb_build_object('reapfromtask_id', reapfromtask_id) where reapfromtask_id is not null;

alter table tasks drop column reapfromtask_id;

alter table tasks drop column wait;

alter table jobs drop column worker_id;

alter table job_task_log drop column worker_id;

alter table jobs drop column waitforlocktype, drop column waitforlockvalue, drop column waitforlockinherit;

alter index job_parent_jobid_index rename to job_parentjob_id_index;

drop index job_actionid_index;;

alter index steps_pkey rename to tasks_pkey;

alter table jobs drop column parenttask_id, drop column parentwait;

create index on workers (stopped);

DO $BODY$
BEGIN
        RAISE NOTICE 'Please load super.sql as a Postgresql superuser.';
END
$BODY$;
