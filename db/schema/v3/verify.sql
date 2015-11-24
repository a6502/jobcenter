
DO $BODY$
BEGIN
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.tables
		WHERE
			table_schema='jobcenter'
			AND table_name='actions'
	)), 'no table actions?';
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.columns
		WHERE
			table_schema='jobcenter'
			AND table_name='actions'
			AND column_name='wfenv'
	)), 'no column wfenv in table actions??';
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.tables
		WHERE
			table_schema='jobcenter'
			AND table_name='jcenv'
	)), 'no table jcenv?';
	RAISE NOTICE 'all tests succesfull?';
END
$BODY$;
