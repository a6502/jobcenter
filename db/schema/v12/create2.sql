
--
-- Name: _procs; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE _procs (
    name text NOT NULL,
    md5 text
);


ALTER TABLE _procs OWNER TO $JCADMIN;

--
-- Name: _schema; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE _schema (
    version text
);


ALTER TABLE _schema OWNER TO $JCADMIN;

--
-- Name: action_inputs; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE action_inputs (
    action_id integer NOT NULL,
    name text NOT NULL,
    type text NOT NULL,
    optional boolean NOT NULL,
    "default" jsonb,
    CONSTRAINT action_inputs_check CHECK ((((optional = false) AND ("default" IS NULL)) OR (("default" IS NOT NULL) AND (optional = true))))
);


ALTER TABLE action_inputs OWNER TO $JCADMIN;

--
-- Name: action_outputs; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE action_outputs (
    action_id integer NOT NULL,
    name text NOT NULL,
    type text NOT NULL,
    optional boolean DEFAULT false NOT NULL
);


ALTER TABLE action_outputs OWNER TO $JCADMIN;

--
-- Name: action_version_tags; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE action_version_tags (
    action_id integer NOT NULL,
    tag text NOT NULL
);


ALTER TABLE action_version_tags OWNER TO $JCADMIN;

--
-- Name: actions; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE actions (
    action_id integer NOT NULL,
    name text NOT NULL,
    type action_type DEFAULT 'action'::action_type NOT NULL,
    version integer DEFAULT 0 NOT NULL,
    wfenv jsonb,
    rolename name,
    config jsonb,
    CONSTRAINT actions_wfenvcheck CHECK ((((type <> 'workflow'::action_type) AND (wfenv IS NULL)) OR (type = 'workflow'::action_type)))
);


ALTER TABLE actions OWNER TO $JCADMIN;

--
-- Name: actions_actionid_seq; Type: SEQUENCE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE SEQUENCE actions_actionid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE actions_actionid_seq OWNER TO $JCADMIN;

--
-- Name: actions_actionid_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE actions_actionid_seq OWNED BY actions.action_id;


--
-- Name: event_subscriptions; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE event_subscriptions (
    subscription_id bigint NOT NULL,
    job_id bigint NOT NULL,
    mask jsonb NOT NULL,
    waiting boolean DEFAULT false NOT NULL,
    name text NOT NULL,
    CONSTRAINT check_job_is_wating CHECK (do_check_job_is_waiting(job_id, waiting))
);


ALTER TABLE event_subscriptions OWNER TO $JCADMIN;

--
-- Name: event_subscriptions_subscription_id_seq; Type: SEQUENCE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE SEQUENCE event_subscriptions_subscription_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE event_subscriptions_subscription_id_seq OWNER TO $JCADMIN;

--
-- Name: event_subscriptions_subscription_id_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE event_subscriptions_subscription_id_seq OWNED BY event_subscriptions.subscription_id;


--
-- Name: jc_env; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jc_env (
    jcenv jsonb
);


ALTER TABLE jc_env OWNER TO $JCADMIN;

--
-- Name: jc_impersonate_roles; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jc_impersonate_roles (
    rolename text NOT NULL,
    impersonates text NOT NULL
);


ALTER TABLE jc_impersonate_roles OWNER TO $JCADMIN;

--
-- Name: jc_role_members; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jc_role_members (
    rolename text NOT NULL,
    member_of text NOT NULL
);


ALTER TABLE jc_role_members OWNER TO $JCADMIN;

--
-- Name: jc_roles; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jc_roles (
    rolename text NOT NULL
);


ALTER TABLE jc_roles OWNER TO $JCADMIN;

--
-- Name: job_events; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE job_events (
    subscription_id integer NOT NULL,
    event_id integer NOT NULL
);


ALTER TABLE job_events OWNER TO $JCADMIN;

--
-- Name: job_task_log; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE job_task_log (
    job_task_log_id bigint NOT NULL,
    job_id bigint,
    task_id integer,
    variables jsonb,
    workflow_id integer,
    task_entered timestamp with time zone,
    task_started timestamp with time zone,
    task_completed timestamp with time zone,
    task_outargs jsonb,
    task_inargs jsonb,
    task_state jsonb
);


ALTER TABLE job_task_log OWNER TO $JCADMIN;

--
-- Name: COLUMN job_task_log.variables; Type: COMMENT; Schema: jobcenter; Owner: $JCADMIN
--

COMMENT ON COLUMN job_task_log.variables IS 'the new value of the variables on completion of the task
if the new value is different from the old value';


--
-- Name: job_task_log_job_task_log_id_seq; Type: SEQUENCE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE SEQUENCE job_task_log_job_task_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE job_task_log_job_task_log_id_seq OWNER TO $JCADMIN;

--
-- Name: job_task_log_job_task_log_id_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE job_task_log_job_task_log_id_seq OWNED BY job_task_log.job_task_log_id;


--
-- Name: jobs; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jobs (
    job_id bigint NOT NULL,
    workflow_id integer NOT NULL,
    task_id integer NOT NULL,
    parentjob_id bigint,
    state job_state,
    arguments jsonb,
    job_created timestamp with time zone DEFAULT now() NOT NULL,
    job_finished timestamp with time zone,
    variables jsonb,
    cookie uuid,
    timeout timestamp with time zone,
    task_entered timestamp with time zone,
    task_started timestamp with time zone,
    task_completed timestamp with time zone,
    stepcounter integer DEFAULT 0 NOT NULL,
    out_args jsonb,
    environment jsonb,
    max_steps integer DEFAULT 100 NOT NULL,
    aborted boolean DEFAULT false NOT NULL,
    current_depth integer DEFAULT 1 NOT NULL,
    task_state jsonb,
    job_state jsonb,
    CONSTRAINT check_is_workflow CHECK (do_is_workflow(workflow_id))
);


