
DO $BODY$
DECLARE
	v_tables text[] := array[
		'_procs',
		'_schema',
		'action_inputs',
		'action_outputs',
		'actions',
		'event_subscriptions',
		'job_events',
		'job_task_log',
		'jobs',
		'jsonb_object_fields',
		'locks',
		'locktypes',
		'next_tasks',
		'queued_events',
		'tasks',
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
		'timerchange',
		'on_job_finished',
		'jobs_task_change',
		'jobs_state_change'
	];
	v_i text;
BEGIN
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
	RAISE NOTICE 'all tests succesfull?';
END
$BODY$;
