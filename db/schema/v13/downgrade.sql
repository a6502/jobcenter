alter table worker_actions drop column filter;

-- this depends on default psqql index names
drop index jobs_arguments_idx;

