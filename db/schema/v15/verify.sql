DO $BODY$
DECLARE
	v_tables text[] := array[
		'call_stats',
		'call_stats_collected'
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
	RAISE INFO 'all tests succesfull?';
END
$BODY$;
