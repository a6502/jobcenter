CREATE OR REPLACE FUNCTION jobcenter.get_stale_actions()
 RETURNS TABLE(top_level_ids integer[], workflow_name text, workflow_id integer, workflow_version integer, name text, action_id integer, version integer, latest_action_id integer, latest_version integer, found integer[], type action_type, tag text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'jobcenter', 'pg_catalog', 'pg_temp'
AS $function$DECLARE
BEGIN
	-- try looking at latest workflows and working down looking for stale references
	RETURN QUERY
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
	), broken_dependency AS (
		SELECT 
			lw.action_id workflow_id,
			t.action_id
		FROM
			latest_actions lw
		JOIN 
			actions wf
		ON
			wf.action_id = lw.action_id
		JOIN
			tasks t
		ON
			lw.type = 'workflow' AND
			t.workflow_id = lw.action_id AND 
			t.action_id != t.workflow_id    -- calls itself
		LEFT JOIN
			latest_actions la
		ON
			t.action_id = la.action_id      -- task action not in latest_actions
		WHERE
			la.action_id IS NULL AND
			NOT coalesce((wf.config->'disabled' = 'true'::jsonb), false)
	-- find branches above broken dependency
	), broken_branches AS (
		SELECT 
			bd.workflow_id,
			bd.action_id,
			array[bd.action_id] found,
			bd.workflow_id broken_workflow_id,
			bd.action_id broken_action_id
		FROM 
			broken_dependency bd
		UNION ALL
		SELECT
			t.workflow_id,
			a.action_id,
			bb.found || a.action_id found,
			bb.broken_workflow_id broken_workflow_id,
			bb.broken_action_id broken_action_id
		FROM
			broken_branches bb
		JOIN 
			actions a
		ON
			a.action_id = bb.workflow_id AND
			a.action_id <> ALL (bb.found) -- loop guard
		LEFT JOIN
			tasks t
		ON 
			t.action_id = a.action_id AND
			t.action_id != t.workflow_id    -- calls itself
	), grouped AS (
		SELECT 
			array_agg(DISTINCT bb.action_id ORDER BY bb.action_id) top_level_ids, 
			array_agg(DISTINCT all_found ORDER BY all_found) found, 
			bb.broken_workflow_id broken_workflow_id, 
			bb.broken_action_id broken_action_id
		FROM
			broken_branches bb
		JOIN
			latest_actions la
		ON
			bb.action_id = la.action_id -- top level workflows must be active
			, unnest(bb.found) all_found -- expand results by found values
		WHERE
			bb.workflow_id IS NULL
		GROUP BY
			bb.broken_workflow_id,
			bb.broken_action_id
	) 
	SELECT 
		g.top_level_ids,
		wf.name workflow_name,
		wf.action_id workflow_id,
		wf.version workflow_version,
		a.name,
		a.action_id, 
		a.version,
		la.action_id latest_action_id,
		la2.version latest_version,
		g.found,
		a.type, 
		avt.tag 
	FROM
		grouped g
	JOIN 
		actions wf
	ON 
		wf.action_id = g.broken_workflow_id
	JOIN
		actions a
	ON
		a.action_id = g.broken_action_id
	LEFT JOIN
		action_version_tags avt
	ON
		avt.action_id = a.action_id
	LEFT JOIN 
		latest_actions la
	ON
		la.name = a.name AND
		la.type = a.type AND
		coalesce(la.tag, 'default') = coalesce(avt.tag, 'default')
	LEFT JOIN 
		actions la2
	ON
		la2.action_id = la.action_id;
	RETURN;
END$function$
