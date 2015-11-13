
CREATE TABLE _procs (
    name text NOT NULL,
    md5 text
);
ALTER TABLE _procs OWNER TO $JCADMIN;

CREATE TABLE _schema (
    version text
);
ALTER TABLE _schema OWNER TO $JCADMIN;

CREATE TABLE action_inputs (
    action_id integer NOT NULL,
    name text NOT NULL,
    type text NOT NULL,
    optional boolean NOT NULL,
    "default" jsonb,
    CONSTRAINT action_inputs_check CHECK ((((optional = false) AND ("default" IS NULL)) OR (("default" IS NOT NULL) AND (optional = true))))
);
ALTER TABLE action_inputs OWNER TO $JCADMIN;

CREATE TABLE action_outputs (
    action_id integer NOT NULL,
    name text NOT NULL,
    type text NOT NULL,
    optional boolean DEFAULT false NOT NULL
);
ALTER TABLE action_outputs OWNER TO $JCADMIN;

CREATE TABLE actions (
    action_id integer NOT NULL,
    name text NOT NULL,
    type action_type DEFAULT 'action'::action_type NOT NULL,
    version integer DEFAULT 0 NOT NULL,
    wfmapcode text,
    CONSTRAINT actions_wfmapcodecheck CHECK ((((type <> 'workflow'::action_type) AND (wfmapcode IS NULL)) OR (type = 'workflow'::action_type)))
);
ALTER TABLE actions OWNER TO $JCADMIN;

CREATE SEQUENCE actions_actionid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE actions_actionid_seq OWNER TO $JCADMIN;
ALTER SEQUENCE actions_actionid_seq OWNED BY actions.action_id;

CREATE TABLE event_subscriptions (
    subscription_id bigint NOT NULL,
    job_id bigint NOT NULL,
    mask jsonb NOT NULL,
    waiting boolean DEFAULT false NOT NULL,
    name text NOT NULL,
    CONSTRAINT check_job_is_wating CHECK (check_job_is_waiting(job_id, waiting))
);
ALTER TABLE event_subscriptions OWNER TO $JCADMIN;

CREATE SEQUENCE event_subscriptions_subscription_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE event_subscriptions_subscription_id_seq OWNER TO $JCADMIN;
ALTER SEQUENCE event_subscriptions_subscription_id_seq OWNED BY event_subscriptions.subscription_id;

CREATE TABLE job_events (
    subscription_id integer NOT NULL,
    event_id integer NOT NULL
);
ALTER TABLE job_events OWNER TO $JCADMIN;

CREATE TABLE job_task_log (
    job_task_log_id bigint NOT NULL,
    job_id bigint,
    task_id integer,
    variables jsonb,
    workflow_id integer,
    task_entered timestamp with time zone,
    task_started timestamp with time zone,
    task_completed timestamp with time zone,
    worker_id bigint,
    task_outargs jsonb,
    task_inargs jsonb
);
ALTER TABLE job_task_log OWNER TO $JCADMIN;
COMMENT ON COLUMN job_task_log.variables IS 'the new value of the variables on completion of the task
if the new value is different from the old value';

CREATE SEQUENCE job_task_log_job_task_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE job_task_log_job_task_log_id_seq OWNER TO $JCADMIN;
ALTER SEQUENCE job_task_log_job_task_log_id_seq OWNED BY job_task_log.job_task_log_id;

CREATE TABLE jobs (
    job_id bigint NOT NULL,
    workflow_id integer NOT NULL,
    task_id integer NOT NULL,
    parentjob_id bigint,
    state job_state,
    arguments jsonb,
    job_created timestamp with time zone DEFAULT now() NOT NULL,
    job_finished timestamp with time zone,
    worker_id bigint,
    variables jsonb,
    parenttask_id integer,
    waitfortask_id integer,
    cookie uuid,
    timeout timestamp with time zone,
    task_entered timestamp with time zone,
    task_started timestamp with time zone,
    task_completed timestamp with time zone,
    stepcounter integer DEFAULT 0 NOT NULL,
    out_args jsonb,
    waitforlocktype text,
    waitforlockvalue text,
    CONSTRAINT check_is_workflow CHECK (is_workflow(workflow_id))
);
ALTER TABLE jobs OWNER TO $JCADMIN;

