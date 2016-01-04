CREATE TABLE version_tags
(
  tag text NOT NULL,
  CONSTRAINT version_tag_pkey PRIMARY KEY (tag)
);
ALTER TABLE version_tags OWNER TO $JCADMIN;
GRANT ALL ON TABLE version_tags TO $JCADMIN;
GRANT SELECT ON TABLE version_tags TO $JCSYSTEM;

CREATE TABLE action_version_tags
(
  action_id integer NOT NULL,
  tag text NOT NULL,
  CONSTRAINT action_version_tags_pkey PRIMARY KEY (action_id, tag),
  CONSTRAINT action_version_tags_action_id_fkey FOREIGN KEY (action_id)
      REFERENCES actions (action_id) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE CASCADE,
  CONSTRAINT action_version_tags_tag_fkey FOREIGN KEY (tag)
      REFERENCES version_tags (tag) MATCH SIMPLE
      ON UPDATE NO ACTION ON DELETE CASCADE
);
ALTER TABLE action_version_tags OWNER TO $JCADMIN;
GRANT ALL ON TABLE action_version_tags TO $JCADMIN;
GRANT SELECT ON TABLE action_version_tags TO $JCSYSTEM;