ALTER TABLE jobs OWNER TO $JCADMIN;

--
-- Name: jobs_archive; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jobs_archive (
    job_id bigint NOT NULL,
    workflow_id integer NOT NULL,
    parentjob_id bigint,
    state job_state,
    arguments jsonb,
    job_created timestamp with time zone NOT NULL,
    job_finished timestamp with time zone NOT NULL,
    stepcounter integer DEFAULT 0 NOT NULL,
    out_args jsonb,
    environment jsonb,
    max_steps integer DEFAULT 100 NOT NULL,
    current_depth integer
);


ALTER TABLE jobs_archive OWNER TO $JCADMIN;

--
-- Name: jobs_jobid_seq; Type: SEQUENCE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE SEQUENCE jobs_jobid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE jobs_jobid_seq OWNER TO $JCADMIN;

--
-- Name: jobs_jobid_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE jobs_jobid_seq OWNED BY jobs.job_id;


--
-- Name: json_schemas; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE json_schemas (
    type text NOT NULL,
    base boolean DEFAULT false NOT NULL,
    schema jsonb,
    CONSTRAINT json_schema_check CHECK ((((base = true) AND (schema IS NULL)) OR ((base = false) AND (schema IS NOT NULL))))
);


ALTER TABLE json_schemas OWNER TO $JCADMIN;

--
-- Name: locks; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE locks (
    job_id bigint NOT NULL,
    locktype text NOT NULL,
    lockvalue text NOT NULL,
    contended integer DEFAULT 0 NOT NULL,
    inheritable boolean DEFAULT false NOT NULL,
    top_level_job_id bigint
);


ALTER TABLE locks OWNER TO $JCADMIN;

--
-- Name: locktypes; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE locktypes (
    locktype text NOT NULL
);


ALTER TABLE locktypes OWNER TO $JCADMIN;

--
-- Name: next_tasks; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE next_tasks (
    from_task_id integer NOT NULL,
    to_task_id integer NOT NULL,
    "when" text NOT NULL
);


ALTER TABLE next_tasks OWNER TO $JCADMIN;

--
-- Name: queued_events; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE queued_events (
    event_id bigint NOT NULL,
    "when" timestamp with time zone DEFAULT now() NOT NULL,
    eventdata jsonb NOT NULL
);


ALTER TABLE queued_events OWNER TO $JCADMIN;

--
-- Name: queued_events_event_id_seq; Type: SEQUENCE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE SEQUENCE queued_events_event_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE queued_events_event_id_seq OWNER TO $JCADMIN;

--
-- Name: queued_events_event_id_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE queued_events_event_id_seq OWNED BY queued_events.event_id;


--
-- Name: tasks; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE tasks (
    task_id integer NOT NULL,
    workflow_id integer NOT NULL,
    action_id integer,
    on_error_task_id integer,
    attributes jsonb,
    next_task_id integer,
    CONSTRAINT check_is_workflow CHECK (do_is_workflow(workflow_id))
);


ALTER TABLE tasks OWNER TO $JCADMIN;

--
-- Name: tasks_taskid_seq; Type: SEQUENCE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE SEQUENCE tasks_taskid_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE tasks_taskid_seq OWNER TO $JCADMIN;

--
-- Name: tasks_taskid_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE tasks_taskid_seq OWNED BY tasks.task_id;


--
-- Name: version_tags; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE version_tags (
    tag text NOT NULL
);


ALTER TABLE version_tags OWNER TO $JCADMIN;

--
-- Name: worker_actions; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE worker_actions (
    worker_id bigint NOT NULL,
    action_id integer NOT NULL,
    CONSTRAINT check_is_action CHECK (do_is_action(action_id))
);


ALTER TABLE worker_actions OWNER TO $JCADMIN;

--
-- Name: workers; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE workers (
    worker_id bigint NOT NULL,
    name text,
    started timestamp with time zone DEFAULT now() NOT NULL,
    stopped timestamp with time zone,
    last_ping timestamp with time zone DEFAULT now() NOT NULL
);


ALTER TABLE workers OWNER TO $JCADMIN;

--
-- Name: workers_worker_id_seq; Type: SEQUENCE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE SEQUENCE workers_worker_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE workers_worker_id_seq OWNER TO $JCADMIN;

--
-- Name: workers_worker_id_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE workers_worker_id_seq OWNED BY workers.worker_id;


--
-- Name: actions action_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY actions ALTER COLUMN action_id SET DEFAULT nextval('actions_actionid_seq'::regclass);


--
-- Name: event_subscriptions subscription_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY event_subscriptions ALTER COLUMN subscription_id SET DEFAULT nextval('event_subscriptions_subscription_id_seq'::regclass);


--
-- Name: job_task_log job_task_log_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY job_task_log ALTER COLUMN job_task_log_id SET DEFAULT nextval('job_task_log_job_task_log_id_seq'::regclass);


--
-- Name: jobs job_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs ALTER COLUMN job_id SET DEFAULT nextval('jobs_jobid_seq'::regclass);


--
-- Name: queued_events event_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY queued_events ALTER COLUMN event_id SET DEFAULT nextval('queued_events_event_id_seq'::regclass);


--
-- Name: tasks task_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks ALTER COLUMN task_id SET DEFAULT nextval('tasks_taskid_seq'::regclass);


--
-- Name: workers worker_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY workers ALTER COLUMN worker_id SET DEFAULT nextval('workers_worker_id_seq'::regclass);


