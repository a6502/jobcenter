CREATE OR REPLACE FUNCTION jobcenter.disable_action(an_action_id integer, a_reason text DEFAULT ''::text)
 RETURNS text
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_job_count integer;
	v_action_ids text;
	v_error text;
	v_disable jsonb;
BEGIN
	/* check for running jobs by building tree of action_ids: 
	 * include an_action_id and find all workflows that reference 
	 * that and repeat
	 */
	WITH RECURSIVE action_tree as (
		SELECT 
			action_id,
			array[action_id] found
		FROM 
			actions
		WHERE 
			action_id = an_action_id
		UNION ALL
		SELECT
			a.action_id,
			at.found || a.action_id found
		FROM
			actions a
		JOIN
			tasks t
		ON 
			a.action_id = t.workflow_id
		JOIN 
			action_tree at
		ON 
			t.action_id = at.action_id AND
			a.action_id <> ALL (at.found) -- loop guard
	)
	SELECT 
		count(*)
	INTO
		v_job_count
	FROM (
		SELECT 
			j.job_id
		FROM
			action_tree at
		JOIN 
			jobs j
		ON 
			j.workflow_id = at.action_id
		WHERE 
			j.job_finished is null
		GROUP BY
			j.job_id
	) a;

	-- bail out if there are running jobs
	IF v_job_count > 0 THEN
		RAISE NOTICE 'running jobs (%) found for action (%)', v_job_count, an_action_id;
		RETURN format('not disabled: %s', an_action_id);
	END IF;

	-- check if any calling workflows are active
	WITH RECURSIVE latest_actions AS (
		SELECT 
			max(a.action_id) action_id, 
			a.name, 
			a.type,
			avt.tag
		FROM 
			actions a
		LEFT JOIN 
			action_version_tags avt
		ON
			a.action_id = avt.action_id
		GROUP BY 
			a.name, a.type, avt.tag
	), action_status AS (
		SELECT 
			t.workflow_id,
			a.action_id,
			(
				la.action_id IS NOT NULL AND
				NOT coalesce((a.config->'disabled' = 'true'::jsonb), false)
			) AS active
		FROM
			actions a
		LEFT JOIN
			tasks t
		ON
			t.action_id = a.action_id    AND 
			t.action_id != t.workflow_id     -- calls itself
		LEFT JOIN
			latest_actions la
		ON
			la.action_id = a.action_id
	-- find branches above action
	), branch_status AS (
		SELECT 
			ast.workflow_id,
			ast.action_id,
			ast.active,
			array[ast.action_id] found
		FROM 
			action_status ast
		WHERE 
			ast.action_id = an_action_id
		UNION ALL
		SELECT
			ast.workflow_id,
			ast.action_id,
			ast.active,
			bst.found || ast.action_id found
		FROM
			branch_status bst
		JOIN 
			action_status ast
		ON
			ast.action_id = bst.workflow_id AND
			ast.action_id <> ALL (bst.found) -- loop guard
	)
	SELECT 
		string_agg(DISTINCT bst.action_id::text, ', ' ORDER BY bst.action_id::text)
	INTO
		v_action_ids
	FROM
		branch_status bst
	WHERE
		bst.active AND
		bst.action_id != an_action_id; -- exclude self

	IF v_action_ids IS NOT NULL THEN
		RAISE NOTICE 'workflows found that rely on action (%): %', an_action_id, v_action_ids;
	END IF;

	v_disable := jsonb_set('{"disabled": true}'::jsonb, array['disabled_reason'], to_json(a_reason)::jsonb);

	-- disable an_action_id
	BEGIN
		UPDATE 
			actions
		SET
			config = COALESCE(config, '{}'::jsonb) || v_disable
		WHERE 
			action_id = an_action_id;
	EXCEPTION WHEN OTHERS THEN
		GET STACKED DIAGNOSTICS v_error = MESSAGE_TEXT;
		RAISE NOTICE 'failed to set action (%) as disabled: %', an_action_id, v_error;
		RETURN format('failed to disable: %s', an_action_id);
	END;

	IF FOUND THEN
		RETURN format('disabled: %s', an_action_id);
	ELSE
		RAISE NOTICE 'failed to find action (%)', an_action_id;
		RETURN format('not found: %s', an_action_id);
	END IF;

	-- not reached
END$function$
