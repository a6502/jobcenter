
DO $BODY$
BEGIN
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.columns
		WHERE
			table_schema='jobcenter'
			AND table_name='jobs'
			AND column_name='current_depth'
	)), 'no column current_depth in table jobs??';
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.columns
		WHERE
			table_schema='jobcenter'
			AND table_name='jobs_archive'
			AND column_name='current_depth'
	)), 'no column current_depth in table jobs_archive?';
	RAISE NOTICE 'all tests succesfull?';
END
$BODY$;
