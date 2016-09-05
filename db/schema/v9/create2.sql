
SET default_tablespace = '';

SET default_with_oids = false;

--
-- TOC entry 186 (class 1259 OID 36193)
-- Name: _procs; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE _procs (
    name text NOT NULL,
    md5 text
);


ALTER TABLE _procs OWNER TO $JCADMIN;

--
-- TOC entry 187 (class 1259 OID 36199)
-- Name: _schema; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE _schema (
    version text
);


ALTER TABLE _schema OWNER TO $JCADMIN;

--
-- TOC entry 188 (class 1259 OID 36205)
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
-- TOC entry 189 (class 1259 OID 36212)
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
-- TOC entry 212 (class 1259 OID 36512)
-- Name: action_version_tags; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE action_version_tags (
    action_id integer NOT NULL,
    tag text NOT NULL
);


ALTER TABLE action_version_tags OWNER TO $JCADMIN;

--
-- TOC entry 190 (class 1259 OID 36219)
-- Name: actions; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE actions (
    action_id integer NOT NULL,
    name text NOT NULL,
    type action_type DEFAULT 'action'::action_type NOT NULL,
    version integer DEFAULT 0 NOT NULL,
    wfmapcode text,
    wfenv jsonb,
    rolename name,
    CONSTRAINT actions_wfenvcheck CHECK ((((type <> 'workflow'::action_type) AND (wfenv IS NULL)) OR (type = 'workflow'::action_type))),
    CONSTRAINT actions_wfmapcodecheck CHECK ((((type <> 'workflow'::action_type) AND (wfmapcode IS NULL)) OR (type = 'workflow'::action_type)))
);


ALTER TABLE actions OWNER TO $JCADMIN;

--
-- TOC entry 191 (class 1259 OID 36228)
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
-- TOC entry 2542 (class 0 OID 0)
-- Dependencies: 191
-- Name: actions_actionid_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE actions_actionid_seq OWNED BY actions.action_id;


--
-- TOC entry 192 (class 1259 OID 36230)
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
-- TOC entry 193 (class 1259 OID 36238)
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
-- TOC entry 2545 (class 0 OID 0)
-- Dependencies: 193
-- Name: event_subscriptions_subscription_id_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE event_subscriptions_subscription_id_seq OWNED BY event_subscriptions.subscription_id;


--
-- TOC entry 210 (class 1259 OID 36497)
-- Name: jc_env; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jc_env (
    jcenv jsonb
);


ALTER TABLE jc_env OWNER TO $JCADMIN;

--
-- TOC entry 218 (class 1259 OID 36807)
-- Name: jc_impersonate_roles; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jc_impersonate_roles (
    rolename text NOT NULL,
    impersonates text NOT NULL
);


ALTER TABLE jc_impersonate_roles OWNER TO $JCADMIN;

--
-- TOC entry 219 (class 1259 OID 36841)
-- Name: jc_role_members; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jc_role_members (
    rolename text NOT NULL,
    member_of text NOT NULL
);


ALTER TABLE jc_role_members OWNER TO $JCADMIN;

--
-- TOC entry 217 (class 1259 OID 36781)
-- Name: jc_roles; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jc_roles (
    rolename text NOT NULL
);


ALTER TABLE jc_roles OWNER TO $JCADMIN;

--
-- TOC entry 194 (class 1259 OID 36240)
-- Name: job_events; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE job_events (
    subscription_id integer NOT NULL,
    event_id integer NOT NULL
);


ALTER TABLE job_events OWNER TO $JCADMIN;

--
-- TOC entry 195 (class 1259 OID 36243)
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
    worker_id bigint,
    task_outargs jsonb,
    task_inargs jsonb
);


ALTER TABLE job_task_log OWNER TO $JCADMIN;

--
-- TOC entry 2552 (class 0 OID 0)
-- Dependencies: 195
-- Name: COLUMN job_task_log.variables; Type: COMMENT; Schema: jobcenter; Owner: $JCADMIN
--

COMMENT ON COLUMN job_task_log.variables IS 'the new value of the variables on completion of the task
if the new value is different from the old value';


--
-- TOC entry 196 (class 1259 OID 36249)
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
-- TOC entry 2554 (class 0 OID 0)
-- Dependencies: 196
-- Name: job_task_log_job_task_log_id_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE job_task_log_job_task_log_id_seq OWNED BY job_task_log.job_task_log_id;


--
-- TOC entry 197 (class 1259 OID 36251)
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
    worker_id bigint,
    variables jsonb,
    parenttask_id integer,
    parentwait boolean DEFAULT false NOT NULL,
    cookie uuid,
    timeout timestamp with time zone,
    task_entered timestamp with time zone,
    task_started timestamp with time zone,
    task_completed timestamp with time zone,
    stepcounter integer DEFAULT 0 NOT NULL,
    out_args jsonb,
    waitforlocktype text,
    waitforlockvalue text,
    environment jsonb,
    max_steps integer DEFAULT 100 NOT NULL,
    aborted boolean DEFAULT false NOT NULL,
    waitforlockinherit boolean,
    current_depth integer DEFAULT 1 NOT NULL,
    CONSTRAINT check_is_workflow CHECK (do_is_workflow(workflow_id))
);


ALTER TABLE jobs OWNER TO $JCADMIN;

--
-- TOC entry 216 (class 1259 OID 36612)
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
-- TOC entry 198 (class 1259 OID 36260)
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
-- TOC entry 2558 (class 0 OID 0)
-- Dependencies: 198
-- Name: jobs_jobid_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE jobs_jobid_seq OWNED BY jobs.job_id;


--
-- TOC entry 199 (class 1259 OID 36262)
-- Name: jsonb_object_fields; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE jsonb_object_fields (
    typename text NOT NULL,
    standard boolean DEFAULT false NOT NULL,
    fields text[],
    CONSTRAINT jsonb_object_fields_check CHECK ((((standard = true) AND (fields IS NULL)) OR ((standard = false) AND (fields IS NOT NULL))))
);


ALTER TABLE jsonb_object_fields OWNER TO $JCADMIN;

--
-- TOC entry 200 (class 1259 OID 36270)
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
-- TOC entry 201 (class 1259 OID 36277)
-- Name: locktypes; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE locktypes (
    locktype text NOT NULL
);


ALTER TABLE locktypes OWNER TO $JCADMIN;

--
-- TOC entry 202 (class 1259 OID 36283)
-- Name: next_tasks; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE next_tasks (
    from_task_id integer NOT NULL,
    to_task_id integer NOT NULL,
    "when" text NOT NULL,
    CONSTRAINT check_same_workflow CHECK (do_check_same_workflow(from_task_id, to_task_id))
);


ALTER TABLE next_tasks OWNER TO $JCADMIN;

--
-- TOC entry 203 (class 1259 OID 36290)
-- Name: queued_events; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE queued_events (
    event_id bigint NOT NULL,
    "when" timestamp with time zone DEFAULT now() NOT NULL,
    eventdata jsonb NOT NULL
);


ALTER TABLE queued_events OWNER TO $JCADMIN;

--
-- TOC entry 204 (class 1259 OID 36297)
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
-- TOC entry 2565 (class 0 OID 0)
-- Dependencies: 204
-- Name: queued_events_event_id_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE queued_events_event_id_seq OWNED BY queued_events.event_id;


--
-- TOC entry 205 (class 1259 OID 36299)
-- Name: tasks; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE tasks (
    task_id integer NOT NULL,
    workflow_id integer NOT NULL,
    action_id integer,
    on_error_task_id integer,
    attributes jsonb,
    wait boolean DEFAULT true NOT NULL,
    reapfromtask_id integer,
    next_task_id integer,
    CONSTRAINT check_is_workflow CHECK (do_is_workflow(workflow_id)),
    CONSTRAINT check_wait CHECK (do_check_wait(action_id, wait))
);


ALTER TABLE tasks OWNER TO $JCADMIN;

