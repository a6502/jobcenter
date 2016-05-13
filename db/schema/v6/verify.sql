
DO $BODY$
DECLARE
	v_tables text[] := array[
		'jc_env',
		'jc_impersonate_roles',
		'jc_role_members',
		'jc_roles',
		'jobs_archive',
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
	RAISE NOTICE 'all tests succesfull?';
END
$BODY$;
