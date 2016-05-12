CREATE OR REPLACE FUNCTION jobcenter.do_workflowoutargsmap(a_workflow_id integer, a_vars jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_code text;
	v_outargs jsonb;
	v_key text;
	v_type text;
	v_opt boolean;
	v_val jsonb;
	v_actual text;
	v_fields text[];
BEGIN
	SELECT wfmapcode INTO v_code FROM actions WHERE action_id = a_workflow_id;
	v_outargs := do_wfomap(v_code, a_vars);
	
	FOR v_key, v_type, v_opt IN SELECT "name", "type", optional
			FROM action_outputs WHERE action_id = a_workflow_id LOOP

		IF NOT v_outargs ? v_key THEN
			IF NOT v_opt THEN
				RAISE EXCEPTION 'required output parameter % not found', v_key;
			ELSE
				CONTINUE;
			END IF;
		END IF;

		v_val := v_outargs->v_key;
		v_actual := jsonb_typeof(v_val);
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

	RETURN v_outargs;
END$function$
