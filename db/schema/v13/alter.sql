alter table worker_actions add column filter jsonb;

create index on jobs using gin (arguments jsonb_path_ops);
create index on jobs_archive using gin (arguments jsonb_path_ops);

