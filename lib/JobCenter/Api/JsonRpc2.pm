package JobCenter::Api::JsonRpc2;

use strict;
use warnings;
use 5.10.0;

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
#use Mojo::JSON qw(decode_json encode_json);
use Mojo::Log;
use Mojo::Pg;

# standard
use Cwd qw(realpath);
use Data::Dumper;
use File::Basename;
use FindBin;
use IO::Pipe;
use Scalar::Util qw(refaddr);

# cpan
use Config::Tiny;
use JSON::MaybeXS;

use JSON::RPC2::TwoWay;

# JobCenter
use JobCenter::Api::Client;
use JobCenter::Api::Job;
use JobCenter::Api::Task;
use JobCenter::Util;

has [qw(
	actionnames
	apiname
	cfg
	clients
	daemon
	debug
	listenstrings
	log
	pg
	pid_file
	ping
	server
	rpc
	tasks
	timeout
	tmr
	users
)];

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new();

	my $cfg;
	if ($args{cfgpath}) {
		$cfg = Config::Tiny->read($args{cfgpath});
		die 'failed to read config ' . $args{cfgpath} . ': ' . Config::Tiny->errstr unless $cfg;
	} else {
		die 'no cfgpath?';
	}

	my $apiname = ($args{apiname} || fileparse($0)) . " [$$]";
	my $daemon = $args{daemon} // 0; # or 1?
	my $debug = $args{debug} // 0; # or 1?
	my $log = $args{log} // Mojo::Log->new();
	$log->path(realpath("$FindBin::Bin/../log/$apiname.log")) if $daemon;

	my $pid_file = $cfg->{pid_file} // realpath("$FindBin::Bin/../log/$apiname.pid");
	die "$apiname already running?" if $daemon and check_pid($pid_file);

	# make our clientname the application_name visible in postgresql
	$ENV{'PGAPPNAME'} = $apiname;
	my $pg = Mojo::Pg->new(
		'postgresql://'
		. $cfg->{api}->{user}
		. ':' . $cfg->{api}->{pass}
		. '@' . $cfg->{pg}->{host}
		. ':' . $cfg->{pg}->{port}
		. '/' . $cfg->{pg}->{db}
	) or die 'no pg?';

	my $rpc = JSON::RPC2::TwoWay->new(debug => $debug) or die 'no rpc?';

	$rpc->register('announce', sub { $self->rpc_announce(@_) }, non_blocking => 0, state => 'auth');
	$rpc->register('create_job', sub { $self->rpc_create_job(@_) }, non_blocking => 0, state => 'auth');
	$rpc->register('get_job_status', sub { $self->rpc_get_job_status(@_) }, state => 'auth');
	$rpc->register('get_task', sub { $self->rpc_get_task(@_) }, state => 'auth');
	$rpc->register('hello', sub { $self->rpc_hello(@_) });
	$rpc->register('task_done', sub { $self->rpc_task_done(@_) }, notification => 1, state => 'auth');
	$rpc->register('withdraw', sub { $self->rpc_withdraw(@_) }, state => 'auth');

	my $server = Mojo::IOLoop->server(
		{port => ($cfg->{api}->{listenport})}
		=> sub {
			my ($loop, $stream, $id) = @_;
			my $client = JobCenter::Api::Client->new($rpc, $stream, $id);
			$client->on(close => sub { $self->_disconnect($client) });
		}
	) or die 'no server?';

	# keep sorted
	#$self->cfg($cfg);
	$self->{actionnames} = {};
	$self->{cfg} = $cfg;
	$self->{apiname} = $apiname;
	$self->{daemon} = $daemon;
	$self->{debug} = $debug;
	$self->{listenstrings} = {};
	$self->{log} = $log;
	$self->{pg} = $pg;
	$self->{pid_file} = $pid_file if $daemon;
	$self->{ping} = $args{ping} || 60;
	$self->{server} = $server;
	$self->{rpc} = $rpc;
	$self->{users} = {
		'deKlant' => 'wilDingen',
		'derKunde' => 'willDinge',
		'theCustomer' => 'wantsThings',
		'deWerknemer' => 'doetDingen',
		'derArbeitnehmer' => 'machtDinge',
		'theEmployee' => 'doesThings',
	};
	$self->{tasks} = {};
	$self->{timeout} = $args{timeout} // 60; # 0 is a valid timeout?

	# add a catch all error handler..
	$self->catch(sub { my ($self, $err) = @_; warn "This looks bad: $err"; });

	return $self;
}