CREATE SEQUENCE jobs_jobid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE jobs_jobid_seq OWNER TO $JCADMIN;
ALTER SEQUENCE jobs_jobid_seq OWNED BY jobs.job_id;

CREATE TABLE jsonb_object_fields (
    typename text NOT NULL,
    standard boolean DEFAULT false NOT NULL,
    fields text[],
    CONSTRAINT jsonb_object_fields_check CHECK ((((standard = true) AND (fields IS NULL)) OR ((standard = false) AND (fields IS NOT NULL))))
);
ALTER TABLE jsonb_object_fields OWNER TO $JCADMIN;

CREATE TABLE locks (
	job_id bigint NOT NULL,
	locktype text NOT NULL,
	lockvalue text NOT NULL,
	contended boolean DEFAULT false
);
ALTER TABLE locks OWNER TO $JCADMIN;

CREATE TABLE locktypes (
	locktype text NOT NULL
);
ALTER TABLE locktypes OWNER TO $JCADMIN;

CREATE TABLE next_tasks (
    from_task_id integer NOT NULL,
    to_task_id integer NOT NULL,
    "when" text NOT NULL,
    CONSTRAINT check_same_workflow CHECK (check_same_workflow(from_task_id, to_task_id))
);
ALTER TABLE next_tasks OWNER TO $JCADMIN;

CREATE TABLE queued_events (
    event_id bigint NOT NULL,
    "when" timestamp with time zone DEFAULT now() NOT NULL,
    eventdata jsonb NOT NULL
);
ALTER TABLE queued_events OWNER TO $JCADMIN;

CREATE SEQUENCE queued_events_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE queued_events_event_id_seq OWNER TO $JCADMIN;
ALTER SEQUENCE queued_events_event_id_seq OWNED BY queued_events.event_id;

CREATE TABLE tasks (
    task_id integer NOT NULL,
    workflow_id integer NOT NULL,
    action_id integer,
    on_error_task_id integer,
    casecode text,
    wait boolean DEFAULT true NOT NULL,
    reapfromtask_id integer,
    imapcode text,
    omapcode text,
    next_task_id integer,
    CONSTRAINT check_is_workflow CHECK (is_workflow(workflow_id)),
    CONSTRAINT check_wait CHECK (check_wait(action_id, wait))
);
ALTER TABLE tasks OWNER TO $JCADMIN;

CREATE SEQUENCE tasks_taskid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER SEQUENCE tasks_taskid_seq OWNER TO $JCADMIN;
ALTER SEQUENCE tasks_taskid_seq OWNED BY tasks.task_id;

CREATE TABLE worker_actions (
    worker_id bigint NOT NULL,
    action_id integer NOT NULL,
    CONSTRAINT check_is_action CHECK (is_action(action_id))
);
ALTER TABLE worker_actions OWNER TO $JCADMIN;

CREATE TABLE workers (
    worker_id bigint NOT NULL,
    name text,
    started timestamp with time zone DEFAULT now() NOT NULL,
    stopped timestamp with time zone,
    last_ping timestamp with time zone DEFAULT now() NOT NULL
);
ALTER TABLE workers OWNER TO $JCADMIN;

CREATE SEQUENCE workers_worker_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
ALTER TABLE workers_worker_id_seq OWNER TO $JCADMIN;
ALTER SEQUENCE workers_worker_id_seq OWNED BY workers.worker_id;

--
-- Defaults
--

ALTER TABLE ONLY actions ALTER COLUMN action_id SET DEFAULT nextval('actions_actionid_seq'::regclass);
ALTER TABLE ONLY event_subscriptions ALTER COLUMN subscription_id SET DEFAULT nextval('event_subscriptions_subscription_id_seq'::regclass);
ALTER TABLE ONLY job_task_log ALTER COLUMN job_task_log_id SET DEFAULT nextval('job_task_log_job_task_log_id_seq'::regclass);
ALTER TABLE ONLY jobs ALTER COLUMN job_id SET DEFAULT nextval('jobs_jobid_seq'::regclass);
ALTER TABLE ONLY queued_events ALTER COLUMN event_id SET DEFAULT nextval('queued_events_event_id_seq'::regclass);
ALTER TABLE ONLY tasks ALTER COLUMN task_id SET DEFAULT nextval('tasks_taskid_seq'::regclass);
ALTER TABLE ONLY workers ALTER COLUMN worker_id SET DEFAULT nextval('workers_worker_id_seq'::regclass);