--
-- TOC entry 206 (class 1259 OID 36308)
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
-- TOC entry 2568 (class 0 OID 0)
-- Dependencies: 206
-- Name: tasks_taskid_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE tasks_taskid_seq OWNED BY tasks.task_id;


--
-- TOC entry 211 (class 1259 OID 36504)
-- Name: version_tags; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE version_tags (
    tag text NOT NULL
);


ALTER TABLE version_tags OWNER TO $JCADMIN;

--
-- TOC entry 207 (class 1259 OID 36310)
-- Name: worker_actions; Type: TABLE; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TABLE worker_actions (
    worker_id bigint NOT NULL,
    action_id integer NOT NULL,
    CONSTRAINT check_is_action CHECK (do_is_action(action_id))
);


ALTER TABLE worker_actions OWNER TO $JCADMIN;

--
-- TOC entry 208 (class 1259 OID 36314)
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
-- TOC entry 209 (class 1259 OID 36322)
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
-- TOC entry 2573 (class 0 OID 0)
-- Dependencies: 209
-- Name: workers_worker_id_seq; Type: SEQUENCE OWNED BY; Schema: jobcenter; Owner: $JCADMIN
--

ALTER SEQUENCE workers_worker_id_seq OWNED BY workers.worker_id;


--
-- TOC entry 2198 (class 2604 OID 36324)
-- Name: action_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY actions ALTER COLUMN action_id SET DEFAULT nextval('actions_actionid_seq'::regclass);


--
-- TOC entry 2202 (class 2604 OID 36325)
-- Name: subscription_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY event_subscriptions ALTER COLUMN subscription_id SET DEFAULT nextval('event_subscriptions_subscription_id_seq'::regclass);


--
-- TOC entry 2204 (class 2604 OID 36326)
-- Name: job_task_log_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY job_task_log ALTER COLUMN job_task_log_id SET DEFAULT nextval('job_task_log_job_task_log_id_seq'::regclass);


--
-- TOC entry 2208 (class 2604 OID 36327)
-- Name: job_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs ALTER COLUMN job_id SET DEFAULT nextval('jobs_jobid_seq'::regclass);


--
-- TOC entry 2219 (class 2604 OID 36328)
-- Name: event_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY queued_events ALTER COLUMN event_id SET DEFAULT nextval('queued_events_event_id_seq'::regclass);


--
-- TOC entry 2221 (class 2604 OID 36329)
-- Name: task_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks ALTER COLUMN task_id SET DEFAULT nextval('tasks_taskid_seq'::regclass);


--
-- TOC entry 2227 (class 2604 OID 36330)
-- Name: worker_id; Type: DEFAULT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY workers ALTER COLUMN worker_id SET DEFAULT nextval('workers_worker_id_seq'::regclass);


--
-- TOC entry 2440 (class 0 OID 36193)
-- Dependencies: 186
-- Data for Name: _procs; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY _procs (name, md5) FROM stdin;
announce	55306b04e24aee6127e71302a4fcb330
do_eval	cf3b8c0089323244460849773103c7ee
do_boolcode	8fe8680543337ebc636a6fec382a7ed3
do_check_role_membership	3a728bd306a7473b0eca5fc671f8d6e2
do_ping	5956d8030c240131659854d44385859d
do_jobtask	e18c2e917e6f78d48ca771526cefceca
do_reap_child_task	535b8c0ddfb313c3a5229496ff8afe9b
ping	131aff0592493096703a61cf32fda9a8
do_omap	110a57fdd39c2a1c54e85a6a5baa12ef
do_check_job_is_waiting	2930b852c9945132bdbeaa86d9fdf8e8
do_check_wait	a6cb6d4b05044f573fb7655d12b559c8
do_check_wait_for_task	9f16737e5d7a792d3aeb6c1bdde47f78
get_task	4b175e7c1dc79193acf1358bfccef31e
do_clear_waiting_events	656583ebaddeddd182cce5dbec55fea6
do_increase_stepcounter	364c1a5d793ab8688c556ccbaa6169c4
do_is_action	a03d0967a074a63d2d0df6e44d0599f0
do_is_workflow	cfab20aeaa64b019493cbb99d50c3ecb
do_notify_timerchange	fdcbf8d83b1a1b377de6ce31657058d0
do_sanity_check_workflow	4b5d6c411016a0b103362fb4ad4ba0c9
do_stringcode	784febdf1618efb69ca2d1e1d8d0516c
do_wfomap	ba8d2d85fa1be97f8bd18b581f9cee5f
do_call_stored_procedure	53caa692d8d2f705fef3b4a078d1a7b3
do_check_same_workflow	d1f1f7812295c89d698fba748d112ba9
do_jobtaskdone	b53cd80b3f5b6d319eec416bb25f0986
do_cleanup_on_finish	c6dd78c89d0d60b1dd164dcf26bc9d39
do_unlock	1c89f1d3cff6e993ab8bbf5812361535
do_lock_task	adf4799d28c42c024967c91f687e2417
do_unlock_task	6d817726b869cf4c1522c942b227f8a0
do_log	e639a7f7605b2d12be1acfd62c72245c
do_prepare_for_action	c6023b934bdc628ea25b07fbb7f70de1
do_raise_error_task	0bea38efa76e47c514456bb9e41ff46a
do_raise_event_task	9db6a036c32a4d6a0f80e47e9bfe76a9
do_archival_and_cleanup	c473ca6a5728ec79d155a30fa907208d
do_subscribe_task	0f5f5aacc64c1b18e82ce1b256b4b78b
do_task_epilogue	793ada92f3fdf0a6d5d9028c8bdfc0c0
do_timeout	7bc199900465cb71af11c2644c162907
do_switch_task	c486cc6646198108dd744e771ecdb990
do_unsubscribe_task	ea6b87cf5b0e57384a10137e7850f298
do_create_childjob	5b75d9ee60a981bb19e9b5c7d558c167
do_jobtaskerror	61373816a65dd65780e0917a9cf65cc0
raise_event	0fa4777e21bdb23fcd9ce4c9d77e2eac
task_done	e70f8a57217a30d8ec06a5143d6d8c51
task_failed	4f43258ed20282f349f9e76620a529d4
withdraw	0f4eeeadfc1a360be3fd77538e6c16f4
do_imap	a942c3686c180f6e0c6806aa777ae1cd
do_eval_task	2e730eefbdec75a25465aefd45c25f2d
do_task_done	fb1117e290e23416d13dbb83b12e887e
get_job_status	8943535458d7033e2d0f84e8bc7f8482
create_job	be3d2222c3a7f3dd4a56c9c6d0e11ccb
do_raise_error	4df00f355b99dca68b2a1c90b747dff9
do_wait_for_children_task	3f86b5afa7ac4a7bb09e48644f3ae7bc
do_task_error	3820cfb906cbb96af4a9faa0ff78f985
do_outargsmap	0ba7af5f7a9200c024762134b1f3fbba
do_inargsmap	df7844372d2bbe4ed25eb616674da67c
do_branch_task	7c0a4500cd4c6fc17ef4bbf6e2ce9bbf
do_end_task	4f8bf5ab53e383ea0ae6015e6e53e375
do_wait_for_event_task	96f8161ea8f8b5b34312cd2772dadfd8
do_workflowoutargsmap	3c5647b0e1612bb1beff2694ad8bafa3
\.


--
-- TOC entry 2441 (class 0 OID 36199)
-- Dependencies: 187
-- Data for Name: _schema; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY _schema (version) FROM stdin;
9
\.


--
-- TOC entry 2442 (class 0 OID 36205)
-- Dependencies: 188
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
-13	locktype	string	f	\N
-14	locktype	string	f	\N
-14	lockvalue	string	f	\N
-13	lockvalue	string	f	\N
\.


--
-- TOC entry 2443 (class 0 OID 36212)
-- Dependencies: 189
-- Data for Name: action_outputs; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY action_outputs (action_id, name, type, optional) FROM stdin;
-9	event	event	f
1	counter	number	f
2	square	number	f
3	quotient	number	f
\.



