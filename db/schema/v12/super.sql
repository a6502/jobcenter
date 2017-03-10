
update pg_enum set enumlabel = 'eventwait' where enumtypid = 'job_state'::regtype and enumlabel='waiting';

update pg_enum set enumlabel = 'childwait' where enumtypid = 'job_state'::regtype and enumlabel='blocked';

ALTER TYPE job_state ADD VALUE 'retrywait';

ALTER TYPE job_state ADD VALUE 'lockwait';

COMMENT ON TYPE jobcenter.job_state
  IS 'ready: waiting for a worker to pick this jobtask
working: waiting for a worker to finish this jobtask
eventwait: waiting for some external event or timeout
childwait: waiting for a subjob to finish
sleeping: waiting for time to pass
done: waiting for the maestro to start plotting
plotting: waiting for the maestro to decide
zombie: waiting for a parent job to wait for us
finished: done waiting
error: too much waiting?
retrywait: waiting until it is time to retry this jobtask
lockwait: waiting for a lock to be unlocked
';


update _schema set version = 12;

