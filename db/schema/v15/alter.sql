CREATE TABLE jobcenter.call_stats (
    name text NOT NULL PRIMARY KEY,
    calls bigint DEFAULT 0 NOT NULL
);


ALTER TABLE jobcenter.call_stats OWNER TO $JCSYSTEM;


CREATE TABLE jobcenter.call_stats_collected (
	unique_id boolean NOT NULL PRIMARY KEY DEFAULT TRUE,
    last timestamp with time zone DEFAULT now(),
	CONSTRAINT call_stats_collected_urow CHECK (unique_id)
);


ALTER TABLE jobcenter.call_stats_collected OWNER TO $JCSYSTEM;
