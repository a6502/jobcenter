
DO $BODY$
BEGIN
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.tables
		WHERE
			table_schema='jobcenter'
			AND table_name='jobs'
	)), 'no table jobs?';
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.columns
		WHERE
			table_schema='jobcenter'
			AND table_name='jobs'
			AND column_name='environment'
	)), 'no column environment in table jobs??';
	RAISE NOTICE 'all tests succesfull?';
END
$BODY$;
