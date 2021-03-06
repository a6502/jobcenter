ALTER TABLE actions ADD COLUMN wfenv jsonb;
ALTER TABLE actions ADD CONSTRAINT actions_wfenvcheck CHECK (type <> 'workflow'::action_type AND wfenv IS NULL OR type = 'workflow'::action_type);
CREATE TABLE jcenv (jcenv jsonb);
CREATE UNIQUE INDEX jcenv_uidx ON jcenv ((jcenv IS NULL OR jcenv IS NOT NULL));
ALTER TABLE jcenv OWNER TO $JCADMIN;
GRANT ALL ON TABLE jcenv TO $JCADMIN;
GRANT SELECT ON TABLE jcenv TO $JCSYSTEM;
INSERT INTO jcenv VALUES ('{"version":"0.1"}'::jsonb);