--
-- Data for Name: _procs; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY _procs (name, md5) FROM stdin;
announce	55306b04e24aee6127e71302a4fcb330
do_boolcode	8fe8680543337ebc636a6fec382a7ed3
do_check_role_membership	3a728bd306a7473b0eca5fc671f8d6e2
do_raise_fatal_error	a872752b1492173bebbcfe95c441d069
nexttask	63cce0fa52bd2cadbdb2b5b8d1da63b0
ping	131aff0592493096703a61cf32fda9a8
do_check_wait	a6cb6d4b05044f573fb7655d12b559c8
do_check_wait_for_task	9f16737e5d7a792d3aeb6c1bdde47f78
do_increase_stepcounter	364c1a5d793ab8688c556ccbaa6169c4
do_is_action	a03d0967a074a63d2d0df6e44d0599f0
do_is_workflow	cfab20aeaa64b019493cbb99d50c3ecb
do_notify_timerchange	fdcbf8d83b1a1b377de6ce31657058d0
do_sanity_check_workflow	4b5d6c411016a0b103362fb4ad4ba0c9
do_stringcode	784febdf1618efb69ca2d1e1d8d0516c
do_wfomap	ba8d2d85fa1be97f8bd18b581f9cee5f
do_check_same_workflow	d1f1f7812295c89d698fba748d112ba9
do_jobtaskdone	b53cd80b3f5b6d319eec416bb25f0986
do_cleanup_on_finish	c6dd78c89d0d60b1dd164dcf26bc9d39
do_unlock_task	6d817726b869cf4c1522c942b227f8a0
do_archival_and_cleanup	c473ca6a5728ec79d155a30fa907208d
do_task_epilogue	793ada92f3fdf0a6d5d9028c8bdfc0c0
do_switch_task	c486cc6646198108dd744e771ecdb990
task_done	e70f8a57217a30d8ec06a5143d6d8c51
withdraw	0f4eeeadfc1a360be3fd77538e6c16f4
get_job_status	8943535458d7033e2d0f84e8bc7f8482
do_imap	dcb782c432b0ced5109ee85811c51b18
do_raise_error	4df00f355b99dca68b2a1c90b747dff9
do_branch_task	7c0a4500cd4c6fc17ef4bbf6e2ce9bbf
get_task	21691d9ba52932cf14a66f446d4c0e88
do_task_done	922c014e1961a280c25bd228d0f587e0
raise_event	db2d287f80735aa79392febf15ed7212
task_failed	910e40dca85e5260e49670b189deb5bf
do_call_stored_procedure	041b9ec8b8fcf4f1eb828f6113939746
do_inargsmap	65b6adf62308e881af03593c7e326f1c
do_raise_error_task	4d8b7ef7d264955ddfa27a686202276f
do_raise_event_task	9c7f61c0a7e1d651a402e542c042d71a
do_subscribe_task	9a4b0a6e01826dcd149b77736866f53a
do_unsubscribe_task	441e0a16d694b293c406eec54c8eb629
do_reap_child_task	78ef738e4a0f26617c93a5459ea42667
blabla	4d439b57e671b65cc111a93249ab7d68
do_check_job_is_waiting	691a545282e0de2e69cbbe6ad751dff7
do_clear_waiting_events	58e492403fdebaaa6d12784ea4fba8d3
do_validate_json_schema_type	275b67208f1e97677f2f969e72b2b813
do_eval	a1a5f065a6738acea871a09597967fbb
do_omap	86442caba3c600b1e1c418f6daf9d104
do_outargscheck	6f46eb323054f5e7badc810eae375d1f
do_validate_json_schema	d0330b95f79b1f8792459dc2b2c3adaf
do_outargsmap	5ba2b840d5d411b9fad5d0a59f5998a8
do_prepare_for_action	aa3b698932e1da3a70cf04a59949388d
do_eval_task	d34f5430a56e7a89f3b85fa9e681dcb2
do_jobtaskerror	6ffd1b553f6f281af3a10fe4332044f3
do_populate_env	e0fce98e66b5ebb77a47ab076fd6be26
do_task_error	19e342291ba59cd3ee2182e09449dcf2
do_wait_for_children_task	fa30a08afa9afc3130eaa2e1b3c9d4c8
do_timeout	1bf32258492a955a0151e08a5c037efd
do_end_task	28120a2ddf46bf2b13e0a2936bdf792c
do_workflowoutargsmap	f20af3faf9bbc239b61d1924a63a5799
do_jobtask	26b849d1aa1ebad78bd10de4e4909f8c
do_log	eb8082a03114c960d421b1e3fa320a81
do_lock_task	fa396b64707f48b9f8b1ff772f8e2455
do_unlock	5550a71eeea95c2a17e2fa95565a5f0b
create_job	9043bd16086d789d4062ebc8ae55d713
do_create_childjob	4616490466042a671b0be3b4ff33143e
do_inargscheck	2be04e3cec4491d0f1baf6c9a6244577
do_wait_for_event_task	a8743b4539297e563d69c073a4826050
do_sleep_task	d8ed5f92587fa9189337cb6df07fe074
do_ping	187d4f08da52df86f0d4c8cfa1821906
\.


--
-- Data for Name: _schema; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY _schema (version) FROM stdin;
12
\.


--
-- Data for Name: action_inputs; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY action_inputs (action_id, name, type, optional, "default") FROM stdin;
-9	events	array	t	[]
-9	timeout	number	t	11.11
-8	name	string	f	\N
-7	name	string	f	\N
-10	msg	string	f	\N
1	step	number	t	1
1	counter	number	f	\N
2	root	number	f	\N
3	dividend	number	f	\N
3	divisor	number	t	3.1415
-13	locktype	string	f	\N
-14	locktype	string	f	\N
-14	lockvalue	string	f	\N
-13	lockvalue	string	f	\N
-7	mask	object	f	\N
-11	event	object	f	\N
-15	timeout	string	f	\N
\.