--
-- TOC entry 2444 (class 0 OID 36219)
-- Dependencies: 190
-- Data for Name: actions; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY actions (action_id, name, type, version, wfmapcode, wfenv, rolename) FROM stdin;
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
1	add	action	0	\N	\N	\N
2	square	action	0	\N	\N	\N
3	div	action	0	\N	\N	\N
-13	lock	system	0	\N	\N	\N
-14	unlock	system	0	\N	\N	\N
\.


--
-- TOC entry 2464 (class 0 OID 36497)
-- Dependencies: 210
-- Data for Name: jc_env; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY jc_env (jcenv) FROM stdin;
{"version": "0.1"}
\.


--
-- TOC entry 2469 (class 0 OID 36807)
-- Dependencies: 218
-- Data for Name: jc_impersonate_roles; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY jc_impersonate_roles (rolename, impersonates) FROM stdin;
$JCCLIENT	deWerknemer
$JCCLIENT	theEmployee
$JCCLIENT	derArbeitnehmer
$JCCLIENT	deKlant
$JCCLIENT	theCustomer
$JCCLIENT	derKunde
\.


--
-- TOC entry 2468 (class 0 OID 36781)
-- Dependencies: 217
-- Data for Name: jc_roles; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY jc_roles (rolename) FROM stdin;
$JCCLIENT
deWerknemer
theEmployee
derArbeitnehmer
deKlant
derKunde
theCustomer
\.

--
-- TOC entry 2453 (class 0 OID 36262)
-- Dependencies: 199
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
-- TOC entry 2455 (class 0 OID 36277)
-- Dependencies: 201
-- Data for Name: locktypes; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY locktypes (locktype) FROM stdin;
foo
abc
slot
schloss
\.

--
-- TOC entry 2465 (class 0 OID 36504)
-- Dependencies: 211
-- Data for Name: version_tags; Type: TABLE DATA; Schema: jobcenter; Owner: $JCADMIN
--

COPY version_tags (tag) FROM stdin;
stable
unittest
\.

--
-- TOC entry 2231 (class 2606 OID 36332)
-- Name: _funcs_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY _procs
    ADD CONSTRAINT _funcs_pkey PRIMARY KEY (name);


--
-- TOC entry 2233 (class 2606 OID 36334)
-- Name: action_inputs_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_inputs
    ADD CONSTRAINT action_inputs_pkey PRIMARY KEY (action_id, name);


--
-- TOC entry 2235 (class 2606 OID 36336)
-- Name: action_outputs_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_outputs
    ADD CONSTRAINT action_outputs_pkey PRIMARY KEY (action_id, name);


--
-- TOC entry 2285 (class 2606 OID 36519)
-- Name: action_version_tags_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_version_tags
    ADD CONSTRAINT action_version_tags_pkey PRIMARY KEY (action_id, tag);


--
-- TOC entry 2237 (class 2606 OID 36338)
-- Name: actions_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT actions_pkey PRIMARY KEY (action_id);


--
-- TOC entry 2241 (class 2606 OID 36342)
-- Name: event_subscriptions_jobid_eventmask_ukey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_jobid_eventmask_ukey UNIQUE (job_id, mask);


--
-- TOC entry 2243 (class 2606 OID 36344)
-- Name: event_subscriptions_jobid_name_ukey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_jobid_name_ukey UNIQUE (job_id, name);


--
-- TOC entry 2245 (class 2606 OID 36346)
-- Name: event_subscriptions_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_pkey PRIMARY KEY (subscription_id);


--
-- TOC entry 2291 (class 2606 OID 36814)
-- Name: jc_impersonate_roles_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_impersonate_roles
    ADD CONSTRAINT jc_impersonate_roles_pkey PRIMARY KEY (rolename, impersonates);


--
-- TOC entry 2293 (class 2606 OID 36848)
-- Name: jc_role_members_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_role_members
    ADD CONSTRAINT jc_role_members_pkey PRIMARY KEY (rolename, member_of);


--
-- TOC entry 2289 (class 2606 OID 36788)
-- Name: jc_roles_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_roles
    ADD CONSTRAINT jc_roles_pkey PRIMARY KEY (rolename);


--
-- TOC entry 2247 (class 2606 OID 36348)
-- Name: job_events_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY job_events
    ADD CONSTRAINT job_events_pkey PRIMARY KEY (subscription_id, event_id);


--
-- TOC entry 2287 (class 2606 OID 36622)
-- Name: job_history_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs_archive
    ADD CONSTRAINT job_history_pkey PRIMARY KEY (job_id);


--
-- TOC entry 2249 (class 2606 OID 36350)
-- Name: job_step_history_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY job_task_log
    ADD CONSTRAINT job_step_history_pkey PRIMARY KEY (job_task_log_id);


--
-- TOC entry 2254 (class 2606 OID 36352)
-- Name: jobs_cookie_key; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_cookie_key UNIQUE (cookie);


--
-- TOC entry 2256 (class 2606 OID 36354)
-- Name: jobs_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_pkey PRIMARY KEY (job_id);


--
-- TOC entry 2258 (class 2606 OID 36356)
-- Name: jsonb_object_fields_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jsonb_object_fields
    ADD CONSTRAINT jsonb_object_fields_pkey PRIMARY KEY (typename);


--
-- TOC entry 2260 (class 2606 OID 36358)
-- Name: locks_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY locks
    ADD CONSTRAINT locks_pkey PRIMARY KEY (job_id, locktype, lockvalue);


--
-- TOC entry 2262 (class 2606 OID 36360)
-- Name: locks_ukey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY locks
    ADD CONSTRAINT locks_ukey UNIQUE (locktype, lockvalue);


--
-- TOC entry 2264 (class 2606 OID 36362)
-- Name: locktypes_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY locktypes
    ADD CONSTRAINT locktypes_pkey PRIMARY KEY (locktype);


--
-- TOC entry 2266 (class 2606 OID 36364)
-- Name: next_tasks_from_when_uniq; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_tasks_from_when_uniq UNIQUE (from_task_id, "when");


--
-- TOC entry 2268 (class 2606 OID 36366)
-- Name: next_tasks_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_tasks_pkey PRIMARY KEY (from_task_id, to_task_id, "when");


--
-- TOC entry 2270 (class 2606 OID 36368)
-- Name: queued_events_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY queued_events
    ADD CONSTRAINT queued_events_pkey PRIMARY KEY (event_id);


--
-- TOC entry 2272 (class 2606 OID 36370)
-- Name: steps_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT steps_pkey PRIMARY KEY (task_id);


--
-- TOC entry 2274 (class 2606 OID 36372)
-- Name: tasks_task_id_workflow_id_ukey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_task_id_workflow_id_ukey UNIQUE (workflow_id, task_id);


--
-- TOC entry 2239 (class 2606 OID 36340)
-- Name: unique_type_name_version; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT unique_type_name_version UNIQUE (type, name, version);


--
-- TOC entry 2283 (class 2606 OID 36511)
-- Name: version_tag_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY version_tags
    ADD CONSTRAINT version_tag_pkey PRIMARY KEY (tag);


--
-- TOC entry 2276 (class 2606 OID 36374)
-- Name: worker_actions_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY worker_actions
    ADD CONSTRAINT worker_actions_pkey PRIMARY KEY (worker_id, action_id);


--
-- TOC entry 2278 (class 2606 OID 36376)
-- Name: workers_pkey; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY workers
    ADD CONSTRAINT workers_pkey PRIMARY KEY (worker_id);


--
-- TOC entry 2280 (class 2606 OID 36378)
-- Name: workers_workername_stopped_key; Type: CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY workers
    ADD CONSTRAINT workers_workername_stopped_key UNIQUE (name, stopped);


--
-- TOC entry 2281 (class 1259 OID 36503)
-- Name: jcenv_uidx; Type: INDEX; Schema: jobcenter; Owner: $JCADMIN
--

CREATE UNIQUE INDEX jcenv_uidx ON jc_env USING btree ((((jcenv IS NULL) OR (jcenv IS NOT NULL))));


