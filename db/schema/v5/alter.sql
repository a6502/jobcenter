
--

ALTER TYPE action_type
          ADD VALUE 'procedure' AFTER 'action';

---

ALTER FUNCTION increase_stepcounter()
          RENAME TO do_increase_stepcounter;

DROP TRIGGER jobs_task_change ON jobs;
        
CREATE TRIGGER on_job_task_change
          BEFORE UPDATE OF task_id
          ON jobs
          FOR EACH ROW
          EXECUTE PROCEDURE do_increase_stepcounter();

---

ALTER FUNCTION clear_waiting_events()
          RENAME TO do_clear_waiting_events;

DROP TRIGGER jobs_state_change ON jobs;
        
CREATE TRIGGER on_job_state_change
          AFTER UPDATE OF state
          ON jobs
          FOR EACH ROW
          WHEN (((old.state = 'waiting'::job_state) AND (new.state <> 'waiting'::job_state)))
          EXECUTE PROCEDURE do_clear_waiting_events();

---

ALTER FUNCTION cleanup_on_finish()
          RENAME TO do_cleanup_on_finish;

DROP TRIGGER on_job_finished ON jobs;

CREATE TRIGGER on_job_finished
          AFTER UPDATE
          ON jobs
          FOR EACH ROW
          WHEN ((new.job_finished IS NOT NULL))
          EXECUTE PROCEDURE do_cleanup_on_finish()
--

ALTER FUNCTION notify_timerchange()
          RENAME TO do_notify_timerchange;

DROP TRIGGER timerchange ON jobs;
        
CREATE TRIGGER on_jobs_timerchange
          AFTER INSERT OR UPDATE OF timeout OR DELETE
          ON jobs
          FOR EACH STATEMENT
          EXECUTE PROCEDURE do_notify_timerchange();

--

ALTER FUNCTION is_workflow(integer)
          RENAME TO do_is_workflow;

ALTER TABLE jobs DROP CONSTRAINT check_is_workflow;
        
ALTER TABLE jobs
          ADD CONSTRAINT check_is_workflow CHECK (do_is_workflow(workflow_id));

ALTER TABLE tasks DROP CONSTRAINT check_is_workflow;
        
ALTER TABLE tasks
          ADD CONSTRAINT check_is_workflow CHECK (do_is_workflow(workflow_id));

--

ALTER FUNCTION is_action(integer)
          RENAME TO do_is_action;

ALTER TABLE worker_actions DROP CONSTRAINT check_is_action;
        
ALTER TABLE worker_actions
          ADD CONSTRAINT check_is_action CHECK (do_is_action(action_id));

--

ALTER FUNCTION check_job_is_waiting(bigint, boolean)
          RENAME TO do_check_job_is_waiting;

ALTER TABLE event_subscriptions DROP CONSTRAINT check_job_is_wating;
        
ALTER TABLE event_subscriptions
          ADD CONSTRAINT check_job_is_wating CHECK (do_check_job_is_waiting(job_id, waiting));

--

ALTER FUNCTION check_same_workflow(integer, integer)
          RENAME TO do_check_same_workflow;

ALTER TABLE next_tasks DROP CONSTRAINT check_same_workflow;
        
ALTER TABLE next_tasks
          ADD CONSTRAINT check_same_workflow CHECK (do_check_same_workflow(from_task_id, to_task_id));

--

ALTER FUNCTION check_wait(integer, boolean)
          RENAME TO do_check_wait;

ALTER TABLE tasks DROP CONSTRAINT check_wait;
        
ALTER TABLE tasks
          ADD CONSTRAINT check_wait CHECK (do_check_wait(action_id, wait));

--

ALTER FUNCTION check_wait_for_task(integer, integer)
          RENAME TO do_check_wait_for_task;
        COMMENT ON FUNCTION do_check_wait_for_task(integer, integer)
          IS 'seems to be unused?';

--

ALTER FUNCTION sanity_check_workflow(integer)
          RENAME TO do_sanity_check_workflow;

--

update _procs set name = 'do_check_job_is_waiting' where name = 'check_job_is_waiting';

update _procs set name = 'do_check_same_workflow' where name = 'check_same_workflow';

update _procs set name = 'do_check_wait' where name = 'check_wait';

update _procs set name = 'do_check_wait_for_task' where name = 'check_wait_for_task';

update _procs set name = 'do_cleanup_on_finish' where name = 'cleanup_on_finish';

update _procs set name = 'do_clear_waiting_events' where name = 'clear_waiting_events';

update _procs set name = 'do_increase_stepcounter' where name = 'increase_stepcounter';

update _procs set name = 'do_is_action' where name = 'is_action';

update _procs set name = 'do_is_workflow' where name = 'is_workflow';

update _procs set name = 'do_notify_timerchange' where name = 'notify_timerchange';

update _procs set name = 'do_sanity_check_workflow' where name = 'sanity_check_workflow';

--

CREATE TYPE jobtask AS
           (workflow_id integer,
            task_id integer,
            job_id bigint);
        ALTER TYPE jobtask
          OWNER TO jc_admin;

CREATE TYPE nextjobtask AS
           (error boolean,
            jobtask jobtask);
        ALTER TYPE nextjobtask
          OWNER TO jc_admin;

-- DROP TYPE jobcenter.nexttask;





