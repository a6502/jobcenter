# JobCenter Installation

### Requirements & Dependencies:

*   PostgreSQL 9.6: [http://www.postgresql.org/download/](http://www.postgresql.org/download/)
    *   server, client and plperl procedural language
    *   debian: postgresql-9.6 postgresql-client-9.6 postgresql-contrib-9.6 postgresql-plperl-9.6
    *   rhel: postgresql95-server, postgresql95, postgresql95-contrib, postgresql95-plperl
    *   The jsonb features of version 9.6 are required, older versions won't
        work. Consider using the packages from postgresql.org if your
        distriubtion does not have the required version.
*   A initialized PostgreSQL cluster, configured to accept local and/or network connections
    using md5 passwords. Example pg_hba.conf:

```
# Database administrative login by Unix domain socket
local   all             postgres                                peer

# TYPE  DATABASE        USER            ADDRESS                 METHOD

# "local" is for Unix domain socket connections only
local   all             all                                     md5
# IPv4 local connections:
host    all             all             127.0.0.1/32            md5
# IPv6 local connections:
host    all             all             ::1/128                 md5

```

*   (one time) access to the PostresSQL unix user to configure pl/perl
*   (one time) access to the PostgreSQL superuser (user postgres or create a new one)
    * required for setting up the JobCenter database and roles
*   a unix user to run the JobCenter as ('jobcenter' for example, don't use root)
*   git (and access to the JobCenter git repository (but it seems you have
    that)
*   perl (>= 5.10, the system perl should do as long as it has all the
    standard modules)
    * For rhel6 / rhel7: install perl-core to get a "full" perl.
*   Try to install as much as possible of the following modules from your
    distribution (if you will be using the system perl)
    *   DBI, DBD::PG, libpq
        * debian: libdbi-perl, libdbd-pg-perl, libpq5
        * rhel: perl-DBI, perl-DBD-Pg, postgresql95-libs
    *   local::lib
        * debian: liblocal-lib-perl
        * rhel7: perl-local-lib
    *   cpanminus 
        * debian: cpanminus
        * rhel7: perl-App-cpanminus
    *   Config::Tiny
        * debian: libconfig-tiny-perl
        * rhel: perl-Config-Tiny
    *   Data::Printer
	* debian: libdata-printer-perl
    *   JSON::MaybeXS, Cpanel::JSON::XS (preferred) or JSON::XS
        * debian: libjson-maybexs-perl, libcpanel-json-xs-perl
    *   Mojolicious (>= 6.66)
        * debian (testing): libmojolicious-perl
    *   Mojo::Pg
        * debian (testing): libmojo-pg-perl
    *   Pegex (>= 0.60)
        * debian (testing): libpegex-perl
*   A way to install modules from CPAN, suggested is to set up a local Pinto
    server.
*   Install the following modules (from CPAN), suggested is to install into a local::lib
    for the JobCenter unix user:
    *   MojoX::NetstringStream
    *   JSON::RPC2::TwoWay
    *   JobCenter::Client::Mojo


### Installation:

*   Install dependencies listed above
*   Checkout jobcenter from git. Let's assume into
    /home/jobcenter/jobcenter.
*   edit the db/create_db script:
    *   set DBNAME to the desired database name for the jobcenter (default: jobcenter)
    *   set JC to the user prefix for the database users (default: jc)
    *   set CLUSTER to the connection details of the desired postgresql cluster.
        (usually empty unless you have multiple PostgreSQL versions 
        installed)
*   run the `db/create_db` script as a postgres superuser (for example user postgres)
*   change the passwords of the ${JC}_admin, ${JC}_client and ${JC}_maestro users
*   copy etc/jobcenter.conf.example to etc/jobcenter.conf and edit:
    *   the database name
    *   the names of the users
    *   the passwords of the users
    *   the connection details for the superuser (directory and port for psql)
*   copy etc/plperl.conf.example to etc/plperl.conf and edit the jobcenter
    path
*   copy etc/plperlinit.conf.example to etc/plperlinit.conf and edit the jobcenter
    path
*   Configure the PostgreSQL plperl module, for example:

    *   add a "include_if_exists = '<jobcenter>/etc/plperl.conf'" to the main PostgreSQL
        config file
        * debian: /etc/postgresql/9.6/postgresql.conf
        * rhel: /var/lib/pgsql/9.6/data/postgresql.conf
*   Restart PostgreSQL for the configuration changes to be effective.
*   Run `db/dbdings create` as the jobcenter user to create the schema in the db you
    just created
*   Then run `db/dbding update` to load the latest stored procedures
*   Start the maestro (use `bin/maestro --nodaemon` to see the debug output)
*   Start a worker, for example `bin/mojoworker --nodaemon`
*   Try a 'hello world' test:
    *   Compile: `bin/jcc test/calltest.wf`
    *   Run: `bin/simpleclient calltest '{"input":12}'`
    *   This should produce output like:
```
job_id 1 listenstring job:1:finished
timeout: 60
outargs as json: {"output": 15}
result: {"output": 15}
```
*   Run the unittests: `cd tests; ./dotest.pl`
*   Configure the API:
    *   If you want to use SSL, you need a certificate. To create a self-signed one:
        * 'openssl req -x509 -newkey rsa:2048 -keyout api.key -out api.pem -days 3065 -nodes'
        * use
    *   Now start the JobCenter API: bin/jcapi

### Uprading:

*   stop any JobCenter workers
*   now stop the JobCenter API (the order matters)
*   stop the maestro
*   git pull the updates
*   run db/dbdings check to see if the db schema needs updating
    *   if it does: run db/dbdings upgrade to update the schema
*   run db/dbdings compare to see if any stored procedures need updating.
    *   if they do: run db/dbdings update
*   start the maestro, the api and the workers
*   ...

