
alter table locks drop column top_level_job_id;

alter table locks alter column inheritable drop not null, alter column contended drop not null;