--
-- Data for Name: action_inputs; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY action_inputs (action_id, name, type, optional, "default") FROM stdin;
-9	events	array	t	[]
-9	timeout	number	t	11.11
-8	name	string	f	\N
-7	name	string	f	\N
-7	mask	json	f	\N
-10	msg	string	f	\N
-11	event	json	f	\N
1	step	number	t	1
1	counter	number	f	\N
2	root	number	f	\N
3	dividend	number	f	\N
3	divisor	number	t	3.1415
\.

--
-- Data for Name: action_outputs; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY action_outputs (action_id, name, type, optional) FROM stdin;
-9	event	event	f
1	counter	number	f
2	square	number	f
2	quotient	number	f
\.

--
-- Data for Name: actions; Type: TABLE DATA; Schema: jobcenter; Owner: admin
--

COPY actions (action_id, name, type, version, wfmapcode) FROM stdin;
0	start	system	0	\N
-1	end	system	0	\N
-2	no_op	system	0	\N
-3	eval	system	0	\N
-4	branch	system	0	\N
-5	switch	system	0	\N
-6	reap_child	system	0	\N
-7	subscribe	system	0	\N
-8	unsubscribe	system	0	\N
-9	wait_for_event	system	0	\N
-10	raise_error	system	0	\N
-11	raise_event	system	0	\N
-12	wait_for_children	system	0	\N
1	add	action	0	\N
2	square	action	0	\N
3	div	action	0	\N
\.

--
-- Name: actions_actionid_seq; Type: SEQUENCE SET; Schema: jobcenter; Owner: $JCADMIN
--

SELECT pg_catalog.setval('actions_actionid_seq', 4, true);

--
-- Data for Name: jsonb_object_fields; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY jsonb_object_fields (typename, standard, fields) FROM stdin;
boolean	t	\N
number	t	\N
string	t	\N
array	t	\N
foobar	f	{foo,bar}
json	f	{}
event	f	{name,event_id,when,data}
\.

--
-- Constraints
--

ALTER TABLE ONLY _procs
    ADD CONSTRAINT _funcs_pkey PRIMARY KEY (name);

ALTER TABLE ONLY action_inputs
    ADD CONSTRAINT action_inputs_pkey PRIMARY KEY (action_id, name);

ALTER TABLE ONLY action_outputs
    ADD CONSTRAINT action_outputs_pkey PRIMARY KEY (action_id, name);

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (action_id);

ALTER TABLE ONLY actions
    ADD CONSTRAINT unique_type_name_version UNIQUE (type, name, version);

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_jobid_eventmask_ukey UNIQUE (job_id, mask);

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_jobid_name_ukey UNIQUE (job_id, name);

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_pkey PRIMARY KEY (subscription_id);

ALTER TABLE ONLY job_events
    ADD CONSTRAINT job_events_pkey PRIMARY KEY (subscription_id, event_id);

ALTER TABLE ONLY job_task_log
    ADD CONSTRAINT job_step_history_pkey PRIMARY KEY (job_task_log_id);

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_cookie_key UNIQUE (cookie);

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (job_id);

ALTER TABLE ONLY jsonb_object_fields
    ADD CONSTRAINT jsonb_object_fields_pkey PRIMARY KEY (typename);

ALTER TABLE locks
    ADD CONSTRAINT locks_pkey PRIMARY KEY (job_id, locktype, lockvalue);

ALTER TABLE locks
    ADD CONSTRAINT locks_ukey UNIQUE (locktype, lockvalue);

ALTER TABLE locktypes
    ADD CONSTRAINT locktypes_pkey PRIMARY KEY (locktype);

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_tasks_from_when_uniq UNIQUE (from_task_id, "when");

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_tasks_pkey PRIMARY KEY (from_task_id, to_task_id, "when");

ALTER TABLE ONLY queued_events
    ADD CONSTRAINT queued_events_pkey PRIMARY KEY (event_id);

ALTER TABLE ONLY tasks
    ADD CONSTRAINT steps_pkey PRIMARY KEY (task_id);

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_task_id_workflow_id_ukey UNIQUE (workflow_id, task_id);

