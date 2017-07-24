
DO $BODY$
BEGIN
	ASSERT (SELECT EXISTS(
		SELECT
			true
		FROM
			information_schema.columns
		WHERE
			table_schema='jobcenter'
			AND table_name='worker_actions'
			AND column_name='filter'
	)), 'no column filter in table worker_actions??';
	RAISE NOTICE 'all tests succesfull?';
END
$BODY$;
