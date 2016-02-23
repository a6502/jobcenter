
DO $BODY$
DECLARE
	v_tables text[] := array[
		'_procs',
		'_schema',
		'action_inputs',
		'action_outputs',
		'action_version_tags',
		'actions',
		'event_subscriptions',
		'jcenv',
		'job_events',
		'job_task_log',
		'jobs',
		'jsonb_object_fields',
		'locks',
		'locktypes',
		'next_tasks',
		'queued_events',
		'tasks',
		'version_tags',
		'worker_actions',
		'workers'
	];
	v_triggers text[] := array[
		'on_job_finished',
		'on_job_state_change',
		'on_job_task_change',
		'on_jobs_timerchange'
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
