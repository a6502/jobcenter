alter table next_tasks drop constraint check_same_workflow;

alter table next_tasks add constraint check_same_workflow check (do_check_same_workflow(from_task_id, to_task_id)) NOT VALID;

