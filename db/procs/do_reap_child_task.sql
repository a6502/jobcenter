CREATE OR REPLACE FUNCTION jobcenter.do_reap_child_task(a_jobtask jobtask)
 RETURNS nextjobtask
 LANGUAGE plpgsql
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$DECLARE
	v_reapfromtask_id int;
	v_map boolean;
	v_rec record;
	v_subjob_id bigint;
	v_in_args jsonb;
	v_out_args jsonb;
	v_args jsonb;
	v_env jsonb;
	v_oldvars jsonb;
	v_action_id integer;
	v_code text;
	--v_maptask_id integer; -- task we use the map defintions from
	--v_mapaction_id integer;
	v_changed boolean;
	v_newvars jsonb;
	v_nexttask_id int;
BEGIN
	-- paranoia check with side effects
	SELECT
		(tasks.attributes->>'reapfromtask_id')::int,
		COALESCE( (tasks.attributes->>'map')::boolean, false)
		INTO v_reapfromtask_id, v_map
	FROM
		jobs
		JOIN tasks USING (workflow_id, task_id)
		JOIN actions USING (action_id)
	WHERE
		job_id = a_jobtask.job_id
		AND workflow_id = a_jobtask.workflow_id
		AND task_id= a_jobtask.task_id
		AND state = 'ready'
		AND actions.type = 'system'
		AND actions.name = 'reap_child';

	IF NOT FOUND THEN
		-- FIXME: call do_raise_error instead?
		RAISE EXCEPTION 'do_reap_child called for non-reap_child-task %', a_jobtask.task_id;
	END IF;

	IF v_reapfromtask_id IS NULL THEN
		RAISE EXCEPTION 'reap_from_task field required for reap_child task %', a_jobtask.task_id;
	END IF;

	-- todo: unify with the non-map case
	IF v_map THEN
		RAISE NOTICE 'look for child jobs of % task %', a_jobtask.job_id, v_reapfromtask_id;
		-- the child job should be a zombie already
	
		SELECT
			arguments, environment, variables
			INTO v_args, v_env, v_oldvars
		FROM
			jobs
		WHERE
			job_id = a_jobtask.job_id;

		-- now get the rest using the task_id and workflow_id
		SELECT
			action_id, attributes->>'omapcode'
			INTO v_action_id, v_code
		FROM
			tasks
			JOIN actions USING (action_id)
		WHERE
			task_id = v_reapfromtask_id
			AND workflow_id = a_jobtask.workflow_id;

		IF NOT FOUND THEN
			RAISE EXCEPTION 'do_outargsarsmap: task % not found', a_jobtask.task_id;
		END IF;
		
		-- omap also initializes oldvars to empty, but then we would log a change if newvars is also empty
		v_oldvars := COALESCE(v_oldvars, '{}'::jsonb);
		
		-- otherwise the variables get clobbered if there were no childjobs:
		v_newvars := v_oldvars;

		v_env = do_populate_env(a_jobtask, v_env);

		FOR v_subjob_id, v_in_args, v_out_args IN
			SELECT
				job_id, arguments, out_args
			FROM
				jobs
			WHERE
				(job_state->>'parenttask_id')::integer = v_reapfromtask_id
				AND parentjob_id = a_jobtask.job_id
				AND state = 'zombie'
			ORDER BY job_id FOR UPDATE OF jobs LOOP
			
			RAISE NOTICE 'child job % finished', v_subjob_id;

			UPDATE
				jobs
			SET
				state = 'finished',
				job_finished = now(),
				task_completed = now()
			WHERE
				job_id = v_subjob_id;

			-- we want the output definitios and maps from the original task that started this
			-- childjob, so we use v_reapfromtask_id in the do_outargsmap
			BEGIN
				v_out_args := COALESCE(v_out_args, '{}'::jsonb);

				RAISE NOTICE 'do_outargsmap: v_oldvars % a_outargs %', v_newvars, v_out_args;
				-- 'unroll' do_outargsmap to save a lot of queries

				PERFORM do_outargscheck(v_action_id, v_out_args);

				-- now run the mapping code
				v_newvars := do_omap(v_code, v_args, v_env, v_oldvars, v_out_args);

				-- and log the output..
				INSERT INTO
					job_task_log (
						job_id,
						workflow_id,
						task_id,
						variables,
						task_entered,
						task_started,
						task_completed,
						task_inargs,
						task_outargs,
						task_state
					)
				SELECT
					job_id,
					workflow_id,
					task_id,
					CASE WHEN v_oldvars IS DISTINCT FROM v_newvars THEN v_newvars ELSE null END,
					task_entered,
					task_started,
					task_completed,
					v_in_args,
					v_out_args,
					jsonb_build_object('childjob_id', v_subjob_id)
				FROM jobs
				WHERE job_id = a_jobtask.job_id;

				v_oldvars := v_newvars;

			EXCEPTION WHEN OTHERS THEN
				RETURN do_raise_error(a_jobtask, format('caught exception in do_outargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM)::jsonb);
			END;
			RAISE NOTICE 'reap_child newvars: %', v_newvars;
		END LOOP;

		-- cant' use the normal task_epilogue here because that would redo the logging we already did
		--RETURN do_task_epilogue(a_jobtask, (v_oldvars IS DISTINCT FROM v_newvars), v_newvars, v_in_args, v_out_args);

		UPDATE jobs SET
			state = 'plotting',
			variables = CASE WHEN v_newvars IS DISTINCT FROM variables THEN v_newvars ELSE variables END,
			task_started = CASE WHEN task_started IS NULL THEN now() ELSE task_started END,
			task_completed = now()
		WHERE job_id = a_jobtask.job_id;

		SELECT next_task_id INTO STRICT v_nexttask_id FROM tasks WHERE task_id = a_jobtask.task_id;

		IF v_nexttask_id = a_jobtask.task_id THEN
			RAISE EXCEPTION 'next_task_id equals task_id %', a_jobtask.task_id;
		END IF;

		RETURN (false, (a_jobtask.workflow_id, v_nexttask_id, a_jobtask.job_id)::jobtask)::nextjobtask;
	END IF;

	RAISE NOTICE 'look for child job of % task %', a_jobtask.job_id, v_reapfromtask_id;
	-- the child job should be a zombie already

	UPDATE
		jobs
	SET
		state = 'finished',
		job_finished = now(),
		task_completed = now()
	WHERE
		(job_state->>'parenttask_id')::integer = v_reapfromtask_id
		AND parentjob_id = a_jobtask.job_id
		AND state = 'zombie'
	RETURNING job_id, arguments, out_args INTO v_subjob_id, v_in_args, v_out_args;

	IF NOT FOUND THEN
		RETURN do_raise_error(a_jobtask, 'no zombie childjob found in reap_child_task');
	END IF;

	RAISE NOTICE 'child job % finished', v_subjob_id;

	-- we want the output definitios and maps from the original task that started this
	-- childjob, so we use v_reapfromtask_id in the do_outargsmap
	BEGIN
		SELECT
			vars_changed, newvars
			INTO v_changed, v_newvars
		FROM
			do_outargsmap((a_jobtask.workflow_id, v_reapfromtask_id, a_jobtask.job_id)::jobtask, v_out_args);
	EXCEPTION WHEN OTHERS THEN
		RETURN do_raise_error(a_jobtask, format('caught exception in do_outargsmap sqlstate %s sqlerrm %s', SQLSTATE, SQLERRM)::jsonb);
	END;

	RAISE NOTICE 'reap_child newvars: %', v_newvars;

	-- log the child job_id in the task_state field
	UPDATE jobs SET
		task_state = jsonb_build_object('childjob_id', v_subjob_id)
	WHERE job_id = a_jobtask.job_id;

	RETURN do_task_epilogue(a_jobtask, v_changed, v_newvars, v_in_args, v_out_args);
END
$function$