ALTER TABLE ONLY worker_actions
    ADD CONSTRAINT worker_actions_pkey PRIMARY KEY (worker_id, action_id);

ALTER TABLE ONLY workers
    ADD CONSTRAINT workers_pkey PRIMARY KEY (worker_id);

ALTER TABLE ONLY workers
    ADD CONSTRAINT workers_workername_stopped_key UNIQUE (name, stopped);

--
-- Indexes
--

CREATE INDEX job_actionid_index ON jobs USING btree (task_id);
CREATE INDEX job_parent_jobid_index ON jobs USING btree (parentjob_id);
CREATE INDEX job_task_log_jobid_idx ON job_task_log USING btree (job_id);

--
-- Triggers
--

CREATE TRIGGER jobs_state_change AFTER UPDATE OF state ON jobs FOR EACH ROW WHEN (((old.state = 'waiting'::job_state) AND (new.state <> 'waiting'::job_state))) EXECUTE PROCEDURE clear_waiting_events();

CREATE TRIGGER jobs_task_change BEFORE UPDATE OF task_id ON jobs FOR EACH ROW EXECUTE PROCEDURE increase_stepcounter();

CREATE TRIGGER on_job_finished AFTER UPDATE ON jobs FOR EACH ROW WHEN ((new.job_finished IS NOT NULL)) EXECUTE PROCEDURE cleanup_on_finish();

CREATE TRIGGER timerchange AFTER INSERT OR DELETE OR UPDATE OF timeout ON jobs FOR EACH STATEMENT EXECUTE PROCEDURE notify_timerchange();


--
-- Foreign Key Constraints
--

ALTER TABLE ONLY action_inputs
    ADD CONSTRAINT action_inputs_actionid_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY action_inputs
    ADD CONSTRAINT action_inputs_type_fkey FOREIGN KEY (type) REFERENCES jsonb_object_fields(typename) ON UPDATE CASCADE;

ALTER TABLE ONLY action_outputs
    ADD CONSTRAINT action_outputs_actionid_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY action_outputs
    ADD CONSTRAINT action_outputs_type_fkey FOREIGN KEY (type) REFERENCES jsonb_object_fields(typename) ON UPDATE CASCADE;

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_job_id_fkey FOREIGN KEY (job_id) REFERENCES jobs(job_id);

