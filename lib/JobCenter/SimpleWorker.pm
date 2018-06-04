package Jobcenter::SimpleWorker;

use strict;
use warnings;
use 5.10.0;

# standard modules
use Data::Dumper;
use FindBin;
use IO::Poll qw(POLLIN);
use Module::Load qw(load);
use Time::HiRes qw(time);

# non standard modules that should be available as packages even on rhel-6
use Config::Tiny;
use DBI;
use DBD::Pg qw(:async);
use JSON qw(decode_json encode_json);

sub new {
	my ($class, %args) = @_;
	my $workername = $args{workername} ||  "$0 [$$]";
	my ($cfg, $pgdsn, $pguser, $pgpass);
	if ($args{cfgpath}) {
		load Config::Tiny;
		$cfg = Config::Tiny->read($args{cfgpath});
		die 'failed to read config ' . $args{cfgpath} . ': ' . Config::Tiny->errstr unless $cfg;
		$pgdsn = 'dbi:Pg:dbname=' . $cfg->{pg}->{db}
			. (($cfg->{pg}->{host}) ? ';host=' . $cfg->{pg}->{host} : '')
			. (($cfg->{pg}->{port}) ? ';port=' . $cfg->{pg}->{port} : '');
		$pguser = $cfg->{client}->{user};
		$pgpass = $cfg->{client}->{pass};
	} else {
		$pgdsn = $args{pgdsn} or die 'no pgdsn?';
		$pguser = $args{pguser} or die 'no pguser?';
		$pgpass = $args{pgpass} or die 'no pgpass?';
	}
	# make our workername the application_name visible in postgresql
	$ENV{'PGAPPNAME'} = $workername;
	my $pgh = DBI->connect(
		$pgdsn,	$pguser, $pgpass,
		{
			AutoCommit => 1,
			RaiseError => 1,
			PrintError => $args{debug} // 1, # 0?
		}
	) or die "cannot connect to db: $DBI::errstr";
	$pgh->{pg_placeholder_dollaronly} = 1;
	
	return bless {
		cfg => $cfg,
		pgh => $pgh,
		workername => $workername,
		debug => $args{debug} // 1,
		ping => $args{ping} || 60,
		listen => {},
		worker_id => undef,
		'exit' => 0,
	}, $class;
}

sub announce {
	my $self = shift;
	my $actionname = shift or die 'no actionname?';
	my $cb = shift;
	die 'no callback?' unless ref $cb eq 'CODE';
	my @upvals = @_;

	my $pgh = $self->{pgh};
	my ($worker_id, $listenstring);
	local $@;
	eval {
		# announce throws an error when:
		# - workername is not unique
		# - actionname does not exist
		($worker_id, $listenstring) = $pgh->selectrow_array(
			q[select * from announce($1, $2)],
			{},
			$self->{workername},
			$actionname
		);
		die "no result" unless $worker_id;
	};
	if ($@) {
		warn $@;
		return 0;
	}
	$pgh->do('LISTEN ' . $pgh->quote_identifier($listenstring));
	$self->{listen}->{$listenstring} = {
		cb => $cb,
		upvals => \@upvals,
		actionname => $actionname,
	};
	$self->{worker_id} = $worker_id;
	say "registered worker_id $worker_id for action $actionname",
		" with listensting $listenstring" if $self->{debug};
	return 1;
}

sub withdraw {
	my $self = shift;
	my $actionname = shift or die 'no actionname?';
	my ($res) = $self->{pgh}->selectrow_array(
			q[select withdraw($1, $2)],
			{},
			$self->{workername},
			$actionname
		);
	die "no result" unless defined $res;
	return $res;
}

sub work {
	my $self = shift;

	my $poll = IO::Poll->new();
	#open my $pgfd, '<&', $self->{pgh}->{pg_socket} or die "Can't dup: $!";
	open my $pgfd, '<&=', $self->{pgh}->{pg_socket} or die "Can't fdopen: $!";
	$poll->mask($pgfd => POLLIN);
	my $now = time();
	my $timeout = $now + $self->{ping};

	while (not $self->{exit}) {
		my @not;
		# get all pending notifications
		push @not, $_ while $_ = $self->{pgh}->pg_notifies();
		say "timeout: ", $timeout - $now if $self->{debug};
		unless (@not) {	# poll if there are not notifications waiting
			my $ret = $poll->poll($timeout - $now);
			# we don't actually care about the return code?
			# get all notifications that came in during the poll
			push @not, $_ while $_ = $self->{pgh}->pg_notifies();
		}
		$now = time();
		# execute
		$self->get_task($_) for @not;
		if ($now >= $timeout) {
			$self->ping();
			$timeout = $now + $self->{ping};
		}
	}
}

sub ping {
	my $self = shift;
	say "ping($self->{worker_id})" if $self->{debug};
	$self->{pgh}->ping or die 'connection lost?';
	$self->{pgh}->do(q[select ping($1)], {}, $self->{worker_id});
}

sub get_task {
	my $self = shift;
	my ($channel, $pid, $job_id) = @{$_[0]};
	my $action = $self->{listen}->{$channel};
	return unless $action;
	local $SIG{__WARN__} = sub {
		print STDERR @_ if $self->{debug};
	};
	my $pgh = $self->{pgh};
	say "get_task: workername $self->{workername}, actionname $action->{actionname}, job_id $job_id"
		if $self->{debug};
	# in the stored-procedure low-level api a null value means poll
	# (yeah it's a hack)
	$job_id = undef if $job_id !~ /^\d+/;
	my ($cookie, $inargs);
	($job_id, $cookie, $inargs) = $pgh->selectrow_array(q[select * from get_task($1, $2, $3)], {},
					$self->{workername}, $action->{actionname}, $job_id);
	return unless $cookie;
	say "cookie $cookie inargs $inargs" if $self->{debug};
	$inargs = decode_json( $inargs ); #fixme: eval?
	my $outargs;
	local $@;
	eval {
		$outargs = &{$action->{cb}}($job_id, $inargs);
	};
	$outargs = {'error' => 'something bad happened: ' . $@} if $@;
	eval {
		$outargs = encode_json( $outargs );
	};
	$outargs = {'error' => 'cannot json encde outargs: ' . $@} if $@;
	say "outargs $outargs" if $self->{debug};
	$pgh->do(q[select task_done($1, $2)], {}, $cookie, $outargs);
	say "done with action $action->{actionname} for job $job_id\n" if $self->{debug};
}

1;

=encoding utf8

=head1 NAME

JobCenter::SimpleWorker - simple blocking JobCenter client

=head1 SYNOPSIS

 use JobCenter::SimpleWorker;

 my $client = JobCenter::SimpleWorker->new(
        cfgpath => "$FindBin::Bin/../etc/jobcenter.conf",
        debug => 1,
 );

 my $result = $client->call($wfname, $inargs);

=head1 DESCRIPTION

"JobCenter::SimpleWorker" is a class to build a simple blocking client for the
JobCenter workflow engine. It has minimal (non-core) dependencies.

=head1 METHODS

=head2 new

$client = JobCenter::SimpleWorker->new(%arguments);

Class method that returns a new JobCenter::SimpleWorker object.

Valid arguments are:

=over 4

=item - cfgpath: path to a JobCenter configuration file.

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