--
-- Data for Name: action_outputs; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY action_outputs (action_id, name, type, optional) FROM stdin;
-9	event	event	f
1	counter	number	f
2	square	number	f
3	quotient	number	f
\.


--
-- Data for Name: action_version_tags; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY action_version_tags (action_id, tag) FROM stdin;
\.


--
-- Data for Name: actions; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY actions (action_id, name, type, version, wfenv, rolename, config) FROM stdin;
0	start	system	0	\N	\N	\N
-1	end	system	0	\N	\N	\N
-2	no_op	system	0	\N	\N	\N
-3	eval	system	0	\N	\N	\N
-4	branch	system	0	\N	\N	\N
-5	switch	system	0	\N	\N	\N
-6	reap_child	system	0	\N	\N	\N
-7	subscribe	system	0	\N	\N	\N
-8	unsubscribe	system	0	\N	\N	\N
-9	wait_for_event	system	0	\N	\N	\N
-10	raise_error	system	0	\N	\N	\N
-11	raise_event	system	0	\N	\N	\N
-12	wait_for_children	system	0	\N	\N	\N
2	square	action	0	\N	\N	\N
3	div	action	0	\N	\N	\N
-13	lock	system	0	\N	\N	\N
-14	unlock	system	0	\N	\N	\N
-15	sleep	system	0	\N	\N	\N
1	add	action	0	\N	\N	{"retry": {"tries": "3", "interval": "5 seconds"}, "timeout": "5 days"}
\.


--
-- Name: actions_actionid_seq; Type: SEQUENCE SET; Schema: jobcenter; Owner: $JCADMIN
--

SELECT pg_catalog.setval('actions_actionid_seq', 4, true);


--
-- Data for Name: event_subscriptions; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY event_subscriptions (subscription_id, job_id, mask, waiting, name) FROM stdin;
\.


--
-- Name: event_subscriptions_subscription_id_seq; Type: SEQUENCE SET; Schema: jobcenter; Owner: $JCADMIN
--

SELECT pg_catalog.setval('event_subscriptions_subscription_id_seq', 1, true);


--
-- Data for Name: jc_env; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY jc_env (jcenv) FROM stdin;
{"version": "0.1"}
\.


--
-- Data for Name: jc_impersonate_roles; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY jc_impersonate_roles (rolename, impersonates) FROM stdin;
$JCCLIENT	deWerknemer
$JCCLIENT	theEmployee
$JCCLIENT	deKlant
$JCCLIENT	derKunde
$JCCLIENT	theCustomer
$JCCLIENT	deArbeider
\.


--
-- Data for Name: jc_role_members; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY jc_role_members (rolename, member_of) FROM stdin;
\.


--
-- Data for Name: jc_roles; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY jc_roles (rolename) FROM stdin;
$JCCLIENT
deWerknemer
theEmployee
deKlant
derKunde
theCustomer
deArbeider
\.


--
-- Data for Name: job_events; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY job_events (subscription_id, event_id) FROM stdin;
\.


--
-- Data for Name: job_task_log; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY job_task_log (job_task_log_id, job_id, task_id, variables, workflow_id, task_entered, task_started, task_completed, task_outargs, task_inargs, task_state) FROM stdin;
\.


--
-- Name: job_task_log_job_task_log_id_seq; Type: SEQUENCE SET; Schema: jobcenter; Owner: $JCADMIN
--

SELECT pg_catalog.setval('job_task_log_job_task_log_id_seq', 1, true);


--
-- Data for Name: jobs; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY jobs (job_id, workflow_id, task_id, parentjob_id, state, arguments, job_created, job_finished, variables, cookie, timeout, task_entered, task_started, task_completed, stepcounter, out_args, environment, max_steps, aborted, current_depth, task_state, job_state) FROM stdin;
\.


--
-- Data for Name: jobs_archive; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY jobs_archive (job_id, workflow_id, parentjob_id, state, arguments, job_created, job_finished, stepcounter, out_args, environment, max_steps, current_depth) FROM stdin;
\.


--
-- Name: jobs_jobid_seq; Type: SEQUENCE SET; Schema: jobcenter; Owner: $JCADMIN
--

SELECT pg_catalog.setval('jobs_jobid_seq', 1, true);


--
-- Data for Name: json_schemas; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY json_schemas (type, base, schema) FROM stdin;
null	t	\N
boolean	t	\N
number	t	\N
string	t	\N
array	t	\N
object	t	\N
integer	f	{"type": "integer"}
foobar	f	{"type": "object", "required": ["foo", "bar"]}
event	f	{"type": "object", "required": ["name", "event_id", "when", "data"]}
fbb	f	{"definitions": {"barfoo": {"type": "object", "required": ["foo", "bar"]}}}
barfoo	f	"jcdb:fbb#/definitions/barfoo"
\.


--
-- Data for Name: locks; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY locks (job_id, locktype, lockvalue, contended, inheritable, top_level_job_id) FROM stdin;
\.


--
-- Data for Name: locktypes; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY locktypes (locktype) FROM stdin;
foo
abc
slot
schloss
\.


--
-- Data for Name: next_tasks; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY next_tasks (from_task_id, to_task_id, "when") FROM stdin;
\.


--
-- Data for Name: queued_events; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY queued_events (event_id, "when", eventdata) FROM stdin;
\.


--
-- Name: queued_events_event_id_seq; Type: SEQUENCE SET; Schema: jobcenter; Owner: $JCADMIN
--

