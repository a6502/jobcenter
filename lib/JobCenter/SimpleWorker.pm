package Jobcenter::SimpleWorker;

use strict;
use warnings;
use 5.10.0;

# standard modules
use Data::Dumper;
use FindBin;
use IO::Poll qw(POLLIN);
use Time::HiRes qw(time);

# non standard modules that should be available as packages even on rhel-6
use Config::Tiny;
use DBI;
use DBD::Pg qw(:async);
use JSON qw(decode_json encode_json);

sub new {
	my ($class, %args) = @_;
	die 'no cfgpath?' unless $args{cfgpath};	
	my $workername = $args{workername} ||  "$0 [$$]";
	my $cfg = Config::Tiny->read($args{cfgpath});
	die 'failed to read config ' . $args{cfgpath} . ': ' . Config::Tiny->errstr unless $cfg;
	# make our workername the application_name visible in postgresql
	$ENV{'PGAPPNAME'} = $workername;
	my $pgh = DBI->connect(
		'dbi:Pg:dbname=' . $cfg->{pg}->{db}
		. ';host=' . $cfg->{pg}->{host}
		. ';port=' . $cfg->{pg}->{port},
		$cfg->{client}->{user},
		$cfg->{client}->{pass},
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
	return 1;
}

sub withdraw {
	die 'aaargh';
}

sub work {
	my $self = shift;

	my $poll = IO::Poll->new();
	open my $pgfd, '<&', $self->{pgh}->{pg_socket} or die "Can't dup: $!";
	$poll->mask($pgfd => POLLIN);
	my $now = time();
	my $timeout = $now + $self->{ping};

	while (not $self->{exit}) {
		say "timout: ", $timeout - $now if $self->{debug};
		my $ret = $poll->poll($timeout - $now);
		$now = time();
		if ( $ret == 1 and ($poll->handles( POLLIN ))[0] == $pgfd ) {
			my @not;
			# get all pending notifications
			push @not, $_ while $_ = $self->{pgh}->pg_notifies();
			# execute
			$self->get_task($_) for @not;
		}
		if ( $now >= $timeout ) {
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
	my ($cookie, $vars) = $pgh->selectrow_array(q[select * from get_task($1, $2, $3)], {},
					$self->{workername}, $action->{actionname}, $job_id);
	return unless $cookie;
	say "cookie $cookie invars $vars" if $self->{debug};
	$vars = decode_json( $vars );
	local $@;
	eval {
		&{$action->{cb}}($job_id, $vars);
	};
	$vars = {'error' => 'something bad happened: ' . $@} if $@;
	$vars = encode_json( $vars );
	say "outvars $vars" if $self->{debug};
	$pgh->do(q[select task_done($1, $2)], {}, $cookie, $vars);
	say "done with action $action->{actionname} for job $job_id\n" if $self->{debug};
}


1;
