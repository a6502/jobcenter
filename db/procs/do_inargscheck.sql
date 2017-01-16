CREATE OR REPLACE FUNCTION jobcenter.do_inargscheck(a_action_id integer, a_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_key text;
	v_type text;
	v_opt boolean;
	v_def jsonb;
	v_base boolean;
	v_schema jsonb;
	v_actual text;
	v_val jsonb;
	v_inargs jsonb;
	v_tmp text[];
	v_rootschema jsonb;
	v_subschema jsonb;
BEGIN
	v_inargs := a_args;

	-- now check if everything is there and check types
	FOR v_key, v_type, v_opt, v_def, v_base, v_schema IN SELECT
				"name", "type", "optional", "default", "base", "schema"
			FROM
				action_inputs JOIN json_schemas USING ("type")
			WHERE
				action_id = a_action_id LOOP
		IF v_inargs ? v_key THEN
			v_val := v_inargs->v_key;
			IF v_base THEN
				v_actual := jsonb_typeof(v_val);
				IF v_actual IS NULL OR v_actual = v_type THEN
					NULL;
				ELSE
					RAISE EXCEPTION 'input parameter "%" has wrong type % (should be %)', v_key, v_actual, v_type;
				END IF;
			ELSE
				IF jsonb_typeof(v_schema) = 'string' THEN
					SELECT regexp_matches((v_schema #>> '{}')::text, '^jcdb:(\w+)(#.*)$') INTO v_tmp;
					SELECT "schema" INTO v_rootschema FROM json_schemas WHERE "type" = v_tmp[1];
					IF v_rootschema IS NULL THEN
						RAISE EXCEPTION 'unkown type % referenced from schema % for input parameter %', v_tmp[1], v_schema, v_key;
					END IF;
					v_subschema = json_build_object('$ref', v_tmp[2]);
					-- RAISE NOTICE 'val % rootschema % subschema %', v_val, v_rootschema, v_subschema;
				ELSE
					v_subschema = v_schema;
				END IF;

				IF NOT do_validate_json_schema(v_subschema, v_val, v_rootschema) THEN
					RAISE EXCEPTION E'input parameter "%" with value "%" does not validate against schema:\n"%"', v_key, v_val, jsonb_pretty(v_schema);
				END IF;
			END IF;
		ELSE
			IF v_opt THEN
				v_inargs := jsonb_set(v_inargs, ARRAY[v_key], v_def);
			ELSE
				RAISE EXCEPTION 'required input parameter "%" not found', v_key;
			END IF;
		END IF;
	END LOOP;

	RETURN v_inargs;
END$function$
