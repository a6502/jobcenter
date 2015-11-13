CREATE OR REPLACE FUNCTION jobcenter.do_outargsmap(a_action_id integer, a_task_id integer, a_oldvars jsonb, a_outargs jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_key text;
	v_type text;
	v_opt boolean;
	v_actual text;
	v_code text;
	v_fields text[];
	v_val jsonb;
	v_newvars jsonb;
BEGIN
	a_outargs := COALESCE(a_outargs, '{}'::jsonb);
	v_newvars := COALESCE(a_oldvars, '{}'::jsonb);

	RAISE NOTICE 'a_oldvars % a_outargs %', a_oldvars, a_outargs;
	FOR v_key, v_type, v_opt IN SELECT "name", "type", optional
			FROM action_outputs WHERE action_id = a_action_id LOOP

		IF NOT a_outargs ? v_key THEN
			IF NOT v_opt THEN
				RAISE EXCEPTION 'required output parameter % not found', v_key;
			ELSE
				CONTINUE;
			END IF;
		END IF;

		v_val := a_outargs->v_key;
		v_actual := jsonb_typeof(v_val);
		RAISE NOTICE 'v_key % v_type % v_opt % v_val % v_actual %', v_key, v_type, v_opt, v_val, v_actual;

		IF v_actual = 'object' THEN
			SELECT fields INTO v_fields FROM jsonb_object_fields WHERE typename = v_type;
			IF NOT v_val ?& v_fields THEN
				RAISE EXCEPTION 'output parameter % with value % does have required fields %', v_key, v_val, v_fields;
			END IF;
		ELSIF v_actual = null OR v_actual = v_type THEN
			-- ok?
			NULL;
		ELSE
			RAISE EXCEPTION 'ouput parameter % has wrong type % (should be %)', v_key, v_actual, v_type;
		END IF;
	END LOOP;

	SELECT omapcode INTO v_code FROM tasks WHERE task_id = a_task_id;
	v_newvars := do_omap(v_code, v_newvars, a_outargs);

	IF a_oldvars IS NULL AND v_newvars = '{}'::jsonb THEN
		-- nothing has really changed
		RETURN NULL;
	END IF;

	RETURN v_newvars;
END$function$
