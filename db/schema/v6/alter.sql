
alter table jobs drop constraint jobs_waitfortask_id_fkey;

alter table jobs alter column waitfortask_id type boolean using false;

alter table jobs rename column waitfortask_id to parentwait;

alter table jobs alter column parentwait set default false;

ALTER TABLE jobs DISABLE TRIGGER on_job_finished;

DROP TRIGGER on_job_finished ON jobs;

CREATE TABLE jobs_archive
(
  job_id bigint NOT NULL,
  workflow_id integer NOT NULL,
  parentjob_id bigint,
  state job_state,
  arguments jsonb,
  job_created timestamp with time zone NOT NULL,
  job_finished timestamp with time zone NOT NULL,
  stepcounter integer NOT NULL DEFAULT 0,
  out_args jsonb,
  environment jsonb,
  CONSTRAINT job_history_pkey PRIMARY KEY (job_id),
  CONSTRAINT job_history_workflowid_fkey FOREIGN KEY (workflow_id)
      REFERENCES actions (action_id) MATCH SIMPLE
      ON UPDATE CASCADE ON DELETE RESTRICT
);

ALTER TABLE jobs_archive OWNER TO $JCADMIN;

GRANT SELECT, UPDATE, INSERT, TRUNCATE, DELETE ON TABLE jobs_archive TO $JCSYSTEM;

ALTER FUNCTION do_check_workers()
  RENAME TO do_archival_and_cleanup;

alter table jobs add column max_steps integer not null default 100;

alter table jobs_archive add column max_steps integer not null default 100;

alter table jobs add column aborted boolean not null default false;

alter table jobs alter column parentwait set not null;

alter table jcenv rename to jc_env;

CREATE TABLE jc_roles
(
  rolename text NOT NULL,
  CONSTRAINT jc_roles_pkey PRIMARY KEY (rolename)
);
ALTER TABLE jc_roles
  OWNER TO $JCADMIN;

CREATE TABLE jc_role_members
(
  rolename text NOT NULL,
  member_of text NOT NULL,
  CONSTRAINT jc_role_members_pkey PRIMARY KEY (rolename, member_of),
  CONSTRAINT jc_role_members_member_of_fkey FOREIGN KEY (member_of)
      REFERENCES jc_roles (rolename) MATCH SIMPLE
      ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT jc_role_members_rolename_fkey FOREIGN KEY (rolename)
      REFERENCES jc_roles (rolename) MATCH SIMPLE
      ON UPDATE CASCADE ON DELETE CASCADE
);

ALTER TABLE jc_role_members
  OWNER TO $JCADMIN;

CREATE TABLE jc_impersonate_roles
(
  rolename text NOT NULL,
  impersonates text NOT NULL,
  CONSTRAINT jc_impersonate_roles_pkey PRIMARY KEY (rolename, impersonates),
  CONSTRAINT jc_impersonate_roles_impersonates_fkey FOREIGN KEY (impersonates)
      REFERENCES jc_roles (rolename) MATCH SIMPLE
      ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT jc_impersonate_roles_rolename_fkey FOREIGN KEY (rolename)
      REFERENCES jc_roles (rolename) MATCH SIMPLE
      ON UPDATE CASCADE ON DELETE CASCADE
);
ALTER TABLE jc_impersonate_roles
  OWNER TO $JCADMIN;

GRANT SELECT ON TABLE jc_roles TO $JCSYSTEM;
GRANT SELECT ON TABLE jc_role_members TO $JCSYSTEM;
GRANT SELECT ON TABLE jc_impersonate_roles TO $JCSYSTEM;

alter table actions rename column role to rolename;

alter table actions add constraint action_rolename_fkey foreign key (rolename) references jc_roles(rolename) ON UPDATE CASCADE ON DELETE restrict;

alter table action_inputs drop CONSTRAINT action_inputs_type_fkey;

alter table action_inputs add CONSTRAINT action_inputs_type_fkey FOREIGN KEY (type)
	REFERENCES jsonb_object_fields (typename) MATCH SIMPLE
	ON UPDATE CASCADE ON DELETE restrict;

alter table action_outputs drop CONSTRAINT action_outputs_type_fkey;

alter table action_outputs add CONSTRAINT action_outputs_type_fkey FOREIGN KEY (type)
      REFERENCES jsonb_object_fields (typename) MATCH SIMPLE
      ON UPDATE CASCADE ON DELETE restrict;

insert into actions values (-13, 'lock', 'system', 0, null, null, null);
insert into actions values (-14, 'unlock', 'system', 0, null, null, null);

-- alter database jobcenter set default_transaction_isolation = serializable;
alter user $JCMAESTRO set default_transaction_isolation = 'repeatable read';

alter table locks alter contended drop default, alter contended type integer using 0, alter contended set default 0;

update tasks set casecode = jsonb_build_object('boolcode', casecode)::text where casecode is not null and action_id <> -5;
update tasks set casecode = jsonb_build_object('stringcode', casecode)::text where casecode is not null and action_id = -5;

alter table tasks alter casecode type jsonb using casecode::jsonb;

alter table tasks rename casecode to attributes;

update tasks set attributes = jsonb_build_object('imapcode', imapcode) where imapcode is not null and omapcode is null;

update tasks set attributes = jsonb_build_object('omapcode', omapcode) where imapcode is null and omapcode is not null;

update tasks set attributes = jsonb_build_object('imapcode', imapcode, 'omapcode', omapcode) where imapcode is not null and omapcode is not null;

update tasks set attributes = jsonb_build_object('evalcode', attributes->>'imapcode') where action_id=-3;

alter table tasks drop column imapcode;

alter table tasks drop column omapcode;

alter function do_branchcasecode(code text, args jsonb, env jsonb, vars jsonb) rename to do_boolcode;

update _procs set name = 'do_boolcode' where name = 'do_branchcasecode';

alter function do_switchcasecode(code text, args jsonb, env jsonb, vars jsonb) rename to do_stringcode;

update _procs set name = 'do_stringcode' where name = 'do_switchcasecode';

alter table locks add column inheritable boolean default false;

alter table jobs add column waitforlockinherit boolean;

alter function do_wfmap(code text, vars jsonb) rename to do_wfomap;

update _procs set name = 'do_wfomap' where name = 'do_wfmap';