SELECT pg_catalog.setval('queued_events_event_id_seq', 1, true);


--
-- Data for Name: tasks; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY tasks (task_id, workflow_id, action_id, on_error_task_id, attributes, next_task_id) FROM stdin;
\.


--
-- Name: tasks_taskid_seq; Type: SEQUENCE SET; Schema: jobcenter; Owner: $JCADMIN
--

SELECT pg_catalog.setval('tasks_taskid_seq', 1, true);


--
-- Data for Name: version_tags; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY version_tags (tag) FROM stdin;
stable
unittest
\.


--
-- Data for Name: worker_actions; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY worker_actions (worker_id, action_id) FROM stdin;
\.


--
-- Data for Name: workers; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY workers (worker_id, name, started, stopped, last_ping) FROM stdin;
\.


--
-- Name: workers_worker_id_seq; Type: SEQUENCE SET; Schema: jobcenter; Owner: $JCADMIN
--

SELECT pg_catalog.setval('workers_worker_id_seq', 1, true);


--
-- Name: _procs _funcs_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY _procs
    ADD CONSTRAINT _funcs_pkey PRIMARY KEY (name);


--
-- Name: action_inputs action_inputs_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_inputs
    ADD CONSTRAINT action_inputs_pkey PRIMARY KEY (action_id, name);


--
-- Name: action_outputs action_outputs_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_outputs
    ADD CONSTRAINT action_outputs_pkey PRIMARY KEY (action_id, name);


--
-- Name: action_version_tags action_version_tags_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_version_tags
    ADD CONSTRAINT action_version_tags_pkey PRIMARY KEY (action_id, tag);


--
-- Name: actions actions_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (action_id);


--
-- Name: next_tasks check_same_workflow; Type: CHECK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE next_tasks
    ADD CONSTRAINT check_same_workflow CHECK (do_check_same_workflow(from_task_id, to_task_id)) NOT VALID;


--
-- Name: event_subscriptions event_subscriptions_jobid_eventmask_ukey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_jobid_eventmask_ukey UNIQUE (job_id, mask);


--
-- Name: event_subscriptions event_subscriptions_jobid_name_ukey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_jobid_name_ukey UNIQUE (job_id, name);


--
-- Name: event_subscriptions event_subscriptions_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_pkey PRIMARY KEY (subscription_id);


--
-- Name: jc_impersonate_roles jc_impersonate_roles_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_impersonate_roles
    ADD CONSTRAINT jc_impersonate_roles_pkey PRIMARY KEY (rolename, impersonates);


--
-- Name: jc_role_members jc_role_members_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_role_members
    ADD CONSTRAINT jc_role_members_pkey PRIMARY KEY (rolename, member_of);


--
-- Name: jc_roles jc_roles_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_roles
    ADD CONSTRAINT jc_roles_pkey PRIMARY KEY (rolename);


--
-- Name: job_events job_events_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY job_events
    ADD CONSTRAINT job_events_pkey PRIMARY KEY (subscription_id, event_id);


--
-- Name: jobs_archive job_history_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs_archive
    ADD CONSTRAINT job_history_pkey PRIMARY KEY (job_id);


--
-- Name: job_task_log job_step_history_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY job_task_log
    ADD CONSTRAINT job_step_history_pkey PRIMARY KEY (job_task_log_id);


--
-- Name: jobs jobs_cookie_key; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_cookie_key UNIQUE (cookie);


--
-- Name: jobs jobs_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (job_id);


--
-- Name: json_schemas json_schemas_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY json_schemas
    ADD CONSTRAINT json_schemas_pkey PRIMARY KEY (type);


--
-- Name: locks locks_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY locks
    ADD CONSTRAINT locks_pkey PRIMARY KEY (job_id, locktype, lockvalue);


--
-- Name: locks locks_ukey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY locks
    ADD CONSTRAINT locks_ukey UNIQUE (locktype, lockvalue);


--
-- Name: locktypes locktypes_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY locktypes
    ADD CONSTRAINT locktypes_pkey PRIMARY KEY (locktype);


--
-- Name: next_tasks next_tasks_from_when_uniq; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_tasks_from_when_uniq UNIQUE (from_task_id, "when");


--
-- Name: next_tasks next_tasks_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_tasks_pkey PRIMARY KEY (from_task_id, to_task_id, "when");


