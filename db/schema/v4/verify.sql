DO $BODY$
BEGIN
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.tables
		WHERE
			table_schema='jobcenter'
			AND table_name='version_tags'
	)), 'no table version_tags?';
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.tables
		WHERE
			table_schema='jobcenter'
			AND table_name='action_version_tags'
	)), 'no table action_version_tags?';
	RAISE NOTICE 'all tests succesfull?';
END
$BODY$;
