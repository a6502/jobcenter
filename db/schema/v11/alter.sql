
create table json_schemas("type" text not null, base boolean not null default false, schema jsonb, primary key ("type"));

alter table json_schemas add constraint "json_schema_check" CHECK (base = true AND schema IS NULL OR base = false AND schema IS NOT NULL);

insert into json_schemas ("type", base) values ('null', true);
insert into json_schemas ("type", base) values ('boolean', true);
insert into json_schemas ("type", base) values ('number', true);
insert into json_schemas ("type", base) values ('string', true);
insert into json_schemas ("type", base) values ('array', true);
insert into json_schemas ("type", base) values ('object', true);

insert into json_schemas ("type", schema) values ('integer', '{"type":"integer"}');

update jsonb_object_fields set "typename" = 'object' where "typename" = 'json';

insert into json_schemas ("type", schema) values ('foobar', '{"type":"object","required":["foo","bar"]}');
insert into json_schemas ("type", schema) values ('event', '{"type":"object","required":["name","event_id","when","data"]}');

alter table action_inputs drop constraint action_inputs_type_fkey;
alter table action_inputs add constraint action_inputs_type_fkey FOREIGN KEY ("type") REFERENCES json_schemas("type") ON UPDATE CASCADE ON DELETE RESTRICT;

alter table action_outputs drop constraint action_outputs_type_fkey;
alter table action_outputs add constraint action_outputs_type_fkey FOREIGN KEY ("type") REFERENCES json_schemas("type") ON UPDATE CASCADE ON DELETE RESTRICT;

drop table jsonb_object_fields ;

ALTER TABLE json_schemas OWNER TO $JCADMIN;

REVOKE ALL ON TABLE json_schemas FROM PUBLIC;
REVOKE ALL ON TABLE json_schemas FROM $JCADMIN;
GRANT ALL ON TABLE json_schemas TO $JCADMIN;
GRANT SELECT ON TABLE json_schemas TO $JCSYSTEM;
