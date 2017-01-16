
DO $BODY$
DECLARE
	v_roles text[] := array[
		'$JCSYSTEM',
		'$JCADMIN',
		'$JCPERL',
		'$JCCLIENT'
	];
	v_tables text[] := array[
		'_procs',
		'_schema',
		'action_inputs',
		'action_outputs',
		'action_version_tags',
		'actions',
		'event_subscriptions',
		'jc_env',
		'jc_impersonate_roles',
		'jc_role_members',
		'jc_roles',
		'job_events',
		'job_task_log',
		'jobs',
		'jobs_archive',
		'json_schemas',
		'locks',
		'locktypes',
		'next_tasks',
		'queued_events',
		'tasks',
		'version_tags',
		'worker_actions',
		'workers'
	];
	v_sequences text[] := array[
		'tasks_taskid_seq',
		'queued_events_event_id_seq',
		'event_subscriptions_subscription_id_seq',
		'actions_actionid_seq',
		'workers_worker_id_seq',
		'jobs_jobid_seq',
		'job_task_log_job_task_log_id_seq'
	];
	v_triggers text[] := array[
		'on_job_task_change',
		'on_job_state_change',
		'on_jobs_timerchange'
	];
	v_i text;
BEGIN
	FOREACH v_i IN ARRAY v_roles LOOP
		ASSERT (SELECT EXISTS(
			SELECT
				true
			FROM
				information_schema.enabled_roles
			WHERE
				role_name = v_i
		)), FORMAT('no role %s?', v_i);
	END LOOP;
	FOREACH v_i IN ARRAY v_tables LOOP
		ASSERT (SELECT EXISTS(
			SELECT
				true
			FROM
				information_schema.tables
			WHERE
				table_schema = 'jobcenter'
				AND table_name = v_i
		)), FORMAT('no table %s?', v_i);
	END LOOP;
	FOREACH v_i IN ARRAY v_sequences LOOP
		ASSERT (SELECT EXISTS(
			SELECT
				true
			FROM
				information_schema.sequences
			WHERE
				sequence_schema = 'jobcenter'
				AND sequence_name = v_i
		)), FORMAT('no sequence %s?', v_i);
	END LOOP;
	FOREACH v_i IN ARRAY v_triggers LOOP
		ASSERT (SELECT EXISTS(
			SELECT
				true
			FROM
				information_schema.triggers
			WHERE
				trigger_schema = 'jobcenter'
				AND trigger_name = v_i
		)), FORMAT('no trigger %s?', v_i);
	END LOOP;
	RAISE INFO 'all tests succesfull?';
END
$BODY$;