sub work {
	my ($self) = @_;
	if ($self->daemon) {
		daemonize();
	}

	# set up a connection to test things
	# this also means that our first pg connection is only used for
	# notifications.. this seems to save some memory on the pg side
	$self->pg->pubsub->listen($self->apiname, sub {
		say 'ohnoes!';
		exit(1);
	});

	$self->log->debug('JobCenter::Api::JsonRpc starting work');
	Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
	#my $reactor = Mojo::IOLoop->singleton->reactor;
	#$reactor->{running}++;
	#while($reactor->{running}) {
	#	$reactor->one_tick();
	#}
	$self->log->debug('JobCenter::Api::JsonRpc done?');

	return 0;
}

sub _disconnect {
	my ($self, $client) = @_;
	$self->log->info('oh my.... ' . ($client->who // 'somebody') . ' disonnected..');
	return unless $client->who;

	my @actions = (@{$client->actions}); # make a copy to loop over
	
	for my $a (@actions) {
		$self->log->debug("withdrawing $a");
		# hack.. make a _withdraw for this..?
		$self->rpc_withdraw($client->con, {actionname => $a});
	}
}

sub rpc_hello {
	my ($self, $con, $args) = @_;
	my $client = $con->owner;
	my $who = $args->{who} or die "no who?";
	my $method = $args->{method} or die "no method?";
	die "unknown authentication method $method" unless $method eq 'password';
	my $token = $args->{token} or die "no token?";
	if ($self->users->{$who} and $self->users->{$who} eq $token) {	
		$self->log->debug("got hello from $who token $token");
		$client->who($who);
		$con->state('auth');
		return JSON->true, "welcome to the clientapi $who!";
	} else {
		$self->log->debug("hello failed for $who");
		$con->state(undef);
		# close the connecion after sending the response
		Mojo::IOLoop->next_tick(sub {
			$client->close;
		});
		return JSON->false, 'you\'re not welcome!';
	}
}

sub rpc_create_job {
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	#$self->log->debug('create_job: ' . Dumper(\@_));
	my %a;
	$a{$_} = $i->{$_} for (qw(wfname inargs vtag));
	$a{impersonate} = $client->who;
	$a{cb} = sub {
		my ($job_id, $outargs) = @_;
		$con->notify('job_done', {job_id => $job_id, outargs => $outargs});
	};
	my $job_id;
	$job_id = $self->_call_nb(%a);
	return $job_id;
}

sub rpc_get_job_status {
	die 'aaargh, implement me!';
}

sub _poll_done {
	my ($self, $job) = @_;
	my $res = $self->pg->db->dollar_only->query(q[select * from get_job_status($1)], $job->job_id)->array;
	return unless $res and @$res and @$res[0];
	my $outargs = @$res[0];
	$self->pg->pubsub->unlisten($job->listenstring);
	Mojo::IOLoop->remove($job->tmr) if $job->tmr;
	unless ($self->{json}) {
		$outargs = decode_json($outargs);
	}
	if ($job->cb) {
		$self->log->debug("calling cb $job->{cb} for job_id $job->{job_id} outargs $outargs");
		local $@;
		eval { $job->cb->($job->{job_id}, $outargs); };
		$self->log->debug("got $@ calling callback") if $@;
	}
	return $outargs; # at least true
}

#sub call {
#	my ($self, %args) = @_;
#	my ($done, $job_id, $outargs);
#	$args{cb} = sub {
#		($job_id, $outargs) = @_;
#		$done++;
#	};
#	$self->call_nb(%args);
#
#	Mojo::IOLoop->one_tick while !$done;
#	
#	return $job_id, $outargs;
#}

sub _call_nb {
	my ($self, %args) = @_;
	my $wfname = $args{wfname} or die 'no workflowname?';
	my $inargs = $args{inargs} // '{}';
	my $vtag = $args{vtag};
	my $impersonate = $args{impersonate};
	my $cb = $args{cb} or die 'no callback?';
	my $timeout = $args{timeout} // 60;

	#if ($self->{json}) {
	#	# sanity check json string
	#	my $inargsp = decode_json($inargs);
	#	die 'inargs is not a json object' unless ref $inargsp eq 'HASH';
	#} else {
		die  'inargs should be a hashref' unless ref $inargs eq 'HASH';
		$inargs = encode_json($inargs);
		#$self->log->debug("inargs as json: $inargs");
	#}

	$self->log->debug("calling $wfname with '$inargs'" . (($vtag) ? " (vtag $vtag)" : ''));
	#say "inargs: $inargs";
	my ($job_id, $listenstring);
	# create_job throws an error when:
	# - wfname does not exist
	# - inargs not valid
	($job_id, $listenstring) = @{$self->pg->db->dollar_only->query(
		q[select * from create_job(wfname := $1, args := $2, tag := $3, impersonate := $4)],
		$wfname,
		$inargs,
		$vtag,
		$impersonate
	)->array};
	die "no result from call to create_job" unless $job_id;
	$self->log->debug("created job_id $job_id listenstring $listenstring");

	my $job = JobCenter::Api::Job->new(
		#cb => $cb,
		job_id => $job_id,
		inargs => $inargs,
		listenstring => $listenstring,
		vtag => $vtag,
		wfname => $wfname,
	);

	$self->pg->pubsub->listen($listenstring, sub {
		#my ($pubsub, $payload) = @_;
		local $@;
		eval { $self->_poll_done($job); };
		$self->log->debug("pubsub cb $@") if $@;
	});

	# do one poll first..
	my $out = $self->_poll_done($job);

	if ($out) {
		# schedule the callback to run soonish
		Mojo::IOLoop->next_tick(sub {
			&$cb($job_id, $out);
		})
	} else {
		# set up timeout
		my $tmr = Mojo::IOLoop->timer($timeout => sub {
			# request failed, cleanup
			$self->pg->pubsub->unlisten($listenstring);
			&$cb($job_id, {'error' => 'timeout'});
		});
		$job->update(cb => $cb, tmr => $tmr);
	}

	return $job_id;
}

sub rpc_announce {
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	my $actionname = $i->{actionname} or die 'actionname required';
	my $slots      = $i->{slots} // 1;


	my ($worker_id, $listenstring);
	local $@;
	eval {
		# announce throws an error when:
		# - workername is not unique
		# - actionname does not exist
		# - worker has already announced action
		($worker_id, $listenstring) = @{$self->pg->db->dollar_only->query(
			q[select * from announce($1, $2, $3)],
			$client->who,
			$actionname,
			$client->who
		)->array};
		die "no result" unless $worker_id;
	};
	if ($@) {
		warn $@;
		return JSON->false, $@;
	}
	$self->log->debug("worker_id $worker_id listenstring $listenstring");

	unless ($self->listenstrings->{$listenstring}) {
		# oooh.. a totally new action
		$self->log->debug("listen $listenstring");
		$self->pg->pubsub->listen( $listenstring, sub {
			my ($pubsub, $payload) = @_;
			local $@;
			eval { $self->_task_ready($listenstring, $payload) };
			warn $@ if $@;
		});
		# assumption 1:1 relation actionname:listenstring
		$self->actionnames->{$actionname} = $listenstring;
		$self->listenstrings->{$listenstring} = [];
	}		

	$client->worker_id($worker_id);
	push @{$client->actions}, $actionname;
	# note that this client is interested in this listenstring
	push @{$self->listenstrings->{$listenstring}}, [$client, $actionname, $slots];

	# set up a ping timer to the client after the first succesfull announce
	unless ($client->tmr) {
		$client->{tmr} = Mojo::IOLoop->recurring( $client->ping, sub { $self->_ping($client) } );
	}
	return JSON->true, 'success';
}

sub rpc_withdraw {
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	my $actionname = $i->{actionname} or die 'actionname required';
	# find listenstring by actionname
	my $listenstring = $self->actionnames->{$actionname} or die "unknown actionname";

	my ($res) = $self->pg->db->query(
			q[select withdraw($1, $2)],
			$client->who,
			$actionname
		)->array;
	die "no result" unless $res and @$res;
	
	# now remove this client from the listenstring client list
	my $l = $self->listenstrings->{$listenstring};
	my @idx = grep { refaddr $$l[$_][0] == refaddr $client } 0..$#$l;
	splice @$l, $_, 1 for @idx;
	
	# delete if the listenstring client list is now empty
	unless (@$l) {
		delete $self->listenstrings->{$listenstring};
		delete $self->actionnames->{$actionname};
		$self->pg->pubsub->unlisten($listenstring);
		$self->log->debug("unlisten $listenstring");
	}		

	# remove this action from the cliens action list
	my $a = $client->actions;
	#@idx = grep { $$a[$_] eq $actionname } 0..$#$a;	
	#splice @$a, $_, 1 for @idx;
	my @a = grep { $_ ne $actionname } @$a;
	$client->{actions} = \@a;

	if (not @a and $client->{tmr}) {
		# cleanup ping timer if client has no more actions
		$self->log->debug("remove tmr $client->{tmr}");
		Mojo::IOLoop->remove($client->{tmr});
		delete $client->{tmr};
	}

	return 1;
}

sub _ping {
	my ($self, $client) = @_;
	my $tmr;
	Mojo::IOLoop->delay->steps(sub {
		my $d = shift;
		my $e = $d->begin;
		$tmr = Mojo::IOLoop->timer(3 => sub { $e->(@_, 'timeout') } );
		$client->con->call('ping', {}, sub { $e->($client, @_) });
	},
	sub {
		my ($d, $e, $r) = @_;
		#print 'got ', Dumper(\@_);
		if ($e and $e eq 'timeout') {
			$self->log->info('uhoh, ping timeout for ' . $client->who);
			Mojo::IOLoop->remove($client->id); # disconnect
		} else {
			if ($e) {
				$self->log->debug("'got $e->{message} ($e->{code}) from $client->{who}");
				return;
			}
			$self->log->debug('got ' . $r . ' from ' . $client->who . ' : ping(' . $client->worker_id . ')');
			Mojo::IOLoop->remove($tmr);
			$self->pg->db->query(q[select ping($1)], $client->worker_id, $d->begin);
		}
	});
}

sub _task_ready {
	my ($self, $listenstring, $job_id) = @_;
	
	$self->log->debug("got notify $listenstring for $job_id");
	my $l = $self->listenstrings->{$listenstring};
	# rotate listenstrings list
	my $c = shift @$l;
	push @$l, $c;

	my ($client, $actionname, $slots) = @$c;

	$client->con->notify('task_ready', {actionname => $actionname, job_id => $job_id});

	my $tmr =  Mojo::IOLoop->timer(3 => sub { $self->_task_ready_next($job_id) } );

	my $task = JobCenter::Api::Task->new(
		actionname => $actionname,
		client => $client,
		job_id => $job_id,
		listenstring => $listenstring,
		tmr => $tmr,
	);
	$self->{tasks}->{$job_id} = $task;
}

sub _task_ready_next {
	my ($self, $job_id) = @_;
	
	my $task = $self->{tasks}->{$job_id} or die 'no task in _task_ready_next?';
	
	$self->log->debug("try next client for $task->{listenstring} for $task->{job_id}");
	my $l = $self->listenstrings->{$task->listenstring};
	# rotate listenstrings list
	my $c = shift @$l;
	push @$l, $c;

	my ($client, $actionname, $slots) = @$c;

	if (refaddr $client == refaddr $task->client) {
		# hmmm...
		return;
	}

	$client->con->notify('task_ready', {actionname => $actionname, job_id => $job_id});

	my $tmr =  Mojo::IOLoop->timer(3 => sub { $self->_task_ready_next($job_id) } );

	$task->update(
		client => $client,
		tmr => $tmr,
		job_id => $job_id,
	);
}

sub rpc_get_task {
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	my $workername = $client->who;
	my $actionname = $i->{actionname};
	my $job_id = $i->{job_id};
	$self->log->debug("get_task: workername $workername, actioname $actionname, job_id $job_id");

	my $task = delete $self->{tasks}->{$job_id};
	return unless $task;

	Mojo::IOLoop->remove($task->tmr) if $task->tmr;
	
	local $SIG{__WARN__} = sub {
		$self->log->debug($_[0]);
	};
	my $res = $self->pg->db->dollar_only->query(q[select * from get_task($1, $2, $3)], $workername, $actionname, $job_id)->array;
	return unless $res and @$res;
	my ($cookie, $inargs) = @$res;
	undef $res; # clear statement handle
	$self->log->debug("cookie $cookie inargs $inargs");
	$inargs = decode_json( $inargs ); # unless $self->json;

	my $tmr =  Mojo::IOLoop->timer($self->timeout => sub { $self->_task_timeout($cookie) } );

	$task->update(
		cookie => $cookie,
		inargs => $inargs,
		tmr => $tmr,
	);
	$self->{tasks}->{$cookie} = $task;

	return ($cookie, $inargs);
}

sub rpc_task_done {
	#my ($self, $task, $outargs) = @_;
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	my $cookie = $i->{cookie} or die 'no cookie?';
	my $outargs = $i->{outargs} or die 'no outargs?';

	my $task = delete $self->{tasks}->{$cookie};
	return unless $task; # really?	
	Mojo::IOLoop->remove($task->tmr) if $task->tmr;

	local $@;
	eval {
		$outargs = encode_json( $outargs );
	};
	$outargs = encode_json({'error' => 'cannot json encode outargs: ' . $@}) if $@;
	#$self->log->debug("outargs $outargs");
	eval {
		$self->pg->db->dollar_only->query(q[select task_done($1, $2)], $cookie, $outargs, sub { 1; } );
	};
	$self->log->debug("task_done got $@") if $@;
	$self->log->debug("worker $client->{who} done with action $task->{actionname} for job $task->{job_id} outargs $outargs\n");
	return;
}

1;
