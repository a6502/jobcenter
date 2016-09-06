--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.4
-- Dumped by pg_dump version 9.5.4

-- Started on 2016-09-05 14:48:03 CEST

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

SET search_path = jobcenter, pg_catalog;

ALTER TABLE IF EXISTS ONLY jobcenter.worker_actions DROP CONSTRAINT IF EXISTS worker_actions_worker_id_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.worker_actions DROP CONSTRAINT IF EXISTS worker_actions_action_id_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.tasks DROP CONSTRAINT IF EXISTS tasks_workflowid_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.tasks DROP CONSTRAINT IF EXISTS tasks_wait_for_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.tasks DROP CONSTRAINT IF EXISTS tasks_actionid_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.tasks DROP CONSTRAINT IF EXISTS task_on_error_task_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.tasks DROP CONSTRAINT IF EXISTS task_next_task_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.next_tasks DROP CONSTRAINT IF EXISTS next_task_to_task_id_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.next_tasks DROP CONSTRAINT IF EXISTS next_task_from_task_id_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.locks DROP CONSTRAINT IF EXISTS locks_locktype_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.locks DROP CONSTRAINT IF EXISTS locks_job_id_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jobs DROP CONSTRAINT IF EXISTS jobs_workflowid_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jobs DROP CONSTRAINT IF EXISTS jobs_taskid_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jobs DROP CONSTRAINT IF EXISTS jobs_parent_jobid_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jobs_archive DROP CONSTRAINT IF EXISTS job_history_workflowid_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.job_events DROP CONSTRAINT IF EXISTS job_events_subscriptionid_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.job_events DROP CONSTRAINT IF EXISTS job_events_eventid_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jc_role_members DROP CONSTRAINT IF EXISTS jc_role_members_rolename_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jc_role_members DROP CONSTRAINT IF EXISTS jc_role_members_member_of_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jc_impersonate_roles DROP CONSTRAINT IF EXISTS jc_impersonate_roles_rolename_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jc_impersonate_roles DROP CONSTRAINT IF EXISTS jc_impersonate_roles_impersonates_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.event_subscriptions DROP CONSTRAINT IF EXISTS event_subscriptions_job_id_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.action_version_tags DROP CONSTRAINT IF EXISTS action_version_tags_tag_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.action_version_tags DROP CONSTRAINT IF EXISTS action_version_tags_action_id_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.actions DROP CONSTRAINT IF EXISTS action_rolename_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.action_outputs DROP CONSTRAINT IF EXISTS action_outputs_type_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.action_outputs DROP CONSTRAINT IF EXISTS action_outputs_actionid_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.action_inputs DROP CONSTRAINT IF EXISTS action_inputs_type_fkey;
ALTER TABLE IF EXISTS ONLY jobcenter.action_inputs DROP CONSTRAINT IF EXISTS action_inputs_actionid_fkey;
DROP TRIGGER IF EXISTS on_jobs_timerchange ON jobcenter.jobs;
DROP TRIGGER IF EXISTS on_job_task_change ON jobcenter.jobs;
DROP TRIGGER IF EXISTS on_job_state_change ON jobcenter.jobs;
DROP INDEX IF EXISTS jobcenter.job_task_log_jobid_idx;
DROP INDEX IF EXISTS jobcenter.job_parent_jobid_index;
DROP INDEX IF EXISTS jobcenter.job_actionid_index;
DROP INDEX IF EXISTS jobcenter.jcenv_uidx;
ALTER TABLE IF EXISTS ONLY jobcenter.workers DROP CONSTRAINT IF EXISTS workers_workername_stopped_key;
ALTER TABLE IF EXISTS ONLY jobcenter.workers DROP CONSTRAINT IF EXISTS workers_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.worker_actions DROP CONSTRAINT IF EXISTS worker_actions_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.version_tags DROP CONSTRAINT IF EXISTS version_tag_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.actions DROP CONSTRAINT IF EXISTS unique_type_name_version;
ALTER TABLE IF EXISTS ONLY jobcenter.tasks DROP CONSTRAINT IF EXISTS tasks_task_id_workflow_id_ukey;
ALTER TABLE IF EXISTS ONLY jobcenter.tasks DROP CONSTRAINT IF EXISTS steps_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.queued_events DROP CONSTRAINT IF EXISTS queued_events_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.next_tasks DROP CONSTRAINT IF EXISTS next_tasks_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.next_tasks DROP CONSTRAINT IF EXISTS next_tasks_from_when_uniq;
ALTER TABLE IF EXISTS ONLY jobcenter.locktypes DROP CONSTRAINT IF EXISTS locktypes_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.locks DROP CONSTRAINT IF EXISTS locks_ukey;
ALTER TABLE IF EXISTS ONLY jobcenter.locks DROP CONSTRAINT IF EXISTS locks_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jsonb_object_fields DROP CONSTRAINT IF EXISTS jsonb_object_fields_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jobs DROP CONSTRAINT IF EXISTS jobs_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jobs DROP CONSTRAINT IF EXISTS jobs_cookie_key;
ALTER TABLE IF EXISTS ONLY jobcenter.job_task_log DROP CONSTRAINT IF EXISTS job_step_history_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jobs_archive DROP CONSTRAINT IF EXISTS job_history_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.job_events DROP CONSTRAINT IF EXISTS job_events_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jc_roles DROP CONSTRAINT IF EXISTS jc_roles_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jc_role_members DROP CONSTRAINT IF EXISTS jc_role_members_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.jc_impersonate_roles DROP CONSTRAINT IF EXISTS jc_impersonate_roles_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.event_subscriptions DROP CONSTRAINT IF EXISTS event_subscriptions_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.event_subscriptions DROP CONSTRAINT IF EXISTS event_subscriptions_jobid_name_ukey;
ALTER TABLE IF EXISTS ONLY jobcenter.event_subscriptions DROP CONSTRAINT IF EXISTS event_subscriptions_jobid_eventmask_ukey;
ALTER TABLE IF EXISTS ONLY jobcenter.actions DROP CONSTRAINT IF EXISTS actions_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.action_version_tags DROP CONSTRAINT IF EXISTS action_version_tags_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.action_outputs DROP CONSTRAINT IF EXISTS action_outputs_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter.action_inputs DROP CONSTRAINT IF EXISTS action_inputs_pkey;
ALTER TABLE IF EXISTS ONLY jobcenter._procs DROP CONSTRAINT IF EXISTS _funcs_pkey;
ALTER TABLE IF EXISTS jobcenter.workers ALTER COLUMN worker_id DROP DEFAULT;
ALTER TABLE IF EXISTS jobcenter.tasks ALTER COLUMN task_id DROP DEFAULT;
ALTER TABLE IF EXISTS jobcenter.queued_events ALTER COLUMN event_id DROP DEFAULT;
ALTER TABLE IF EXISTS jobcenter.jobs ALTER COLUMN job_id DROP DEFAULT;
ALTER TABLE IF EXISTS jobcenter.job_task_log ALTER COLUMN job_task_log_id DROP DEFAULT;
ALTER TABLE IF EXISTS jobcenter.event_subscriptions ALTER COLUMN subscription_id DROP DEFAULT;
ALTER TABLE IF EXISTS jobcenter.actions ALTER COLUMN action_id DROP DEFAULT;
DROP SEQUENCE IF EXISTS jobcenter.workers_worker_id_seq;
DROP TABLE IF EXISTS jobcenter.workers;
DROP TABLE IF EXISTS jobcenter.worker_actions;
DROP TABLE IF EXISTS jobcenter.version_tags;
DROP SEQUENCE IF EXISTS jobcenter.tasks_taskid_seq;
DROP TABLE IF EXISTS jobcenter.tasks;
DROP SEQUENCE IF EXISTS jobcenter.queued_events_event_id_seq;
DROP TABLE IF EXISTS jobcenter.queued_events;
DROP TABLE IF EXISTS jobcenter.next_tasks;
DROP TABLE IF EXISTS jobcenter.locktypes;
DROP TABLE IF EXISTS jobcenter.locks;
DROP TABLE IF EXISTS jobcenter.jsonb_object_fields;
DROP SEQUENCE IF EXISTS jobcenter.jobs_jobid_seq;
DROP TABLE IF EXISTS jobcenter.jobs_archive;
DROP TABLE IF EXISTS jobcenter.jobs;
DROP SEQUENCE IF EXISTS jobcenter.job_task_log_job_task_log_id_seq;
DROP TABLE IF EXISTS jobcenter.job_task_log;
DROP TABLE IF EXISTS jobcenter.job_events;
DROP TABLE IF EXISTS jobcenter.jc_roles;
DROP TABLE IF EXISTS jobcenter.jc_role_members;
DROP TABLE IF EXISTS jobcenter.jc_impersonate_roles;
DROP TABLE IF EXISTS jobcenter.jc_env;
DROP SEQUENCE IF EXISTS jobcenter.event_subscriptions_subscription_id_seq;
DROP TABLE IF EXISTS jobcenter.event_subscriptions;
DROP SEQUENCE IF EXISTS jobcenter.actions_actionid_seq;
DROP TABLE IF EXISTS jobcenter.actions;
DROP TABLE IF EXISTS jobcenter.action_version_tags;
DROP TABLE IF EXISTS jobcenter.action_outputs;
DROP TABLE IF EXISTS jobcenter.action_inputs;
DROP TABLE IF EXISTS jobcenter._schema;
DROP TABLE IF EXISTS jobcenter._procs;
DROP FUNCTION IF EXISTS jobcenter.withdraw(a_workername text, a_actionname text);
DROP FUNCTION IF EXISTS jobcenter.task_failed(a_cookie text, a_errmsg text);
DROP FUNCTION IF EXISTS jobcenter.task_done(a_jobcookie text, a_out_args jsonb);
DROP FUNCTION IF EXISTS jobcenter.raise_event(a_eventdata jsonb);
DROP FUNCTION IF EXISTS jobcenter.ping(a_worker_id bigint);
DROP FUNCTION IF EXISTS jobcenter.get_task(a_workername text, a_actionname text, a_job_id bigint, a_pattern jsonb);
DROP FUNCTION IF EXISTS jobcenter.get_job_status(a_job_id bigint);
DROP FUNCTION IF EXISTS jobcenter.do_workflowoutargsmap(a_workflow_id integer, a_args jsonb, a_env jsonb, a_vars jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_wfomap(code text, args jsonb, env jsonb, vars jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_wait_for_event_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_wait_for_children_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_unsubscribe_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_unlock_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_unlock(a_locktype text, a_lockvalue text, a_contended integer, a_job_id bigint, a_parentjob_id bigint, a_top_level_job_id bigint);
DROP FUNCTION IF EXISTS jobcenter.do_timeout();
DROP FUNCTION IF EXISTS jobcenter.do_task_error(a_jobtask jobtask, a_errargs jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_task_epilogue(a_jobtask jobtask, a_vars_changed boolean, a_newvars jsonb, a_inargs jsonb, a_outargs jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_task_done(a_jobtask jobtask, a_outargs jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_switch_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_subscribe_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_stringcode(code text, args jsonb, env jsonb, vars jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_sanity_check_workflow(a_workflow_id integer);
DROP FUNCTION IF EXISTS jobcenter.do_reap_child_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_raise_event_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_raise_error_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_raise_error(a_jobtask jobtask, a_errmsg text, a_class text);
DROP FUNCTION IF EXISTS jobcenter.do_prepare_for_action(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_ping(a_worker_id bigint);
DROP FUNCTION IF EXISTS jobcenter.do_outargsmap(a_jobtask jobtask, a_outargs jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_omap(code text, args jsonb, env jsonb, vars jsonb, oargs jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_notify_timerchange();
DROP FUNCTION IF EXISTS jobcenter.do_log(a_job_id bigint, a_logvars boolean, a_inargs jsonb, a_outargs jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_lock_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_jobtaskerror(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_jobtaskdone(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_jobtask(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_is_workflow(integer);
DROP FUNCTION IF EXISTS jobcenter.do_is_action(integer);
DROP FUNCTION IF EXISTS jobcenter.do_increase_stepcounter();
DROP FUNCTION IF EXISTS jobcenter.do_inargsmap(a_action_id integer, a_task_id integer, a_args jsonb, a_env jsonb, a_vars jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_imap(code text, args jsonb, env jsonb, vars jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_eval_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_eval(code text, args jsonb, env jsonb, vars jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_end_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_create_childjob(a_parentjobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_clear_waiting_events();
DROP FUNCTION IF EXISTS jobcenter.do_cleanup_on_finish_trigger();
DROP FUNCTION IF EXISTS jobcenter.do_cleanup_on_finish(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_check_wait_for_task(a_action_id integer, a_wait_for_task integer);
DROP FUNCTION IF EXISTS jobcenter.do_check_wait(a_action_id integer, a_wait boolean);
DROP FUNCTION IF EXISTS jobcenter.do_check_same_workflow(a_task1_id integer, a_task2_id integer);
DROP FUNCTION IF EXISTS jobcenter.do_check_role_membership(a_have_role text, a_should_role text);
DROP FUNCTION IF EXISTS jobcenter.do_check_job_is_waiting(bigint, boolean);
DROP FUNCTION IF EXISTS jobcenter.do_call_stored_procedure(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_branch_task(a_jobtask jobtask);
DROP FUNCTION IF EXISTS jobcenter.do_boolcode(code text, args jsonb, env jsonb, vars jsonb);
DROP FUNCTION IF EXISTS jobcenter.do_archival_and_cleanup(dummy text);
DROP FUNCTION IF EXISTS jobcenter.create_job(wfname text, args jsonb, tag text, impersonate text);
DROP FUNCTION IF EXISTS jobcenter.announce(workername text, actionname text, impersonate text);
DROP TYPE IF EXISTS jobcenter.nextjobtask;
DROP TYPE IF EXISTS jobcenter.jobtask;
DROP TYPE IF EXISTS jobcenter.job_state;
DROP TYPE IF EXISTS jobcenter.action_type;
DROP SCHEMA IF EXISTS jobcenter;
--
-- TOC entry 8 (class 2615 OID 36103)
-- Name: jobcenter; Type: SCHEMA; Schema: -; Owner: $JCADMIN
--

CREATE SCHEMA jobcenter;


ALTER SCHEMA jobcenter OWNER TO $JCADMIN;
REVOKE ALL ON SCHEMA jobcenter FROM PUBLIC;
GRANT ALL ON SCHEMA jobcenter TO $JCADMIN;
GRANT USAGE ON SCHEMA jobcenter TO $JCCLIENT;
GRANT USAGE ON SCHEMA jobcenter TO $JCMAESTRO;
GRANT ALL ON SCHEMA jobcenter TO $JCSYSTEM;
GRANT ALL ON SCHEMA jobcenter TO $JCPERL;


SET search_path = jobcenter, pg_catalog;

--
-- TOC entry 646 (class 1247 OID 36105)
-- Name: action_type; Type: TYPE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TYPE action_type AS ENUM (
    'system',
    'action',
    'procedure',
    'workflow'
);


ALTER TYPE action_type OWNER TO $JCADMIN;

--
-- TOC entry 649 (class 1247 OID 36112)
-- Name: job_state; Type: TYPE; Schema: jobcenter; Owner: $JCADMIN
--

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

--
-- TOC entry 2476 (class 0 OID 0)
-- Dependencies: 649
-- Name: TYPE job_state; Type: COMMENT; Schema: jobcenter; Owner: $JCADMIN
--

COMMENT ON TYPE job_state IS 'ready: waiting for a worker to pick this jobtask
working: waiting for a worker to finish this jobtask
waiting: waiting for some external event or timeout
blocked: waiting for a subjob to finish
done: waiting for the maestro to start plotting
plotting: waiting for the maestro to decide
zombie: waiting for a parent job to wait for us
finished: done waiting
error: ?';


--
-- TOC entry 732 (class 1247 OID 36544)
-- Name: jobtask; Type: TYPE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TYPE jobtask AS (
	workflow_id integer,
	task_id integer,
	job_id bigint
);


ALTER TYPE jobtask OWNER TO $JCADMIN;

--
-- TOC entry 735 (class 1247 OID 36547)
-- Name: nextjobtask; Type: TYPE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TYPE nextjobtask AS (
	error boolean,
	jobtask jobtask
);


ALTER TYPE nextjobtask OWNER TO $JCADMIN;

