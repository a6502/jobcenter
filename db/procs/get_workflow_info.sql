CREATE OR REPLACE FUNCTION jobcenter.get_workflow_info(a_wfname text, a_tag text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_tags text[];
	v_workflow_id int;
	v_config jsonb;
	v_info jsonb DEFAULT '{}'::jsonb;
	v_tmp jsonb;
BEGIN
	IF a_tag IS NOT NULL AND a_tag <> 'default' THEN
		v_tags = string_to_array(a_tag, ':') || v_tags;
	END IF;

	-- find the worklow by name
	SELECT
		action_id, config INTO 
		v_workflow_id, v_config
	FROM 
		actions
		LEFT JOIN action_version_tags AS avt USING (action_id)
	WHERE
		type = 'workflow'
		AND name = a_wfname
		AND (avt.tag = ANY(v_tags) OR avt.tag IS NULL)
	ORDER BY array_position(v_tags, avt.tag), version DESC LIMIT 1;

	IF NOT FOUND THEN
		RETURN null::jsonb;
	END IF;

	IF v_config->>'description' IS NOT NULL THEN
		v_info = jsonb_insert(v_info, '{description}', v_config->>'description');
	END IF;


	SELECT
		json_object_agg(
			"name",
			jsonb_build_object(
				'type', "type",
				'default', "default"
			)
		) INTO v_tmp
	FROM
		action_inputs
	WHERE
		action_id = v_workflow_id
		AND destination = 'arguments'::action_input_destination;

	v_info = jsonb_insert(v_info, '{inputs}', COALESCE(v_tmp, '{}'::jsonb));

	SELECT
		json_object_agg(
			"name",
			jsonb_build_object(
				'type', "type",
				'optional', "optional"
			)
		) INTO v_tmp
	FROM
		action_outputs
	WHERE
		action_id = v_workflow_id;

	 v_info = jsonb_insert(v_info, '{outputs}', COALESCE(v_tmp, '{}'::jsonb));

	RETURN v_info;
END$function$
