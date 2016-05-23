alter table jobs add column current_depth integer not null default 1;

alter table jobs_archive add column current_depth integer;

