DO $BODY$
BEGIN
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.columns
		WHERE
			table_schema='jobcenter'
			AND table_name='action'
			AND column_name='src'
	)), 'no column src in table action??';
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.columns
		WHERE
			table_schema='jobcenter'
			AND table_name='action'
			AND column_name='srcmd5'
	)), 'no column src in table action??';
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.columns
		WHERE
			table_schema='jobcenter'
			AND table_name='action_inputs'
			AND column_name='destination'
	)), 'no column destination in table action_inputs??';
	RAISE NOTICE 'all tests succesfull?';
END
$BODY$;
