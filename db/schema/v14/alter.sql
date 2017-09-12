
alter table actions add column src text, add column srcmd5 uuid;

CREATE TYPE action_input_destination AS ENUM
   ('arguments',
    'environment');
ALTER TYPE action_input_destination
  OWNER TO jc_admin;

alter table action_inputs add column destination action_input_destination not null default 'arguments';