ALTER TABLE ONLY job_events
    ADD CONSTRAINT job_events_eventid_fkey FOREIGN KEY (event_id) REFERENCES queued_events(event_id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY job_events
    ADD CONSTRAINT job_events_subscriptionid_fkey FOREIGN KEY (subscription_id) REFERENCES event_subscriptions(subscription_id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_parent_jobid_fkey FOREIGN KEY (parentjob_id) REFERENCES jobs(job_id);

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_taskid_fkey FOREIGN KEY (workflow_id, task_id) REFERENCES tasks(workflow_id, task_id) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_waitfortask_id_fkey FOREIGN KEY (waitfortask_id) REFERENCES tasks(task_id);

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_workflowid_fkey FOREIGN KEY (workflow_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE locks
    ADD CONSTRAINT locks_job_id_fkey FOREIGN KEY (job_id) REFERENCES jobs(job_id);

ALTER TABLE locks
    ADD CONSTRAINT locks_locktype_fkey FOREIGN KEY (locktype) REFERENCES locktypes(locktype);

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_task_from_task_id_fkey FOREIGN KEY (from_task_id) REFERENCES tasks(task_id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_task_to_task_id_fkey FOREIGN KEY (to_task_id) REFERENCES tasks(task_id) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE ONLY tasks
    ADD CONSTRAINT task_next_task_fkey FOREIGN KEY (next_task_id) REFERENCES tasks(task_id);

ALTER TABLE ONLY tasks
    ADD CONSTRAINT task_on_error_task_fkey FOREIGN KEY (on_error_task_id) REFERENCES tasks(task_id);

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_actionid_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_wait_for_fkey FOREIGN KEY (reapfromtask_id) REFERENCES tasks(task_id);

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_workflowid_fkey FOREIGN KEY (workflow_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE ONLY worker_actions
    ADD CONSTRAINT worker_actions_action_id_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id);

ALTER TABLE ONLY worker_actions
    ADD CONSTRAINT worker_actions_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES workers(worker_id) ON DELETE CASCADE;

--
-- More Grants
--

REVOKE ALL ON FUNCTION announce(a_workername text, a_actionname text) FROM PUBLIC;
GRANT ALL ON FUNCTION announce(a_workername text, a_actionname text) TO $JCSYSTEM;
GRANT ALL ON FUNCTION announce(a_workername text, a_actionname text) TO jc_client;

REVOKE ALL ON FUNCTION check_job_is_waiting(bigint, boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION check_job_is_waiting(bigint, boolean) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION check_same_workflow(a_task1_id integer, a_task2_id integer) FROM PUBLIC;
GRANT ALL ON FUNCTION check_same_workflow(a_task1_id integer, a_task2_id integer) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION check_wait(a_action_id integer, a_wait boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION check_wait(a_action_id integer, a_wait boolean) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION check_wait_for_task(a_action_id integer, a_wait_for_task integer) FROM PUBLIC;
GRANT ALL ON FUNCTION check_wait_for_task(a_action_id integer, a_wait_for_task integer) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION cleanup_on_finish() FROM PUBLIC;
GRANT ALL ON FUNCTION cleanup_on_finish() TO $JCSYSTEM;

REVOKE ALL ON FUNCTION clear_waiting_events() FROM PUBLIC;
GRANT ALL ON FUNCTION clear_waiting_events() TO $JCSYSTEM;

REVOKE ALL ON FUNCTION create_job(a_wfname text, a_args jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION create_job(a_wfname text, a_args jsonb) TO $JCSYSTEM;
GRANT ALL ON FUNCTION create_job(a_wfname text, a_args jsonb) TO jc_client;

REVOKE ALL ON FUNCTION do_branch_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_branch_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_branchcasecode(code text, args jsonb, vars jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION do_branchcasecode(code text, args jsonb, vars jsonb) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_check_workers() FROM PUBLIC;
GRANT ALL ON FUNCTION do_check_workers() TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_check_workers() TO $JCMAESTRO;

REVOKE ALL ON FUNCTION do_create_childjob(a_parentworkflow_id integer, a_parenttask_id integer, a_parentjob_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_create_childjob(a_parentworkflow_id integer, a_parenttask_id integer, a_parentjob_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_end_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_end_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_eval(code text, args jsonb, vars jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION do_eval(code text, args jsonb, vars jsonb) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_eval_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_eval_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_imap(code text, args jsonb, vars jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION do_imap(code text, args jsonb, vars jsonb) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_inargsmap(a_action_id integer, a_task_id integer, a_args jsonb, a_vars jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION do_inargsmap(a_action_id integer, a_task_id integer, a_args jsonb, a_vars jsonb) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_jobtask(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_jobtask(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_jobtask(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCMAESTRO;

REVOKE ALL ON FUNCTION do_jobtaskdone(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_jobtaskdone(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_jobtaskdone(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCMAESTRO;

REVOKE ALL ON FUNCTION do_jobtaskerror(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_jobtaskerror(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_jobtaskerror(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCMAESTRO;

REVOKE ALL ON FUNCTION do_omap(code text, vars jsonb, oargs jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION do_omap(code text, vars jsonb, oargs jsonb) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_outargsmap(a_action_id integer, a_task_id integer, a_oldvars jsonb, a_outargs jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION do_outargsmap(a_action_id integer, a_task_id integer, a_oldvars jsonb, a_outargs jsonb) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_ping(a_worker_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_ping(a_worker_id bigint) TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_ping(a_worker_id bigint) TO $JCMAESTRO;

REVOKE ALL ON FUNCTION do_prepare_for_action(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_prepare_for_action(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_raise_error(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_errmsg text) FROM PUBLIC;
GRANT ALL ON FUNCTION do_raise_error(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_errmsg text) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_raise_error_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_raise_error_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_raise_event_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_raise_event_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_raise_fatal_error(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_errmsg text) FROM PUBLIC;
GRANT ALL ON FUNCTION do_raise_fatal_error(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_errmsg text) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_reap_child_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_reap_child_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_subscribe_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_subscribe_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_switch_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_switch_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_switchcasecode(code text, args jsonb, vars jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION do_switchcasecode(code text, args jsonb, vars jsonb) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_task_done(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_outargs jsonb, a_notify boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION do_task_done(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_outargs jsonb, a_notify boolean) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_task_error(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_errargs jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION do_task_error(a_workflow_id integer, a_task_id integer, a_job_id bigint, a_errargs jsonb) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_timeout() FROM PUBLIC;
GRANT ALL ON FUNCTION do_timeout() TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_timeout() TO $JCMAESTRO;

REVOKE ALL ON FUNCTION do_unsubscribe_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_unsubscribe_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_wait_for_children_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_wait_for_children_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_wait_for_event_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_wait_for_event_task(a_workflow_id integer, a_task_id integer, a_job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_wfmap(code text, vars jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION do_wfmap(code text, vars jsonb) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION do_workflowoutargsmap(a_workflow_id integer, a_vars jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION do_workflowoutargsmap(a_workflow_id integer, a_vars jsonb) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION get_job_status(a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION get_job_status(a_job_id bigint) TO $JCSYSTEM;
GRANT ALL ON FUNCTION get_job_status(a_job_id bigint) TO jc_client;

REVOKE ALL ON FUNCTION get_task(a_workername text, a_actionname text, a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION get_task(a_workername text, a_actionname text, a_job_id bigint) TO $JCSYSTEM;
GRANT ALL ON FUNCTION get_task(a_workername text, a_actionname text, a_job_id bigint) TO jc_client;

REVOKE ALL ON FUNCTION increase_stepcounter() FROM PUBLIC;
GRANT ALL ON FUNCTION increase_stepcounter() TO $JCSYSTEM;

REVOKE ALL ON FUNCTION is_action(integer) FROM PUBLIC;
GRANT ALL ON FUNCTION is_action(integer) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION is_workflow(integer) FROM PUBLIC;
GRANT ALL ON FUNCTION is_workflow(integer) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION nexttask(error boolean, workflow_id integer, task_id integer, job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION nexttask(error boolean, workflow_id integer, task_id integer, job_id bigint) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION notify_timerchange() FROM PUBLIC;
GRANT ALL ON FUNCTION notify_timerchange() TO $JCSYSTEM;

REVOKE ALL ON FUNCTION ping(a_worker_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION ping(a_worker_id bigint) TO $JCSYSTEM;
GRANT ALL ON FUNCTION ping(a_worker_id bigint) TO jc_client;

REVOKE ALL ON FUNCTION raise_event(a_eventdata jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION raise_event(a_eventdata jsonb) TO $JCSYSTEM;
GRANT ALL ON FUNCTION raise_event(a_eventdata jsonb) TO jc_client;

REVOKE ALL ON FUNCTION sanity_check_workflow(a_workflow_id integer) FROM PUBLIC;
GRANT ALL ON FUNCTION sanity_check_workflow(a_workflow_id integer) TO $JCSYSTEM;

REVOKE ALL ON FUNCTION task_done(a_jobcookie text, a_out_args jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION task_done(a_jobcookie text, a_out_args jsonb) TO $JCSYSTEM;
GRANT ALL ON FUNCTION task_done(a_jobcookie text, a_out_args jsonb) TO jc_client;

REVOKE ALL ON FUNCTION task_failed(a_cookie text, a_errmsg text) FROM PUBLIC;
GRANT ALL ON FUNCTION task_failed(a_cookie text, a_errmsg text) TO $JCSYSTEM;
GRANT ALL ON FUNCTION task_failed(a_cookie text, a_errmsg text) TO jc_client;

REVOKE ALL ON TABLE _procs FROM PUBLIC;
GRANT ALL ON TABLE _procs TO $JCADMIN;

REVOKE ALL ON TABLE action_inputs FROM PUBLIC;
GRANT ALL ON TABLE action_inputs TO $JCADMIN;
GRANT SELECT ON TABLE action_inputs TO $JCSYSTEM;

REVOKE ALL ON TABLE action_outputs FROM PUBLIC;
GRANT ALl ON TABLE action_outputs TO $JCADMIN;
GRANT SELECT ON TABLE action_outputs TO $JCSYSTEM;

REVOKE ALL ON TABLE actions FROM PUBLIC;
GRANT ALL ON TABLE actions TO $JCADMIN;
GRANT SELECT ON TABLE actions TO $JCSYSTEM;

REVOKE ALL ON SEQUENCE actions_actionid_seq FROM PUBLIC;
GRANT ALL ON SEQUENCE actions_actionid_seq TO $JCADMIN;

REVOKE ALL ON TABLE event_subscriptions FROM PUBLIC;
GRANT ALL ON TABLE event_subscriptions TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE event_subscriptions TO $JCSYSTEM;

REVOKE ALL ON SEQUENCE event_subscriptions_subscription_id_seq FROM PUBLIC;
GRANT ALL ON SEQUENCE event_subscriptions_subscription_id_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE event_subscriptions_subscription_id_seq TO $JCSYSTEM;

REVOKE ALL ON TABLE job_events FROM PUBLIC;
GRANT ALL ON TABLE job_events TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE job_events TO $JCSYSTEM;

REVOKE ALL ON TABLE job_task_log FROM PUBLIC;
GRANT ALL ON TABLE job_task_log TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE job_task_log TO $JCSYSTEM;

REVOKE ALL ON SEQUENCE job_task_log_job_task_log_id_seq FROM PUBLIC;
GRANT ALL ON SEQUENCE job_task_log_job_task_log_id_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE job_task_log_job_task_log_id_seq TO $JCSYSTEM;

REVOKE ALL ON TABLE jobs FROM PUBLIC;
GRANT ALL ON TABLE jobs TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE jobs TO $JCSYSTEM;

REVOKE ALL ON SEQUENCE jobs_jobid_seq FROM PUBLIC;
GRANT ALL ON SEQUENCE jobs_jobid_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE jobs_jobid_seq TO $JCSYSTEM;

REVOKE ALL ON TABLE jsonb_object_fields FROM PUBLIC;
GRANT ALL ON TABLE jsonb_object_fields TO $JCADMIN;
GRANT SELECT ON TABLE jsonb_object_fields TO $JCSYSTEM;

REVOKE ALL ON TABLE locks FROM PUBLIC;
GRANT ALL ON TABLE locks TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE locks TO $JCSYSTEM;

REVOKE ALL ON TABLE locktypes FROM PUBLIC;
GRANT ALL ON TABLE locktypes TO $JCADMIN;
GRANT SELECT ON TABLE locktypes TO $JCSYSTEM;

REVOKE ALL ON TABLE next_tasks FROM PUBLIC;
GRANT ALL ON TABLE next_tasks TO $JCADMIN;
GRANT SELECT ON TABLE next_tasks TO $JCSYSTEM;

REVOKE ALL ON TABLE queued_events FROM PUBLIC;
GRANT ALL ON TABLE queued_events TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE queued_events TO $JCSYSTEM;

REVOKE ALL ON SEQUENCE queued_events_event_id_seq FROM PUBLIC;
GRANT ALL ON SEQUENCE queued_events_event_id_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE queued_events_event_id_seq TO $JCSYSTEM;

REVOKE ALL ON TABLE tasks FROM PUBLIC;
GRANT ALL ON TABLE tasks TO $JCSYSTEM;
GRANT SELECT ON TABLE tasks TO $JCSYSTEM;

REVOKE ALL ON SEQUENCE tasks_taskid_seq FROM PUBLIC;
GRANT ALL ON SEQUENCE tasks_taskid_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE tasks_taskid_seq TO $JCSYSTEM;

REVOKE ALL ON TABLE worker_actions FROM PUBLIC;
GRANT ALL ON TABLE worker_actions TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE worker_actions TO $JCSYSTEM;

REVOKE ALL ON TABLE workers FROM PUBLIC;
GRANT ALL ON TABLE workers TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE workers TO $JCSYSTEM;

REVOKE ALL ON SEQUENCE workers_worker_id_seq FROM PUBLIC;
GRANT ALL ON SEQUENCE workers_worker_id_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE workers_worker_id_seq TO $JCSYSTEM;

INSERT INTO _procs
	SELECT
		p.proname AS "name",
		md5(pg_catalog.pg_get_functiondef(p.oid)) AS "md5"
	FROM
		pg_catalog.pg_proc p
		JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
	 WHERE
	 	pg_catalog.pg_function_is_visible(p.oid)
	 	AND n.nspname = 'jobcenter';

INSERT INTO _schema values ('1');
