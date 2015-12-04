package JobCenter::SimpleClient;

use strict;
use warnings;
use 5.10.0;

# standard modules
use Data::Dumper;
use IO::Poll qw(POLLIN);
use Module::Load qw(load);
use Time::HiRes qw(time);

# non standard modules that should be available as packages even on rhel-6
#use Config::Tiny;
use DBI;
use DBD::Pg qw(:async);
use JSON qw(decode_json encode_json);

sub new {
	my ($class, %args) = @_;
	my $self = bless {
		clientname => $args{clientname} || "$0 [$$]",
		debug => $args{debug} // 1,
		json => $args{json} // 1,
		timeout => $args{timeout} || 60,
	}, $class;
	if ($args{cfgpath}) {
		load Config::Tiny;
		my $cfg = Config::Tiny->read($args{cfgpath});
		die 'failed to read config ' . $args{cfgpath} . ': ' . Config::Tiny->errstr unless $cfg;
		$self->{pgdsn} = 'dbi:Pg:dbname=' . $cfg->{pg}->{db}
			. ';host=' . $cfg->{pg}->{host}
			. ';port=' . $cfg->{pg}->{port};
		$self->{pguser} = $cfg->{client}->{user};
		$self->{pgpass} = $cfg->{client}->{pass};
	} else {
		$self->{pgdsn} = $args{pgdsn} or die 'no pgdsn?';
		$self->{pguser} = $args{pguser} or die 'no pguser?';
		$self->{pgpass} = $args{pgpass} or die 'no pgpass?';
	}

	# make our clientname the application_name visible in postgresql
	$ENV{'PGAPPNAME'} = $self->{clientname};
	$self->{pgh} = DBI->connect(
		$self->{pgdsn}, $self->{pguser}, $self->{pgpass},
		{
			AutoCommit => 1,
			RaiseError => 1,
			PrintError => $args{debug} // 1, # 0?
		}
	) or die "cannot connect to db: $DBI::errstr";
	$self->{pgh}->{pg_placeholder_dollaronly} = 1;
	
	return $self;
}

sub call {
	my $self = shift;
	my $wfname = shift or die 'no workflowname?';
	my $inargs = shift // '{}';

	if ($self->{json}) {
		# sanity check json string
		my $inargsp = decode_json($inargs);
		die 'inargs is not a json object' unless ref $inargsp eq 'HASH';
	} else {
		die  'inargs should be a hashref' unless ref $inargs eq 'HASH';
		$inargs = encode_json($inargs);
	}

	my $pgh = $self->{pgh};
	my ($job_id, $listenstring);
	# create_job throws an error when:
	# - wfname does not exist
	# - inargs not valid
	($job_id, $listenstring) = $pgh->selectrow_array(
		q[select * from create_job($1, $2)],
		{},
		$wfname,
		$inargs
	);
	die "no result from call to create_job" unless $job_id;
	say STDERR "job_id $job_id listenstring $listenstring" if $self->{debug};

	$pgh->do('LISTEN ' . $pgh->quote_identifier($listenstring));

	my $poll = IO::Poll->new();
	open my $pgfd, '<&=', $self->{pgh}->{pg_socket} or die "Can't fdopen: $!";
	$poll->mask($pgfd => POLLIN);
	my $now = time();
	my $timeout = $now + $self->{timeout};

	while ($timeout > $now) {
		# there is a race condition between create_job and listen, so we have
		# to call get_job_status now to see if the job has finished already
		# if not, we wait for the notification
		
		my ($outargs) = $pgh->selectrow_array(
			q[select * from get_job_status($1)],
			{},
			$job_id
		);
		if ($outargs) {
			return $outargs if $self->{json};
			return decode_json($outargs);
		}

		say STDERR "timeout: ", $timeout - $now if $self->{debug};
		my $ret = $poll->poll($timeout - $now);
		# why poll returns doesn't matter here
		# we only poll on 1 fd and we only listen to 1 channel
		# so it it either the timeout, caught by the while condition
		# or the notification we were waiting for
		$now = time();
	}
	# timeout
	die 'call timed out';
}

1;

=encoding utf8

=head1 NAME

JobCenter::SimpleClient - simple blocking JobCenter client

=head1 SYNOPSIS

 use JobCenter::SimpleClient;

 my $client = JobCenter::SimpleClient->new(
        cfgpath => "$FindBin::Bin/../etc/jobcenter.conf",
        debug => 1,
 );

 my $result = $client->call($wfname, $inargs);

=head1 DESCRIPTION

"JobCenter::SimpleClient" is a class to build a simple blocing client for the
JobCenter workflow engine. It has minimal (non-core) dependencies.

=head1 METHODS

=head2 new

$client = JobCenter::SimpleClient->new(%arguments);

Class method that returns a new JobCenter::SimpleClient object.

Valid arguments are:

=over 4

=item - cfgpath: path to a JobCenter configutationn file. 

 (either cfgpath or pgdsn, pguser and pgpass need to be supplied)

=item - clientname: postgresql clientname to use.

Z<> 

=item - debug: when true prints debugging on stderr.

(default false)

=item - json flag:

 when true expects the inargs to be valid json.
 when false a perl hashref is expected and json encoded.
 (default true)

=item - pgdsn: dbi dsn for postgresql

=item - pguser: postgresql user

=item - pgpass: postgresql pass

 (either cfgpath or pgdsn, pguser and pgpass need to be supplied)

=item - timeout: how long to wait for the call to complete

 (default 60 seconds)

=back

=head2 call

$result = $client->call('my1stworkflow', '{"input":"foo"}');

Calls the workflow named the first argument with the inargs of the second argument.
Throws an error if anything goes wrong.

=head1 SEE ALSO

L<Jobcenter::SimpleWorker>, L<simpleclient>, L<simpleclient2>.

=cut

