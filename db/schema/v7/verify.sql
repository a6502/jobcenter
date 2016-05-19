
DO $BODY$
BEGIN
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.tables
		WHERE
			table_schema='jobcenter'
			AND table_name='locks'
	)), 'no table locks?';
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.columns
		WHERE
			table_schema='jobcenter'
			AND table_name='locks'
			AND column_name='top_level_job_id'
	)), 'no column top_level_job_id in table locks??';
	RAISE NOTICE 'all tests succesfull?';
END
$BODY$;
