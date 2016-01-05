package JobCenter::MojoWorker;

#
# Mojo's default reactor uses EV, and EV does not play nice with signals
# without some handholding. We either can try to detect EV and do the
# handholding, or try to prevent Mojo using EV.
#
BEGIN {
	$ENV{'MOJO_REACTOR'} = 'Mojo::Reactor::Poll';
}

# mojo
use Mojo::Base 'Mojo::EventEmitter';
use Mojo::IOLoop;
use Mojo::Pg;
use Mojo::JSON qw(decode_json encode_json);

# standard
use Data::Dumper;
use IO::Pipe;

# other
use Config::Tiny;


has [qw(cfg pg workername debug ping tmr)];

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new();

	die 'no cfgpath?' unless $args{cfgpath};	
	my $workername = $args{workername} ||  "$0 [$$]";
	my $cfg = Config::Tiny->read($args{cfgpath});
	die 'failed to read config ' . $args{cfgpath} . ': ' . Config::Tiny->errstr unless $cfg;


	# make our workername the application_name visible in postgresql
	$ENV{'PGAPPNAME'} = $workername;
	my $pg = Mojo::Pg->new(
		'postgresql://'
		. $cfg->{client}->{user}
		. ':' . $cfg->{client}->{pass}
		. '@' . $cfg->{pg}->{host}
		. ':' . $cfg->{pg}->{port}
		. '/' . $cfg->{pg}->{db}
	);

	$self->{cfg} = $cfg;
	$self->{pg} = $pg;
	$self->{workername} = $workername;
	$self->{debug} = $args{debug} // 1;
	$self->{ping} = $args{ping} || 60;
	return $self;
}

sub announce {
	my $self = shift;
	my $actionname = shift or die 'no actionname?';
	my $cb = shift;
	die 'no callback?' unless ref $cb eq 'CODE';
	my @upvals = @_;

	my ($worker_id, $listenstring);
	local $@;
	eval {
		# announce throws an error when:
		# - workername is not unique
		# - actionname does not exist
		($worker_id, $listenstring) = @{$self->pg->db->dollar_only->query(
			q[select * from announce($1, $2)],
			$self->workername,
			$actionname
		)->array};
		die "no result" unless $worker_id;
	};
	if ($@) {
		warn $@;
		return 0;
	}
	say "worker_id $worker_id listenstring $listenstring" if $self->debug;
	$self->pg->pubsub->listen( $listenstring, sub {
		# use a closure to pass on $cb, $workername and $actionname
		my ($pubsub, $payload) = @_;
		$self->_get_task($cb, \@upvals, $actionname, $payload);
	});
	$self->{worker_id} = $worker_id;
	# set up a ping timer after the first succesfull announce
	unless ($self->tmr) {
		$self->{tmr}  = Mojo::IOLoop->recurring( $self->ping, sub { $self->_ping($worker_id) } );
	}
	return 1;
}

sub work {
	my $self = shift;
	pipe my $reader, my $writer;
	Mojo::IOLoop->singleton->reactor->io($reader => sub { });
	local $SIG{INT} = local $SIG{TERM} = sub {
		say STDERR 'trying to stop...';
		Mojo::IOLoop->stop;
		say $writer 'STOOOP!'
	};
	say "working!";
	Mojo::IOLoop->start;
}

sub withdraw {
	my $self = shift;
	my $actionname = shift or die 'no actionname?';
	my ($res) = $self->pg->db->query(
			q[select withdraw($1, $2)],
			$self->{workername},
			$actionname
		);
	die "no result" unless $res and @$res;
	return $res;
	die 'aaargh';
}

sub _ping {
	my $self = shift;
	my $worker_id = shift;
	say "ping($worker_id)!" if $self->debug;
	$self->pg->db->query(q[select ping($1)], $worker_id, sub {});
}

sub _get_task {
	my ($self, $cb, $upvals, $actionname, $job_id) = @_;
	say "get_task: workername $self->{workername}, actioname $actionname, job_id $job_id" if $self->debug;
	local $SIG{__WARN__} = sub {
		print STDERR @_ if $self->debug;
	};
	local $@;
	eval {
		my $res = $self->pg->db->dollar_only->query(q[select * from get_task($1, $2, $3)], $self->workername, $actionname, $job_id)->array;
		die "no result" unless $res and @$res;
		my ($cookie, $vars) = @$res;
		undef $res; # clear statement handle
		say "cookie $cookie invars $vars" if $self->debug;
		$vars = decode_json( $vars );
		eval {
			&$cb($job_id, $vars);
		};
		$vars = {'error' => 'something bad happened'} if $@;
		$vars = encode_json( $vars );
		say "outvars $vars" if $self->debug;
		$self->pg->db->dollar_only->query(q[select task_done($1, $2)], $cookie, $vars); #, sub { say 'yaaj!'} );
		say "done with action $actionname for job $job_id\n" if $self->debug;
	};
	say $@ if $@;
}

1;
