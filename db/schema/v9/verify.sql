
DO $BODY$
DECLARE
	v_roles text[] := array[
		'$JCSYSTEM',
		'$JCADMIN',
		'$JCPERL',
		'$JCCLIENT'
	];
	v_i text;
BEGIN
	FOREACH v_i IN ARRAY v_roles LOOP
		ASSERT (SELECT EXISTS(
			SELECT
				true
			FROM
				information_schema.enabled_roles
			WHERE
				role_name = v_i
		)), FORMAT('no role %s?', v_i);
	END LOOP;
	RAISE INFO 'all tests succesfull?';
END
$BODY$;
