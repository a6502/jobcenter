CREATE OR REPLACE FUNCTION jobcenter.do_outargscheck(a_action_id integer, a_outargs jsonb)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_key text;
	v_type text;
	v_opt boolean;
	v_base boolean;
	v_schema jsonb;
	v_val jsonb;
	v_actual text;
	v_tmp text[];
	v_rootschema jsonb;
	v_subschema jsonb;
BEGIN
	FOR v_key, v_type, v_opt, v_base, v_schema IN SELECT
				"name", "type", "optional", "base", "schema"
			FROM
				action_outputs JOIN json_schemas USING ("type")
			WHERE
				action_id = a_action_id LOOP
		IF NOT a_outargs ? v_key THEN
			IF NOT v_opt THEN
				RAISE EXCEPTION 'required output parameter % not found', v_key;
			ELSE
				CONTINUE;
			END IF;
		END IF;

		v_val := a_outargs->v_key;
		IF v_base THEN
			v_actual := jsonb_typeof(v_val);
			IF v_actual IS NULL OR v_actual = v_type THEN
				-- ok?
				NULL;
			ELSE
				RAISE EXCEPTION 'ouput parameter % has wrong type % (should be %)', v_key, v_actual, v_type;
			END IF;
		ELSE
			IF jsonb_typeof(v_schema) = 'string' THEN
				SELECT regexp_matches((v_schema #>> '{}')::text, '^jcdb:(\w+)(#.*)$') INTO v_tmp;
				SELECT "schema" INTO v_rootschema FROM json_schemas WHERE "type" = v_tmp[1];
				IF v_rootschema IS NULL THEN
					RAISE EXCEPTION 'unkown type % referenced from schema % for output parameter %', v_tmp[1], v_schema, v_key;
				END IF;
				v_subschema = json_build_object('$ref', v_tmp[2]);
				-- RAISE NOTICE 'val % rootschema % subschema %', v_val, v_rootschema, v_subschema;
			ELSE
				v_subschema = v_schema;
			END IF;

			IF NOT do_validate_json_schema(v_subschema, v_val, v_rootschema) THEN
				RAISE EXCEPTION E'output parameter "%" with value "%" does not validate against schema:\n"%"', v_key, v_val, jsonb_pretty(v_schema);
			END IF;
		END IF;
	END LOOP;

	RETURN true;
END$function$