--
-- TOC entry 2251 (class 1259 OID 36379)
-- Name: job_actionid_index; Type: INDEX; Schema: jobcenter; Owner: $JCADMIN
--

CREATE INDEX job_actionid_index ON jobs USING btree (task_id);


--
-- TOC entry 2252 (class 1259 OID 36380)
-- Name: job_parent_jobid_index; Type: INDEX; Schema: jobcenter; Owner: $JCADMIN
--

CREATE INDEX job_parent_jobid_index ON jobs USING btree (parentjob_id);


--
-- TOC entry 2250 (class 1259 OID 36381)
-- Name: job_task_log_jobid_idx; Type: INDEX; Schema: jobcenter; Owner: $JCADMIN
--

CREATE INDEX job_task_log_jobid_idx ON job_task_log USING btree (job_id);


--
-- TOC entry 2324 (class 2620 OID 36533)
-- Name: on_job_state_change; Type: TRIGGER; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TRIGGER on_job_state_change AFTER UPDATE OF state ON jobs FOR EACH ROW WHEN (((old.state = 'waiting'::job_state) AND (new.state <> 'waiting'::job_state))) EXECUTE PROCEDURE do_clear_waiting_events();


--
-- TOC entry 2323 (class 2620 OID 36532)
-- Name: on_job_task_change; Type: TRIGGER; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TRIGGER on_job_task_change BEFORE UPDATE OF task_id ON jobs FOR EACH ROW EXECUTE PROCEDURE do_increase_stepcounter();


--
-- TOC entry 2325 (class 2620 OID 36535)
-- Name: on_jobs_timerchange; Type: TRIGGER; Schema: jobcenter; Owner: $JCADMIN
--

CREATE TRIGGER on_jobs_timerchange AFTER INSERT OR DELETE OR UPDATE OF timeout ON jobs FOR EACH STATEMENT EXECUTE PROCEDURE do_notify_timerchange();


--
-- TOC entry 2294 (class 2606 OID 36386)
-- Name: action_inputs_actionid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_inputs
    ADD CONSTRAINT action_inputs_actionid_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 2295 (class 2606 OID 36830)
-- Name: action_inputs_type_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_inputs
    ADD CONSTRAINT action_inputs_type_fkey FOREIGN KEY (type) REFERENCES jsonb_object_fields(typename) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2296 (class 2606 OID 36396)
-- Name: action_outputs_actionid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_outputs
    ADD CONSTRAINT action_outputs_actionid_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 2297 (class 2606 OID 36835)
-- Name: action_outputs_type_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_outputs
    ADD CONSTRAINT action_outputs_type_fkey FOREIGN KEY (type) REFERENCES jsonb_object_fields(typename) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2298 (class 2606 OID 36825)
-- Name: action_rolename_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY actions
    ADD CONSTRAINT action_rolename_fkey FOREIGN KEY (rolename) REFERENCES jc_roles(rolename) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2316 (class 2606 OID 36520)
-- Name: action_version_tags_action_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_version_tags
    ADD CONSTRAINT action_version_tags_action_id_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON DELETE CASCADE;


--
-- TOC entry 2317 (class 2606 OID 36525)
-- Name: action_version_tags_tag_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY action_version_tags
    ADD CONSTRAINT action_version_tags_tag_fkey FOREIGN KEY (tag) REFERENCES version_tags(tag) ON DELETE CASCADE;


--
-- TOC entry 2299 (class 2606 OID 36406)
-- Name: event_subscriptions_job_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY event_subscriptions
    ADD CONSTRAINT event_subscriptions_job_id_fkey FOREIGN KEY (job_id) REFERENCES jobs(job_id);


--
-- TOC entry 2319 (class 2606 OID 36815)
-- Name: jc_impersonate_roles_impersonates_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_impersonate_roles
    ADD CONSTRAINT jc_impersonate_roles_impersonates_fkey FOREIGN KEY (impersonates) REFERENCES jc_roles(rolename) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 2320 (class 2606 OID 36820)
-- Name: jc_impersonate_roles_rolename_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_impersonate_roles
    ADD CONSTRAINT jc_impersonate_roles_rolename_fkey FOREIGN KEY (rolename) REFERENCES jc_roles(rolename) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 2321 (class 2606 OID 36849)
-- Name: jc_role_members_member_of_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_role_members
    ADD CONSTRAINT jc_role_members_member_of_fkey FOREIGN KEY (member_of) REFERENCES jc_roles(rolename) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 2322 (class 2606 OID 36854)
-- Name: jc_role_members_rolename_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jc_role_members
    ADD CONSTRAINT jc_role_members_rolename_fkey FOREIGN KEY (rolename) REFERENCES jc_roles(rolename) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 2300 (class 2606 OID 36411)
