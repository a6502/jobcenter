package JobCenter::MojoWorker;

#
# Mojo's default reactor uses EV, and EV does not play nice with signals
# without some handholding. We either can try to detect EV and do the
# handholding, or try to prevent Mojo using EV.
#
BEGIN {
	$ENV{'MOJO_REACTOR'} = 'Mojo::Reactor::Poll';
}

use strict;
use warnings;

# mojo
use Mojo::Base 'Mojo::EventEmitter';
use Mojo::IOLoop;
use Mojo::JSON qw(decode_json encode_json);
use Mojo::Log;
use Mojo::Pg;

# standard
use Cwd qw(realpath);
use Data::Dumper;
use File::Basename;
use FindBin;
use IO::Pipe;

# other
use Config::Tiny;

# jobcenter
use JobCenter::MojoWorker::Task;
use JobCenter::Util;

has [qw(cfg daemon debug json log pg pid_file ping tmr worker_id workername)];

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new();

	my $cfg;
	if ($args{cfg}) {
		$cfg = $args{cfg};
	} elsif ($args{cfgpath}) {
		$cfg = Config::Tiny->read($args{cfgpath});
		die 'failed to read config ' . $args{cfgpath} . ': ' . Config::Tiny->errstr unless $cfg;
	} else {
		die 'no cfg or cfgpath?';
	}

	my $workername = $args{workername} || fileparse($0);
	my $pid_file = $cfg->{pid_file} // realpath("$FindBin::Bin/../log/$workername.pid");
	die "$workername already running?" if check_pid($pid_file);

	# make our workername the application_name visible in postgresql
	$ENV{'PGAPPNAME'} = $workername . " [$$]" unless $ENV{'PGAPPNAME'};
	my $pg = Mojo::Pg->new(
		'postgresql://'
		. $cfg->{client}->{user}
		. ':' . $cfg->{client}->{pass}
		. '@' . ( $cfg->{pg}->{host} // '' )
		. ( ($cfg->{pg}->{port}) ? ':' . $cfg->{pg}->{port} : '' )
		. '/' . $cfg->{pg}->{db}
	);

	$self->{cfg} = $cfg;
	$self->{daemon} = $args{daemon} // 1;
	$self->{debug} = $args{debug} // 1;
	$self->{json} = $args{json} // 0;
	$self->{log} = Mojo::Log->new;
	$self->{pg} = $pg;
	$self->{pid_file} = $pid_file;
	$self->{ping} = $args{ping} || 60;
	$self->{workername} = $workername . " [$$]";
	#say Dumper(\%args);
	#say Dumper($self);
	if ($self->daemon) {
		# fixme: get from config?
		$self->log->path(realpath("$FindBin::Bin/../log/$workername.log"));
		daemonize();
	}
	return $self;
}

sub announce {
	my $self = shift;
	return $self->announce_worker($self->workername, @_);
}

sub announce_worker {
	my $self = shift;
	my $workername = shift or die 'no workername?';
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
			$workername,
			$actionname
		)->array};
		die "no result" unless $worker_id;
	};
	if ($@) {
		warn $@;
		return 0;
	}
	$self->log->debug("worker_id $worker_id listenstring $listenstring");
	$self->pg->pubsub->listen( $listenstring, sub {
		# use a closure to pass on cb, upvals and actionname
		my ($pubsub, $payload) = @_;
		$self->_get_task($cb, \@upvals, $workername, $actionname, $payload);
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
	ensure_pid_file($self->pid_file, $self->log);

	# set up a pipe we can create a io event on when we get a signal
	pipe my $reader, my $writer;
	Mojo::IOLoop->singleton->reactor->io($reader => sub { });
	local $SIG{INT} = local $SIG{TERM} = sub {
		$self->log->info('trying to stop...');
		Mojo::IOLoop->stop;
		say $writer 'STOOOP!'
	};

	$self->log->info($self->workername . ' working!');
	Mojo::IOLoop->start;
	$self->log->info($self->workername . ' stopping');
}

sub withdraw {
	my $self = shift;
	my $actionname = shift or die 'no actionname?';
	my ($res) = $self->pg->db->query(
			q[select withdraw($1, $2)],
			$self->workername,
			$actionname
		)->array;
	die "no result" unless $res and @$res;
	return $res;
}

sub _ping {
	my $self = shift;
	my $worker_id = shift;
	$self->log->debug("ping($worker_id)!");
	$self->pg->db->query(q[select ping($1)], $worker_id, sub {});
}

sub _get_task {
	my ($self, $cb, $upvals, $workername, $actionname, $job_id) = @_;
	$self->log->debug("get_task: workername $workername, actioname $actionname, job_id $job_id");
	local $SIG{__WARN__} = sub {
		$self->log->debug($_[0]);
	};
	my $res = $self->pg->db->dollar_only->query(q[select * from get_task($1, $2, $3)], $workername, $actionname, $job_id)->array;
	return unless $res and @$res;
	my ($cookie, $inargs) = @$res;
	undef $res; # clear statement handle
	$self->log->debug("cookie $cookie inargs $inargs");
	$inargs = decode_json( $inargs ) unless $self->json;
	my $task = JobCenter::MojoWorker::Task->new(
		workername => $workername,
		actionname => $actionname,
		cookie => $cookie,
		job_id => $job_id,
	);
	my $outargs;
	local $@;
	eval {
		$outargs = &$cb(@$upvals, $job_id, $inargs, sub {
			say 'gonna call task_done!', Dumper(\$_[0]);
			# closure to pass on the task..
			$self->_task_done($task, $_[0]);
		});
	};
	$outargs = {'error' => 'something bad happened: ' . $@} if $@;
	return unless $outargs;
	$self->_task_done($task, $outargs);
}

sub _task_done {
	my ($self, $task, $outargs) = @_;
	local $@;
	unless ($self->json) {
		eval {
			$outargs = encode_json( $outargs );
		};
		$outargs = encode_json({'error' => 'cannot json encode outargs: ' . $@}) if $@;
	}
	#$self->log->debug("outargs $outargs");
	eval {
		$self->pg->db->dollar_only->query(q[select task_done($1, $2)], $task->cookie, $outargs, sub { 1; } );
	};
	$self->log->debug("_task_done got $@") if $@;
	$self->log->debug("worker $task->{workername} done with action $task->{actionname} for job $task->{job_id}, outargs $outargs\n");
}


1;
