
alter table locks add column top_level_job_id bigint;

update locks set inheritable=false where inheritable is null;

alter table locks alter column inheritable set not null, alter column contended set not null;