-- Name: job_events_eventid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY job_events
    ADD CONSTRAINT job_events_eventid_fkey FOREIGN KEY (event_id) REFERENCES queued_events(event_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 2301 (class 2606 OID 36416)
-- Name: job_events_subscriptionid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY job_events
    ADD CONSTRAINT job_events_subscriptionid_fkey FOREIGN KEY (subscription_id) REFERENCES event_subscriptions(subscription_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 2318 (class 2606 OID 36623)
-- Name: job_history_workflowid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs_archive
    ADD CONSTRAINT job_history_workflowid_fkey FOREIGN KEY (workflow_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2302 (class 2606 OID 36421)
-- Name: jobs_parent_jobid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_parent_jobid_fkey FOREIGN KEY (parentjob_id) REFERENCES jobs(job_id);


--
-- TOC entry 2303 (class 2606 OID 36426)
-- Name: jobs_taskid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_taskid_fkey FOREIGN KEY (workflow_id, task_id) REFERENCES tasks(workflow_id, task_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2304 (class 2606 OID 36436)
-- Name: jobs_workflowid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY jobs
    ADD CONSTRAINT jobs_workflowid_fkey FOREIGN KEY (workflow_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2305 (class 2606 OID 36441)
-- Name: locks_job_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY locks
    ADD CONSTRAINT locks_job_id_fkey FOREIGN KEY (job_id) REFERENCES jobs(job_id);


--
-- TOC entry 2306 (class 2606 OID 36446)
-- Name: locks_locktype_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY locks
    ADD CONSTRAINT locks_locktype_fkey FOREIGN KEY (locktype) REFERENCES locktypes(locktype);


--
-- TOC entry 2307 (class 2606 OID 36451)
-- Name: next_task_from_task_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_task_from_task_id_fkey FOREIGN KEY (from_task_id) REFERENCES tasks(task_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 2308 (class 2606 OID 36456)
-- Name: next_task_to_task_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY next_tasks
    ADD CONSTRAINT next_task_to_task_id_fkey FOREIGN KEY (to_task_id) REFERENCES tasks(task_id) ON UPDATE CASCADE ON DELETE CASCADE;


--
-- TOC entry 2309 (class 2606 OID 36461)
-- Name: task_next_task_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT task_next_task_fkey FOREIGN KEY (next_task_id) REFERENCES tasks(task_id);


--
-- TOC entry 2310 (class 2606 OID 36466)
-- Name: task_on_error_task_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT task_on_error_task_fkey FOREIGN KEY (on_error_task_id) REFERENCES tasks(task_id);


--
-- TOC entry 2311 (class 2606 OID 36471)
-- Name: tasks_actionid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_actionid_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2312 (class 2606 OID 36476)
-- Name: tasks_wait_for_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_wait_for_fkey FOREIGN KEY (reapfromtask_id) REFERENCES tasks(task_id);


--
-- TOC entry 2313 (class 2606 OID 36481)
-- Name: tasks_workflowid_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY tasks
    ADD CONSTRAINT tasks_workflowid_fkey FOREIGN KEY (workflow_id) REFERENCES actions(action_id) ON UPDATE CASCADE ON DELETE RESTRICT;


--
-- TOC entry 2314 (class 2606 OID 36486)
-- Name: worker_actions_action_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY worker_actions
    ADD CONSTRAINT worker_actions_action_id_fkey FOREIGN KEY (action_id) REFERENCES actions(action_id);


--
-- TOC entry 2315 (class 2606 OID 36491)
-- Name: worker_actions_worker_id_fkey; Type: FK CONSTRAINT; Schema: jobcenter; Owner: $JCADMIN
--

ALTER TABLE ONLY worker_actions
    ADD CONSTRAINT worker_actions_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES workers(worker_id) ON DELETE CASCADE;


--
-- TOC entry 2475 (class 0 OID 0)
-- Dependencies: 8
-- Name: jobcenter; Type: ACL; Schema: -; Owner: $JCADMIN
--

REVOKE ALL ON SCHEMA jobcenter FROM PUBLIC;
REVOKE ALL ON SCHEMA jobcenter FROM $JCADMIN;
GRANT ALL ON SCHEMA jobcenter TO $JCADMIN;
GRANT USAGE ON SCHEMA jobcenter TO $JCCLIENT;
GRANT USAGE ON SCHEMA jobcenter TO jc_maestro;
GRANT ALL ON SCHEMA jobcenter TO $JCSYSTEM;
GRANT ALL ON SCHEMA jobcenter TO $JCPERL;


--
-- TOC entry 2477 (class 0 OID 0)
-- Dependencies: 253
-- Name: announce(text, text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION announce(workername text, actionname text, impersonate text) FROM PUBLIC;
REVOKE ALL ON FUNCTION announce(workername text, actionname text, impersonate text) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION announce(workername text, actionname text, impersonate text) TO $JCSYSTEM;
GRANT ALL ON FUNCTION announce(workername text, actionname text, impersonate text) TO $JCCLIENT;


--
-- TOC entry 2478 (class 0 OID 0)
-- Dependencies: 269
-- Name: create_job(text, jsonb, text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION create_job(wfname text, args jsonb, tag text, impersonate text) FROM PUBLIC;
REVOKE ALL ON FUNCTION create_job(wfname text, args jsonb, tag text, impersonate text) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION create_job(wfname text, args jsonb, tag text, impersonate text) TO $JCSYSTEM;
GRANT ALL ON FUNCTION create_job(wfname text, args jsonb, tag text, impersonate text) TO $JCCLIENT;


--
-- TOC entry 2479 (class 0 OID 0)
-- Dependencies: 261
-- Name: do_archival_and_cleanup(text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_archival_and_cleanup(dummy text) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_archival_and_cleanup(dummy text) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_archival_and_cleanup(dummy text) TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_archival_and_cleanup(dummy text) TO jc_maestro;


--
-- TOC entry 2480 (class 0 OID 0)
-- Dependencies: 279
-- Name: do_boolcode(text, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_boolcode(code text, args jsonb, env jsonb, vars jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_boolcode(code text, args jsonb, env jsonb, vars jsonb) FROM $JCPERL;
GRANT ALL ON FUNCTION do_boolcode(code text, args jsonb, env jsonb, vars jsonb) TO $JCPERL;


--
-- TOC entry 2481 (class 0 OID 0)
-- Dependencies: 258
-- Name: do_branch_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_branch_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_branch_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_branch_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2482 (class 0 OID 0)
-- Dependencies: 241
-- Name: do_call_stored_procedure(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_call_stored_procedure(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_call_stored_procedure(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_call_stored_procedure(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2483 (class 0 OID 0)
-- Dependencies: 271
-- Name: do_check_job_is_waiting(bigint, boolean); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_check_job_is_waiting(bigint, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_check_job_is_waiting(bigint, boolean) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_check_job_is_waiting(bigint, boolean) TO $JCSYSTEM;


--
-- TOC entry 2484 (class 0 OID 0)
-- Dependencies: 288
-- Name: do_check_role_membership(text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_check_role_membership(a_have_role text, a_should_role text) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_check_role_membership(a_have_role text, a_should_role text) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_check_role_membership(a_have_role text, a_should_role text) TO $JCSYSTEM;


--
-- TOC entry 2485 (class 0 OID 0)
-- Dependencies: 272
-- Name: do_check_same_workflow(integer, integer); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_check_same_workflow(a_task1_id integer, a_task2_id integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_check_same_workflow(a_task1_id integer, a_task2_id integer) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_check_same_workflow(a_task1_id integer, a_task2_id integer) TO $JCSYSTEM;


--
-- TOC entry 2486 (class 0 OID 0)
-- Dependencies: 247
-- Name: do_check_wait(integer, boolean); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_check_wait(a_action_id integer, a_wait boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_check_wait(a_action_id integer, a_wait boolean) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_check_wait(a_action_id integer, a_wait boolean) TO $JCSYSTEM;


--
-- TOC entry 2488 (class 0 OID 0)
-- Dependencies: 248
-- Name: do_check_wait_for_task(integer, integer); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_check_wait_for_task(a_action_id integer, a_wait_for_task integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_check_wait_for_task(a_action_id integer, a_wait_for_task integer) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_check_wait_for_task(a_action_id integer, a_wait_for_task integer) TO $JCSYSTEM;


--
-- TOC entry 2489 (class 0 OID 0)
-- Dependencies: 257
-- Name: do_cleanup_on_finish(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_cleanup_on_finish(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_cleanup_on_finish(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_cleanup_on_finish(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2490 (class 0 OID 0)
-- Dependencies: 281
-- Name: do_cleanup_on_finish_trigger(); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_cleanup_on_finish_trigger() FROM PUBLIC;
REVOKE ALL ON FUNCTION do_cleanup_on_finish_trigger() FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_cleanup_on_finish_trigger() TO $JCSYSTEM;


--
-- TOC entry 2491 (class 0 OID 0)
-- Dependencies: 270
-- Name: do_clear_waiting_events(); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_clear_waiting_events() FROM PUBLIC;
REVOKE ALL ON FUNCTION do_clear_waiting_events() FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_clear_waiting_events() TO $JCSYSTEM;


--
-- TOC entry 2492 (class 0 OID 0)
-- Dependencies: 239
-- Name: do_create_childjob(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_create_childjob(a_parentjobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_create_childjob(a_parentjobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_create_childjob(a_parentjobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2493 (class 0 OID 0)
-- Dependencies: 290
-- Name: do_end_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_end_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_end_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_end_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2494 (class 0 OID 0)
-- Dependencies: 235
-- Name: do_eval(text, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_eval(code text, args jsonb, env jsonb, vars jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_eval(code text, args jsonb, env jsonb, vars jsonb) FROM $JCPERL;
GRANT ALL ON FUNCTION do_eval(code text, args jsonb, env jsonb, vars jsonb) TO $JCPERL;


--
-- TOC entry 2495 (class 0 OID 0)
-- Dependencies: 242
-- Name: do_eval_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_eval_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_eval_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_eval_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2496 (class 0 OID 0)
-- Dependencies: 264
-- Name: do_imap(text, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_imap(code text, args jsonb, env jsonb, vars jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_imap(code text, args jsonb, env jsonb, vars jsonb) FROM $JCPERL;
GRANT ALL ON FUNCTION do_imap(code text, args jsonb, env jsonb, vars jsonb) TO $JCPERL;


--
-- TOC entry 2497 (class 0 OID 0)
-- Dependencies: 254
-- Name: do_inargsmap(integer, integer, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_inargsmap(a_action_id integer, a_task_id integer, a_args jsonb, a_env jsonb, a_vars jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_inargsmap(a_action_id integer, a_task_id integer, a_args jsonb, a_env jsonb, a_vars jsonb) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_inargsmap(a_action_id integer, a_task_id integer, a_args jsonb, a_env jsonb, a_vars jsonb) TO $JCSYSTEM;


--
-- TOC entry 2498 (class 0 OID 0)
-- Dependencies: 276
-- Name: do_increase_stepcounter(); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_increase_stepcounter() FROM PUBLIC;
REVOKE ALL ON FUNCTION do_increase_stepcounter() FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_increase_stepcounter() TO $JCSYSTEM;


--
-- TOC entry 2499 (class 0 OID 0)
-- Dependencies: 278
-- Name: do_is_action(integer); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_is_action(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_is_action(integer) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_is_action(integer) TO $JCSYSTEM;


--
-- TOC entry 2500 (class 0 OID 0)
-- Dependencies: 277
-- Name: do_is_workflow(integer); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_is_workflow(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_is_workflow(integer) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_is_workflow(integer) TO $JCSYSTEM;


--
-- TOC entry 2501 (class 0 OID 0)
-- Dependencies: 260
-- Name: do_jobtask(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_jobtask(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_jobtask(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_jobtask(a_jobtask jobtask) TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_jobtask(a_jobtask jobtask) TO jc_maestro;


--
-- TOC entry 2502 (class 0 OID 0)
-- Dependencies: 282
-- Name: do_jobtaskdone(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_jobtaskdone(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_jobtaskdone(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_jobtaskdone(a_jobtask jobtask) TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_jobtaskdone(a_jobtask jobtask) TO jc_maestro;


--
-- TOC entry 2503 (class 0 OID 0)
-- Dependencies: 262
-- Name: do_jobtaskerror(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_jobtaskerror(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_jobtaskerror(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_jobtaskerror(a_jobtask jobtask) TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_jobtaskerror(a_jobtask jobtask) TO jc_maestro;


--
-- TOC entry 2504 (class 0 OID 0)
-- Dependencies: 265
-- Name: do_lock_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_lock_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_lock_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_lock_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2505 (class 0 OID 0)
-- Dependencies: 266
-- Name: do_log(bigint, boolean, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_log(a_job_id bigint, a_logvars boolean, a_inargs jsonb, a_outargs jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_log(a_job_id bigint, a_logvars boolean, a_inargs jsonb, a_outargs jsonb) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_log(a_job_id bigint, a_logvars boolean, a_inargs jsonb, a_outargs jsonb) TO $JCSYSTEM;


--
-- TOC entry 2506 (class 0 OID 0)
-- Dependencies: 274
-- Name: do_notify_timerchange(); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_notify_timerchange() FROM PUBLIC;
REVOKE ALL ON FUNCTION do_notify_timerchange() FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_notify_timerchange() TO $JCSYSTEM;


--
-- TOC entry 2507 (class 0 OID 0)
-- Dependencies: 233
-- Name: do_omap(text, jsonb, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_omap(code text, args jsonb, env jsonb, vars jsonb, oargs jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_omap(code text, args jsonb, env jsonb, vars jsonb, oargs jsonb) FROM $JCPERL;
GRANT ALL ON FUNCTION do_omap(code text, args jsonb, env jsonb, vars jsonb, oargs jsonb) TO $JCPERL;


--
-- TOC entry 2508 (class 0 OID 0)
-- Dependencies: 236
-- Name: do_outargsmap(jobtask, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_outargsmap(a_jobtask jobtask, a_outargs jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_outargsmap(a_jobtask jobtask, a_outargs jsonb) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_outargsmap(a_jobtask jobtask, a_outargs jsonb) TO $JCSYSTEM;


--
-- TOC entry 2509 (class 0 OID 0)
-- Dependencies: 273
-- Name: do_ping(bigint); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_ping(a_worker_id bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_ping(a_worker_id bigint) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_ping(a_worker_id bigint) TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_ping(a_worker_id bigint) TO jc_maestro;


--
-- TOC entry 2510 (class 0 OID 0)
-- Dependencies: 283
-- Name: do_prepare_for_action(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_prepare_for_action(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_prepare_for_action(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_prepare_for_action(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2511 (class 0 OID 0)
-- Dependencies: 289
-- Name: do_raise_error(jobtask, text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_raise_error(a_jobtask jobtask, a_errmsg text, a_class text) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_raise_error(a_jobtask jobtask, a_errmsg text, a_class text) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_raise_error(a_jobtask jobtask, a_errmsg text, a_class text) TO $JCSYSTEM;


--
-- TOC entry 2512 (class 0 OID 0)
-- Dependencies: 243
-- Name: do_raise_error_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_raise_error_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_raise_error_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_raise_error_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2513 (class 0 OID 0)
-- Dependencies: 245
-- Name: do_raise_event_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_raise_event_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_raise_event_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_raise_event_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2514 (class 0 OID 0)
-- Dependencies: 249
-- Name: do_reap_child_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_reap_child_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_reap_child_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_reap_child_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2515 (class 0 OID 0)
-- Dependencies: 280
-- Name: do_sanity_check_workflow(integer); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_sanity_check_workflow(a_workflow_id integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_sanity_check_workflow(a_workflow_id integer) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_sanity_check_workflow(a_workflow_id integer) TO $JCSYSTEM;


--
-- TOC entry 2516 (class 0 OID 0)
-- Dependencies: 267
-- Name: do_stringcode(text, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_stringcode(code text, args jsonb, env jsonb, vars jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_stringcode(code text, args jsonb, env jsonb, vars jsonb) FROM $JCPERL;
GRANT ALL ON FUNCTION do_stringcode(code text, args jsonb, env jsonb, vars jsonb) TO $JCPERL;


--
-- TOC entry 2517 (class 0 OID 0)
-- Dependencies: 246
-- Name: do_subscribe_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_subscribe_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_subscribe_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_subscribe_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2518 (class 0 OID 0)
-- Dependencies: 251
-- Name: do_switch_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_switch_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_switch_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_switch_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2519 (class 0 OID 0)
-- Dependencies: 284
-- Name: do_task_done(jobtask, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_task_done(a_jobtask jobtask, a_outargs jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_task_done(a_jobtask jobtask, a_outargs jsonb) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_task_done(a_jobtask jobtask, a_outargs jsonb) TO $JCSYSTEM;


--
-- TOC entry 2520 (class 0 OID 0)
-- Dependencies: 250
-- Name: do_task_epilogue(jobtask, boolean, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_task_epilogue(a_jobtask jobtask, a_vars_changed boolean, a_newvars jsonb, a_inargs jsonb, a_outargs jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_task_epilogue(a_jobtask jobtask, a_vars_changed boolean, a_newvars jsonb, a_inargs jsonb, a_outargs jsonb) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_task_epilogue(a_jobtask jobtask, a_vars_changed boolean, a_newvars jsonb, a_inargs jsonb, a_outargs jsonb) TO $JCSYSTEM;


--
-- TOC entry 2521 (class 0 OID 0)
-- Dependencies: 268
-- Name: do_task_error(jobtask, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_task_error(a_jobtask jobtask, a_errargs jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_task_error(a_jobtask jobtask, a_errargs jsonb) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_task_error(a_jobtask jobtask, a_errargs jsonb) TO $JCSYSTEM;


--
-- TOC entry 2522 (class 0 OID 0)
-- Dependencies: 263
-- Name: do_timeout(); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_timeout() FROM PUBLIC;
REVOKE ALL ON FUNCTION do_timeout() FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_timeout() TO $JCSYSTEM;
GRANT ALL ON FUNCTION do_timeout() TO jc_maestro;


--
-- TOC entry 2523 (class 0 OID 0)
-- Dependencies: 232
-- Name: do_unlock(text, text, integer, bigint, bigint, bigint); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_unlock(a_locktype text, a_lockvalue text, a_contended integer, a_job_id bigint, a_parentjob_id bigint, a_top_level_job_id bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_unlock(a_locktype text, a_lockvalue text, a_contended integer, a_job_id bigint, a_parentjob_id bigint, a_top_level_job_id bigint) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_unlock(a_locktype text, a_lockvalue text, a_contended integer, a_job_id bigint, a_parentjob_id bigint, a_top_level_job_id bigint) TO $JCSYSTEM;


--
-- TOC entry 2524 (class 0 OID 0)
-- Dependencies: 259
-- Name: do_unlock_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_unlock_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_unlock_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_unlock_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2525 (class 0 OID 0)
-- Dependencies: 285
-- Name: do_unsubscribe_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_unsubscribe_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_unsubscribe_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_unsubscribe_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2526 (class 0 OID 0)
-- Dependencies: 255
-- Name: do_wait_for_children_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_wait_for_children_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_wait_for_children_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_wait_for_children_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2527 (class 0 OID 0)
-- Dependencies: 291
-- Name: do_wait_for_event_task(jobtask); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_wait_for_event_task(a_jobtask jobtask) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_wait_for_event_task(a_jobtask jobtask) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_wait_for_event_task(a_jobtask jobtask) TO $JCSYSTEM;


--
-- TOC entry 2528 (class 0 OID 0)
-- Dependencies: 238
-- Name: do_wfomap(text, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCPERL
--

REVOKE ALL ON FUNCTION do_wfomap(code text, args jsonb, env jsonb, vars jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_wfomap(code text, args jsonb, env jsonb, vars jsonb) FROM $JCPERL;
GRANT ALL ON FUNCTION do_wfomap(code text, args jsonb, env jsonb, vars jsonb) TO $JCPERL;


--
-- TOC entry 2529 (class 0 OID 0)
-- Dependencies: 240
-- Name: do_workflowoutargsmap(integer, jsonb, jsonb, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION do_workflowoutargsmap(a_workflow_id integer, a_args jsonb, a_env jsonb, a_vars jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION do_workflowoutargsmap(a_workflow_id integer, a_args jsonb, a_env jsonb, a_vars jsonb) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION do_workflowoutargsmap(a_workflow_id integer, a_args jsonb, a_env jsonb, a_vars jsonb) TO $JCSYSTEM;


--
-- TOC entry 2530 (class 0 OID 0)
-- Dependencies: 237
-- Name: get_job_status(bigint); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION get_job_status(a_job_id bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_job_status(a_job_id bigint) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION get_job_status(a_job_id bigint) TO $JCSYSTEM;
GRANT ALL ON FUNCTION get_job_status(a_job_id bigint) TO $JCCLIENT;


--
-- TOC entry 2531 (class 0 OID 0)
-- Dependencies: 252
-- Name: get_task(text, text, bigint, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION get_task(a_workername text, a_actionname text, a_job_id bigint, a_pattern jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION get_task(a_workername text, a_actionname text, a_job_id bigint, a_pattern jsonb) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION get_task(a_workername text, a_actionname text, a_job_id bigint, a_pattern jsonb) TO $JCSYSTEM;
GRANT ALL ON FUNCTION get_task(a_workername text, a_actionname text, a_job_id bigint, a_pattern jsonb) TO $JCCLIENT;


--
-- TOC entry 2532 (class 0 OID 0)
-- Dependencies: 275
-- Name: ping(bigint); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION ping(a_worker_id bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION ping(a_worker_id bigint) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION ping(a_worker_id bigint) TO $JCSYSTEM;
GRANT ALL ON FUNCTION ping(a_worker_id bigint) TO $JCCLIENT;


--
-- TOC entry 2533 (class 0 OID 0)
-- Dependencies: 286
-- Name: raise_event(jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION raise_event(a_eventdata jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION raise_event(a_eventdata jsonb) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION raise_event(a_eventdata jsonb) TO $JCSYSTEM;
GRANT ALL ON FUNCTION raise_event(a_eventdata jsonb) TO $JCCLIENT;


--
-- TOC entry 2534 (class 0 OID 0)
-- Dependencies: 256
-- Name: task_done(text, jsonb); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION task_done(a_jobcookie text, a_out_args jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION task_done(a_jobcookie text, a_out_args jsonb) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION task_done(a_jobcookie text, a_out_args jsonb) TO $JCSYSTEM;
GRANT ALL ON FUNCTION task_done(a_jobcookie text, a_out_args jsonb) TO $JCCLIENT;


--
-- TOC entry 2535 (class 0 OID 0)
-- Dependencies: 244
-- Name: task_failed(text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION task_failed(a_cookie text, a_errmsg text) FROM PUBLIC;
REVOKE ALL ON FUNCTION task_failed(a_cookie text, a_errmsg text) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION task_failed(a_cookie text, a_errmsg text) TO $JCSYSTEM;
GRANT ALL ON FUNCTION task_failed(a_cookie text, a_errmsg text) TO $JCCLIENT;


--
-- TOC entry 2536 (class 0 OID 0)
-- Dependencies: 287
-- Name: withdraw(text, text); Type: ACL; Schema: jobcenter; Owner: $JCSYSTEM
--

REVOKE ALL ON FUNCTION withdraw(a_workername text, a_actionname text) FROM PUBLIC;
REVOKE ALL ON FUNCTION withdraw(a_workername text, a_actionname text) FROM $JCSYSTEM;
GRANT ALL ON FUNCTION withdraw(a_workername text, a_actionname text) TO $JCSYSTEM;
GRANT ALL ON FUNCTION withdraw(a_workername text, a_actionname text) TO $JCCLIENT;


--
-- TOC entry 2537 (class 0 OID 0)
-- Dependencies: 186
-- Name: _procs; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE _procs FROM PUBLIC;
REVOKE ALL ON TABLE _procs FROM $JCADMIN;
GRANT ALL ON TABLE _procs TO $JCADMIN;


--
-- TOC entry 2538 (class 0 OID 0)
-- Dependencies: 188
-- Name: action_inputs; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE action_inputs FROM PUBLIC;
REVOKE ALL ON TABLE action_inputs FROM $JCADMIN;
GRANT ALL ON TABLE action_inputs TO $JCADMIN;
GRANT SELECT ON TABLE action_inputs TO $JCSYSTEM;


--
-- TOC entry 2539 (class 0 OID 0)
-- Dependencies: 189
-- Name: action_outputs; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE action_outputs FROM PUBLIC;
REVOKE ALL ON TABLE action_outputs FROM $JCADMIN;
GRANT ALL ON TABLE action_outputs TO $JCADMIN;
GRANT SELECT ON TABLE action_outputs TO $JCSYSTEM;


--
-- TOC entry 2540 (class 0 OID 0)
-- Dependencies: 212
-- Name: action_version_tags; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE action_version_tags FROM PUBLIC;
REVOKE ALL ON TABLE action_version_tags FROM $JCADMIN;
GRANT ALL ON TABLE action_version_tags TO $JCADMIN;
GRANT SELECT ON TABLE action_version_tags TO $JCSYSTEM;


--
-- TOC entry 2541 (class 0 OID 0)
-- Dependencies: 190
-- Name: actions; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE actions FROM PUBLIC;
REVOKE ALL ON TABLE actions FROM $JCADMIN;
GRANT ALL ON TABLE actions TO $JCADMIN;
GRANT SELECT ON TABLE actions TO $JCSYSTEM;


--
-- TOC entry 2543 (class 0 OID 0)
-- Dependencies: 191
-- Name: actions_actionid_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON SEQUENCE actions_actionid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE actions_actionid_seq FROM $JCADMIN;
GRANT ALL ON SEQUENCE actions_actionid_seq TO $JCADMIN;


--
-- TOC entry 2544 (class 0 OID 0)
-- Dependencies: 192
-- Name: event_subscriptions; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE event_subscriptions FROM PUBLIC;
REVOKE ALL ON TABLE event_subscriptions FROM $JCADMIN;
GRANT ALL ON TABLE event_subscriptions TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE event_subscriptions TO $JCSYSTEM;


--
-- TOC entry 2546 (class 0 OID 0)
-- Dependencies: 193
-- Name: event_subscriptions_subscription_id_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON SEQUENCE event_subscriptions_subscription_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE event_subscriptions_subscription_id_seq FROM $JCADMIN;
GRANT ALL ON SEQUENCE event_subscriptions_subscription_id_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE event_subscriptions_subscription_id_seq TO $JCSYSTEM;


--
-- TOC entry 2547 (class 0 OID 0)
-- Dependencies: 210
-- Name: jc_env; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE jc_env FROM PUBLIC;
REVOKE ALL ON TABLE jc_env FROM $JCADMIN;
GRANT ALL ON TABLE jc_env TO $JCADMIN;
GRANT SELECT ON TABLE jc_env TO $JCSYSTEM;


--
-- TOC entry 2548 (class 0 OID 0)
-- Dependencies: 218
-- Name: jc_impersonate_roles; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE jc_impersonate_roles FROM PUBLIC;
REVOKE ALL ON TABLE jc_impersonate_roles FROM $JCADMIN;
GRANT ALL ON TABLE jc_impersonate_roles TO $JCADMIN;
GRANT SELECT ON TABLE jc_impersonate_roles TO $JCSYSTEM;


--
-- TOC entry 2549 (class 0 OID 0)
-- Dependencies: 219
-- Name: jc_role_members; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE jc_role_members FROM PUBLIC;
REVOKE ALL ON TABLE jc_role_members FROM $JCADMIN;
GRANT ALL ON TABLE jc_role_members TO $JCADMIN;
GRANT SELECT ON TABLE jc_role_members TO $JCSYSTEM;


--
-- TOC entry 2550 (class 0 OID 0)
-- Dependencies: 217
-- Name: jc_roles; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE jc_roles FROM PUBLIC;
REVOKE ALL ON TABLE jc_roles FROM $JCADMIN;
GRANT ALL ON TABLE jc_roles TO $JCADMIN;
GRANT SELECT ON TABLE jc_roles TO $JCSYSTEM;


--
-- TOC entry 2551 (class 0 OID 0)
-- Dependencies: 194
-- Name: job_events; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE job_events FROM PUBLIC;
REVOKE ALL ON TABLE job_events FROM $JCADMIN;
GRANT ALL ON TABLE job_events TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE job_events TO $JCSYSTEM;


--
-- TOC entry 2553 (class 0 OID 0)
-- Dependencies: 195
-- Name: job_task_log; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE job_task_log FROM PUBLIC;
REVOKE ALL ON TABLE job_task_log FROM $JCADMIN;
GRANT ALL ON TABLE job_task_log TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE job_task_log TO $JCSYSTEM;


--
-- TOC entry 2555 (class 0 OID 0)
-- Dependencies: 196
-- Name: job_task_log_job_task_log_id_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON SEQUENCE job_task_log_job_task_log_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE job_task_log_job_task_log_id_seq FROM $JCADMIN;
GRANT ALL ON SEQUENCE job_task_log_job_task_log_id_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE job_task_log_job_task_log_id_seq TO $JCSYSTEM;


--
-- TOC entry 2556 (class 0 OID 0)
-- Dependencies: 197
-- Name: jobs; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE jobs FROM PUBLIC;
REVOKE ALL ON TABLE jobs FROM $JCADMIN;
GRANT ALL ON TABLE jobs TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE jobs TO $JCSYSTEM;


--
-- TOC entry 2557 (class 0 OID 0)
-- Dependencies: 216
-- Name: jobs_archive; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE jobs_archive FROM PUBLIC;
REVOKE ALL ON TABLE jobs_archive FROM $JCADMIN;
GRANT ALL ON TABLE jobs_archive TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE jobs_archive TO $JCSYSTEM;


--
-- TOC entry 2559 (class 0 OID 0)
-- Dependencies: 198
-- Name: jobs_jobid_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON SEQUENCE jobs_jobid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE jobs_jobid_seq FROM $JCADMIN;
GRANT ALL ON SEQUENCE jobs_jobid_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE jobs_jobid_seq TO $JCSYSTEM;


--
-- TOC entry 2560 (class 0 OID 0)
-- Dependencies: 199
-- Name: jsonb_object_fields; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE jsonb_object_fields FROM PUBLIC;
REVOKE ALL ON TABLE jsonb_object_fields FROM $JCADMIN;
GRANT ALL ON TABLE jsonb_object_fields TO $JCADMIN;
GRANT SELECT ON TABLE jsonb_object_fields TO $JCSYSTEM;


--
-- TOC entry 2561 (class 0 OID 0)
-- Dependencies: 200
-- Name: locks; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE locks FROM PUBLIC;
REVOKE ALL ON TABLE locks FROM $JCADMIN;
GRANT ALL ON TABLE locks TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE locks TO $JCSYSTEM;


--
-- TOC entry 2562 (class 0 OID 0)
-- Dependencies: 201
-- Name: locktypes; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE locktypes FROM PUBLIC;
REVOKE ALL ON TABLE locktypes FROM $JCADMIN;
GRANT ALL ON TABLE locktypes TO $JCADMIN;
GRANT SELECT ON TABLE locktypes TO $JCSYSTEM;


--
-- TOC entry 2563 (class 0 OID 0)
-- Dependencies: 202
-- Name: next_tasks; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE next_tasks FROM PUBLIC;
REVOKE ALL ON TABLE next_tasks FROM $JCADMIN;
GRANT ALL ON TABLE next_tasks TO $JCADMIN;
GRANT SELECT ON TABLE next_tasks TO $JCSYSTEM;


--
-- TOC entry 2564 (class 0 OID 0)
-- Dependencies: 203
-- Name: queued_events; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE queued_events FROM PUBLIC;
REVOKE ALL ON TABLE queued_events FROM $JCADMIN;
GRANT ALL ON TABLE queued_events TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE queued_events TO $JCSYSTEM;


--
-- TOC entry 2566 (class 0 OID 0)
-- Dependencies: 204
-- Name: queued_events_event_id_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON SEQUENCE queued_events_event_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE queued_events_event_id_seq FROM $JCADMIN;
GRANT ALL ON SEQUENCE queued_events_event_id_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE queued_events_event_id_seq TO $JCSYSTEM;


--
-- TOC entry 2567 (class 0 OID 0)
-- Dependencies: 205
-- Name: tasks; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE tasks FROM PUBLIC;
REVOKE ALL ON TABLE tasks FROM $JCADMIN;
GRANT ALL ON TABLE tasks TO $JCADMIN;
GRANT ALL ON TABLE tasks TO $JCSYSTEM;


--
-- TOC entry 2569 (class 0 OID 0)
-- Dependencies: 206
-- Name: tasks_taskid_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON SEQUENCE tasks_taskid_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE tasks_taskid_seq FROM $JCADMIN;
GRANT ALL ON SEQUENCE tasks_taskid_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE tasks_taskid_seq TO $JCSYSTEM;


--
-- TOC entry 2570 (class 0 OID 0)
-- Dependencies: 211
-- Name: version_tags; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE version_tags FROM PUBLIC;
REVOKE ALL ON TABLE version_tags FROM $JCADMIN;
GRANT ALL ON TABLE version_tags TO $JCADMIN;
GRANT SELECT ON TABLE version_tags TO $JCSYSTEM;


--
-- TOC entry 2571 (class 0 OID 0)
-- Dependencies: 207
-- Name: worker_actions; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE worker_actions FROM PUBLIC;
REVOKE ALL ON TABLE worker_actions FROM $JCADMIN;
GRANT ALL ON TABLE worker_actions TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE worker_actions TO $JCSYSTEM;


--
-- TOC entry 2572 (class 0 OID 0)
-- Dependencies: 208
-- Name: workers; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON TABLE workers FROM PUBLIC;
REVOKE ALL ON TABLE workers FROM $JCADMIN;
GRANT ALL ON TABLE workers TO $JCADMIN;
GRANT SELECT,INSERT,DELETE,TRUNCATE,UPDATE ON TABLE workers TO $JCSYSTEM;


--
-- TOC entry 2574 (class 0 OID 0)
-- Dependencies: 209
-- Name: workers_worker_id_seq; Type: ACL; Schema: jobcenter; Owner: $JCADMIN
--

REVOKE ALL ON SEQUENCE workers_worker_id_seq FROM PUBLIC;
REVOKE ALL ON SEQUENCE workers_worker_id_seq FROM $JCADMIN;
GRANT ALL ON SEQUENCE workers_worker_id_seq TO $JCADMIN;
GRANT ALL ON SEQUENCE workers_worker_id_seq TO $JCSYSTEM;


-- Completed on 2016-09-05 14:48:03 CEST

--
-- PostgreSQL database dump complete
--

