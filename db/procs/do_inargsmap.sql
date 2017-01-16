CREATE OR REPLACE FUNCTION jobcenter.do_inargsmap(a_action_id integer, a_task_id integer, a_args jsonb, a_env jsonb, a_vars jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_key text;
	v_type text;
	v_opt boolean;
	v_def jsonb;
	v_code text;
	v_actual text;
	v_fields text[];
	v_val jsonb;
	v_inargs jsonb;
BEGIN
	SELECT attributes->>'imapcode' INTO v_code FROM tasks WHERE task_id = a_task_id;
	v_inargs := do_imap(v_code, a_args, a_env, a_vars);

	--RAISE NOTICE 'v_inargs now %', v_inargs;
	-- now check if everything is there and check types
	/*
	FOR v_key, v_type, v_opt, v_def IN SELECT "name", "type", optional, "default"
			FROM action_inputs WHERE action_id = a_action_id LOOP

		IF v_inargs ? v_key THEN
			v_val := v_inargs->v_key;
			v_actual := jsonb_typeof(v_val);
			IF v_actual = 'object' THEN
				SELECT fields INTO v_fields FROM jsonb_object_fields WHERE typename = v_type;
				IF NOT v_val ?& v_fields THEN
					RAISE EXCEPTION 'input parameter "%" with value "%" does have required fields %', v_key, v_val, v_fields;
				END IF;
			ELSIF v_actual = null OR v_actual = v_type THEN
				-- ok?
				NULL;
			ELSE
				RAISE EXCEPTION 'input parameter "%" has wrong type % (should be %)', v_key, v_actual, v_type;
			END IF;
		ELSE
			IF v_opt THEN
				v_inargs := jsonb_set(v_inargs, ARRAY[v_key], v_def);
			ELSE
				RAISE EXCEPTION 'required input parameter "%" not found', v_key;
			END IF;
		END IF;

	END LOOP;
	*/
	v_inargs := do_inargscheck(a_action_id, v_inargs);

	RETURN v_inargs;
END$function$