--
-- Name: queued_events queued_events_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY queued_events
    ADD CONSTRAINT queued_events_pkey PRIMARY KEY (event_id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (task_id);


--
-- Name: tasks tasks_task_id_workflow_id_ukey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_task_id_workflow_id_ukey UNIQUE (workflow_id, task_id);


--
-- Name: actions unique_type_name_version; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT unique_type_name_version UNIQUE (type, name, version);


--
-- Name: version_tags version_tag_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY version_tags
    ADD CONSTRAINT version_tag_pkey PRIMARY KEY (tag);


--
-- Name: worker_actions worker_actions_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY worker_actions
    ADD CONSTRAINT worker_actions_pkey PRIMARY KEY (worker_id, action_id);


--
-- Name: workers workers_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY workers
    ADD CONSTRAINT workers_pkey PRIMARY KEY (worker_id);


--
-- Name: workers workers_workername_stopped_key; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY workers
    ADD CONSTRAINT workers_workername_stopped_key UNIQUE (name, stopped);


--
-- Name: jcenv_uidx; Type: INDEX; Schema: jobcenter; Owner: $JCADMIN
--

CREATE UNIQUE INDEX jcenv_uidx ON jc_env USING btree ((((jcenv IS NULL) OR (jcenv IS NOT NULL))));


--
-- Name: job_parentjob_id_index; Type: INDEX; Schema: jobcenter; Owner: $JCADMIN
--

CREATE INDEX job_parentjob_id_index ON jobs USING btree (parentjob_id);


--
-- Name: job_task_log_jobid_idx; Type: INDEX; Schema: jobcenter; Owner: $JCADMIN
--

CREATE INDEX job_task_log_jobid_idx ON job_task_log USING btree (job_id);


--
-- Name: jobs_state_idx; Type: INDEX; Schema: jobcenter; Owner: $JCADMIN
--

CREATE INDEX jobs_state_idx ON jobs USING btree (state);


--
-- Name: jobs_timeout_idx; Type: INDEX; Schema: jobcenter; Owner: $JCADMIN
--

CREATE INDEX jobs_timeout_idx ON jobs USING btree (timeout);


--
-- Name: workers_stopped_idx; Type: INDEX; Schema: jobcenter; Owner: $JCADMIN
--

CREATE INDEX workers_stopped_idx ON workers USING btree (stopped);


--
-- Name: jobs on_job_state_change; Type: TRIGGER; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TRIGGER on_job_state_change AFTER UPDATE OF state ON jobs FOR EACH ROW WHEN (((old.state = 'eventwait'::job_state) AND (new.state <> 'eventwait'::job_state))) EXECUTE PROCEDURE do_clear_waiting_events();


--
-- Name: jobs on_job_task_change; Type: TRIGGER; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TRIGGER on_job_task_change BEFORE UPDATE OF task_id ON jobs FOR EACH ROW EXECUTE PROCEDURE do_increase_stepcounter();


--
-- Name: jobs on_jobs_timerchange; Type: TRIGGER; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TRIGGER on_jobs_timerchange AFTER INSERT OR DELETE OR UPDATE OF timeout ON jobs FOR EACH STATEMENT EXECUTE PROCEDURE do_notify_timerchange();


--
-- Name: action_inputs action_inputs_actionid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_inputs
    ADD CONSTRAINT action_inputs_actionid_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: action_inputs action_inputs_type_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_inputs
    ADD CONSTRAINT action_inputs_type_fkey FOREIGN KEY (type) REFERENCES json_schemas(type) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: action_outputs action_outputs_actionid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_outputs
    ADD CONSTRAINT action_outputs_actionid_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: action_outputs action_outputs_type_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_outputs
    ADD CONSTRAINT action_outputs_type_fkey FOREIGN KEY (type) REFERENCES json_schemas(type) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: actions action_rolename_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT action_rolename_fkey FOREIGN KEY (rolename) REFERENCES jc_roles(rolename) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: action_version_tags action_version_tags_action_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_version_tags
    ADD CONSTRAINT action_version_tags_action_id_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON DELETE CASCADE;


--
-- Name: action_version_tags action_version_tags_tag_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_version_tags
    ADD CONSTRAINT action_version_tags_tag_fkey FOREIGN KEY (tag) REFERENCES version_tags(tag) ON DELETE CASCADE;


--
-- Name: event_subscriptions event_subscriptions_job_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_job_id_fkey FOREIGN KEY (job_id) REFERENCES jobs(job_id);


--
-- Name: jc_impersonate_roles jc_impersonate_roles_impersonates_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_impersonate_roles
    ADD CONSTRAINT jc_impersonate_roles_impersonates_fkey FOREIGN KEY (impersonates) REFERENCES jc_roles(rolename) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: jc_impersonate_roles jc_impersonate_roles_rolename_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_impersonate_roles
    ADD CONSTRAINT jc_impersonate_roles_rolename_fkey FOREIGN KEY (rolename) REFERENCES jc_roles(rolename) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: jc_role_members jc_role_members_member_of_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_role_members
    ADD CONSTRAINT jc_role_members_member_of_fkey FOREIGN KEY (member_of) REFERENCES jc_roles(rolename) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: jc_role_members jc_role_members_rolename_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_role_members
    ADD CONSTRAINT jc_role_members_rolename_fkey FOREIGN KEY (rolename) REFERENCES jc_roles(rolename) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: job_events job_events_eventid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY job_events
    ADD CONSTRAINT job_events_eventid_fkey FOREIGN KEY (event_id) REFERENCES queued_events(event_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: job_events job_events_subscriptionid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY job_events
    ADD CONSTRAINT job_events_subscriptionid_fkey FOREIGN KEY (subscription_id) REFERENCES event_subscriptions(subscription_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: jobs_archive job_history_workflowid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs_archive
    ADD CONSTRAINT job_history_workflowid_fkey FOREIGN KEY (workflow_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: jobs jobs_parent_jobid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_parent_jobid_fkey FOREIGN KEY (parentjob_id) REFERENCES jobs(job_id);


--
-- Name: jobs jobs_taskid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_taskid_fkey FOREIGN KEY (workflow_id, task_id) REFERENCES tasks(workflow_id, task_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: jobs jobs_workflowid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_workflowid_fkey FOREIGN KEY (workflow_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: locks locks_job_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY locks
    ADD CONSTRAINT locks_job_id_fkey FOREIGN KEY (job_id) REFERENCES jobs(job_id);


--
-- Name: locks locks_locktype_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY locks
    ADD CONSTRAINT locks_locktype_fkey FOREIGN KEY (locktype) REFERENCES locktypes(locktype);


--
-- Name: next_tasks next_task_from_task_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_task_from_task_id_fkey FOREIGN KEY (from_task_id) REFERENCES tasks(task_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: next_tasks next_task_to_task_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_task_to_task_id_fkey FOREIGN KEY (to_task_id) REFERENCES tasks(task_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- Name: tasks task_next_task_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT task_next_task_fkey FOREIGN KEY (next_task_id) REFERENCES tasks(task_id);


--
-- Name: tasks task_on_error_task_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT task_on_error_task_fkey FOREIGN KEY (on_error_task_id) REFERENCES tasks(task_id);


--
-- Name: tasks tasks_actionid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_actionid_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: tasks tasks_workflowid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_workflowid_fkey FOREIGN KEY (workflow_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- Name: worker_actions worker_actions_action_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY worker_actions
    ADD CONSTRAINT worker_actions_action_id_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id);


--
-- Name: worker_actions worker_actions_worker_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY worker_actions
    ADD CONSTRAINT worker_actions_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES workers(worker_id) ON DELETE CASCADE;


--
-- Name: jobcenter; Type: ACL; Schema: -; Owner: $JCADMIN
--

GRANT USAGE ON SCHEMA jobcenter TO $JCCLIENT;
GRANT USAGE ON SCHEMA jobcenter TO $JCMAESTRO;
GRANT ALL ON SCHEMA jobcenter TO $JCPERL;
GRANT ALL ON SCHEMA jobcenter TO $JCSYSTEM;


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- Name: announce(text, text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION announce(workername text, actionname text, impersonate text) FROM PUBLIC;
GRANT ALL ON FUNCTION announce(workername text, actionname text, impersonate text) TO $JCCLIENT;


--
-- Name: create_job(text, jsonb, text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION create_job(wfname text, args jsonb, tag text, impersonate text) FROM PUBLIC;
GRANT ALL ON FUNCTION create_job(wfname text, args jsonb, tag text, impersonate text) TO $JCCLIENT;


--
-- Name: do_archival_and_cleanup(text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_archival_and_cleanup(dummy text) FROM PUBLIC;
GRANT ALL ON FUNCTION do_archival_and_cleanup(dummy text) TO $JCMAESTRO;


--
-- Name: do_boolcode(text, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_boolcode(code text, args jsonb, env jsonb, vars jsonb) FROM PUBLIC;


--
-- Name: do_branch_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_branch_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_call_stored_procedure(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_call_stored_procedure(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_check_job_is_waiting(bigint, boolean); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_check_job_is_waiting(bigint, boolean) FROM PUBLIC;


--
-- Name: do_check_role_membership(text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_check_role_membership(a_have_role text, a_should_role text) FROM PUBLIC;


--
-- Name: do_check_same_workflow(integer, integer); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_check_same_workflow(a_task1_id integer, a_task2_id integer) FROM PUBLIC;


--
-- Name: do_check_wait(integer, boolean); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_check_wait(a_action_id integer, a_wait boolean) FROM PUBLIC;


--
-- Name: do_check_wait_for_task(integer, integer); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_check_wait_for_task(a_action_id integer, a_wait_for_task integer) FROM PUBLIC;


--
-- Name: do_cleanup_on_finish(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_cleanup_on_finish(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_clear_waiting_events(); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_clear_waiting_events() FROM PUBLIC;


--
-- Name: do_create_childjob(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_create_childjob(a_parentjobtask jobtask) FROM PUBLIC;


--
-- Name: do_end_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_end_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_eval(text, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_eval(code text, args jsonb, env jsonb, vars jsonb) FROM PUBLIC;


--
-- Name: do_eval_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_eval_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_imap(text, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_imap(code text, args jsonb, env jsonb, vars jsonb) FROM PUBLIC;


--
-- Name: do_inargsmap(integer, jobtask, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_inargsmap(a_action_id integer, a_jobtask jobtask, a_args jsonb, a_env jsonb, a_vars jsonb) FROM PUBLIC;


--
-- Name: do_increase_stepcounter(); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_increase_stepcounter() FROM PUBLIC;


--
-- Name: do_is_action(integer); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_is_action(integer) FROM PUBLIC;


--
-- Name: do_is_workflow(integer); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_is_workflow(integer) FROM PUBLIC;


--
-- Name: do_jobtask(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_jobtask(a_jobtask jobtask) FROM PUBLIC;
GRANT ALL ON FUNCTION do_jobtask(a_jobtask jobtask) TO $JCMAESTRO;


--
-- Name: do_jobtaskdone(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_jobtaskdone(a_jobtask jobtask) FROM PUBLIC;
GRANT ALL ON FUNCTION do_jobtaskdone(a_jobtask jobtask) TO $JCMAESTRO;


--
-- Name: do_jobtaskerror(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_jobtaskerror(a_jobtask jobtask) FROM PUBLIC;
GRANT ALL ON FUNCTION do_jobtaskerror(a_jobtask jobtask) TO $JCMAESTRO;


--
-- Name: do_lock_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_lock_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_log(bigint, boolean, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_log(a_job_id bigint, a_logvars boolean, a_inargs jsonb, a_outargs jsonb) FROM PUBLIC;


--
-- Name: do_notify_timerchange(); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_notify_timerchange() FROM PUBLIC;


--
-- Name: do_omap(text, jsonb, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_omap(code text, args jsonb, env jsonb, vars jsonb, oargs jsonb) FROM PUBLIC;


--
-- Name: do_outargsmap(jobtask, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_outargsmap(a_jobtask jobtask, a_outargs jsonb) FROM PUBLIC;


--
-- Name: do_ping(bigint); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_ping(a_worker_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION do_ping(a_worker_id bigint) TO $JCMAESTRO;


--
-- Name: do_prepare_for_action(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_prepare_for_action(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_raise_error(jobtask, text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_raise_error(a_jobtask jobtask, a_errmsg text, a_class text) FROM PUBLIC;


--
-- Name: do_raise_error_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_raise_error_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_raise_event_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_raise_event_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_reap_child_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_reap_child_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_sanity_check_workflow(integer); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_sanity_check_workflow(a_workflow_id integer) FROM PUBLIC;


--
-- Name: do_stringcode(text, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_stringcode(code text, args jsonb, env jsonb, vars jsonb) FROM PUBLIC;


--
-- Name: do_subscribe_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_subscribe_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_switch_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_switch_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_task_done(jobtask, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_task_done(a_jobtask jobtask, a_outargs jsonb) FROM PUBLIC;


--
-- Name: do_task_epilogue(jobtask, boolean, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_task_epilogue(a_jobtask jobtask, a_vars_changed boolean, a_newvars jsonb, a_inargs jsonb, a_outargs jsonb) FROM PUBLIC;


--
-- Name: do_task_error(jobtask, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_task_error(a_jobtask jobtask, a_outargs jsonb) FROM PUBLIC;


--
-- Name: do_timeout(); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_timeout() FROM PUBLIC;
GRANT ALL ON FUNCTION do_timeout() TO $JCMAESTRO;


--
-- Name: do_unlock(text, text, integer, bigint, bigint, bigint); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_unlock(a_locktype text, a_lockvalue text, a_contended integer, a_job_id bigint, a_parentjob_id bigint, a_top_level_job_id bigint) FROM PUBLIC;


--
-- Name: do_unlock_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_unlock_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_unsubscribe_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_unsubscribe_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_wait_for_children_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_wait_for_children_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_wait_for_event_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_wait_for_event_task(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: do_wfomap(text, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_wfomap(code text, args jsonb, env jsonb, vars jsonb) FROM PUBLIC;


--
-- Name: do_workflowoutargsmap(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_workflowoutargsmap(a_jobtask jobtask) FROM PUBLIC;


--
-- Name: get_job_status(bigint); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION get_job_status(a_job_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION get_job_status(a_job_id bigint) TO $JCCLIENT;


--
-- Name: get_task(text, text, bigint, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION get_task(a_workername text, a_actionname text, a_job_id bigint, a_pattern jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION get_task(a_workername text, a_actionname text, a_job_id bigint, a_pattern jsonb) TO $JCCLIENT;


--
-- Name: ping(bigint); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION ping(a_worker_id bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION ping(a_worker_id bigint) TO $JCCLIENT;


--
-- Name: raise_event(jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION raise_event(a_eventdata jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION raise_event(a_eventdata jsonb) TO $JCCLIENT;


--
-- Name: task_done(text, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION task_done(a_jobcookie text, a_out_args jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION task_done(a_jobcookie text, a_out_args jsonb) TO $JCCLIENT;


--
-- Name: task_failed(text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION task_failed(a_cookie text, a_errmsg text) FROM PUBLIC;
GRANT ALL ON FUNCTION task_failed(a_cookie text, a_errmsg text) TO $JCCLIENT;


--
-- Name: withdraw(text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION withdraw(a_workername text, a_actionname text) FROM PUBLIC;
GRANT ALL ON FUNCTION withdraw(a_workername text, a_actionname text) TO $JCCLIENT;


--
-- Name: action_inputs; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE action_inputs TO $JCSYSTEM;


--
-- Name: action_outputs; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE action_outputs TO $JCSYSTEM;


--
-- Name: action_version_tags; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE action_version_tags TO $JCSYSTEM;


--
-- Name: actions; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE actions TO $JCSYSTEM;


--
-- Name: event_subscriptions; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE event_subscriptions TO $JCSYSTEM;


--
-- Name: event_subscriptions_subscription_id_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT ALL ON SEQUENCE event_subscriptions_subscription_id_seq TO $JCSYSTEM;


--
-- Name: jc_env; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE jc_env TO $JCSYSTEM;


--
-- Name: jc_impersonate_roles; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE jc_impersonate_roles TO $JCSYSTEM;


--
-- Name: jc_role_members; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE jc_role_members TO $JCSYSTEM;


--
-- Name: jc_roles; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE jc_roles TO $JCSYSTEM;


--
-- Name: job_events; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE job_events TO $JCSYSTEM;


--
-- Name: job_task_log; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE job_task_log TO $JCSYSTEM;


--
-- Name: job_task_log_job_task_log_id_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT ALL ON SEQUENCE job_task_log_job_task_log_id_seq TO $JCSYSTEM;


--
-- Name: jobs; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE jobs TO $JCSYSTEM;


--
-- Name: jobs_archive; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE jobs_archive TO $JCSYSTEM;


--
-- Name: jobs_jobid_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT ALL ON SEQUENCE jobs_jobid_seq TO $JCSYSTEM;


--
-- Name: json_schemas; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE json_schemas TO $JCSYSTEM;


--
-- Name: locks; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE locks TO $JCSYSTEM;


--
-- Name: locktypes; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE locktypes TO $JCSYSTEM;


--
-- Name: next_tasks; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE next_tasks TO $JCSYSTEM;


--
-- Name: queued_events; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE queued_events TO $JCSYSTEM;


--
-- Name: queued_events_event_id_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT ALL ON SEQUENCE queued_events_event_id_seq TO $JCSYSTEM;


--
-- Name: tasks; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT ALL ON TABLE tasks TO $JCSYSTEM;


--
-- Name: tasks_taskid_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT ALL ON SEQUENCE tasks_taskid_seq TO $JCSYSTEM;


--
-- Name: version_tags; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT ON TABLE version_tags TO $JCSYSTEM;


--
-- Name: worker_actions; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE worker_actions TO $JCSYSTEM;


--
-- Name: workers; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE workers TO $JCSYSTEM;


--
-- Name: workers_worker_id_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

GRANT ALL ON SEQUENCE workers_worker_id_seq TO $JCSYSTEM;


--
-- PostgreSQL database dump complete
--

