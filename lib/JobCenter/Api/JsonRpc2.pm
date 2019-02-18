package JobCenter::Api::JsonRpc2;

#
# Mojo's default reactor uses EV, and EV does not play nice with signals
# without some handholding. We either can try to detect EV and do the
# handholding, or try to prevent Mojo using EV.
#
BEGIN {
	$ENV{'MOJO_REACTOR'} = 'Mojo::Reactor::Poll';
}

# mojo
use Mojo::Base -base;
use Mojo::IOLoop;
use Mojo::Log;

# standard
use Cwd qw(realpath);
use Data::Dumper;
use Encode qw(encode_utf8 decode_utf8);
use File::Basename;
use FindBin;
use Scalar::Util qw(refaddr);

# cpan
use Config::Tiny;
use JSON::MaybeXS;
use JSON::RPC2::TwoWay;

# JobCenter
use JobCenter::Api::Auth;
use JobCenter::Api::Job;
use JobCenter::Api::Task;
use JobCenter::Api::WorkerAction;
use JobCenter::Pg;
use JobCenter::Api::Server;

has [qw(
	actionnames
	apiname
	auth
	cfg
	clients
	daemon
	debug
	jcpg
	jobs
	listenstrings
	log
	pending
	pid_file
	ping
	pqq
	servers
	rpc
	tasks
	timeout
	tmr
)];

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new();

	my $cfg;
	die 'no cfgpath?' unless $args{cfgpath};
	$cfg = $self->{cfg} = Config::Tiny->read($args{cfgpath});
	die 'failed to read config ' . $args{cfgpath} . ': ' . Config::Tiny->errstr unless $cfg;

	my $apiname = $self->{apiname} = ($args{apiname} || fileparse($0)) . " [$$]";
	my $debug = $self->{debug} = $args{debug} // 0; # or 1?
	my $log = $self->{log} = $args{log} // Mojo::Log->new();

	#$log->path(realpath("$FindBin::Bin/../log/$apiname.log")) if $daemon;
	#my $pid_file = $cfg->{pid_file} // realpath("$FindBin::Bin/../log/$apiname.pid");
	#die "$apiname already running?" if $daemon and check_pid($pid_file);

	# make our clientname the application_name visible in postgresql
	$ENV{'PGAPPNAME'} = $apiname;
	my $jcpg = $self->{jcpg} = JobCenter::Pg->new(
		'postgresql://'
		. $cfg->{api}->{user}
		. ':' . $cfg->{api}->{pass}
		. '@' . ( $cfg->{pg}->{host} // '' )
		. ( ($cfg->{pg}->{port}) ? ':' . $cfg->{pg}->{port} : '' )
		. '/' . $cfg->{pg}->{db}
	) or die 'no pg?';
	$jcpg->max_total_connections($cfg->{pg}->{con} // 5); # sane value?

	if ($debug) {
		# pg log messages come as perl warnings, so log warnings
		$SIG{__WARN__} = sub {
			my $w = decode_utf8($_[0]);
			$w =~ s/\n$//; $w =~ s/\n/ \\n /;
			$log->warn($w)
		};
	}

	$jcpg->on(connection => sub {
		my ($jcpg, $dbh) = @_;
		return unless $debug;
		#$dbh->trace('DBD');
		$dbh->{PrintWarn} = 1; # pg log messages are warnings too
		$dbh->do("select set_config('client_min_messages', 'log', false)");
		$log->debug("jcpg: $jcpg has new connection: $dbh");
	});

	# set up 1 central listen
	# this tests the pg connection as well
	$self->{jobs} = {}; # jobs we are waiting for
	$jcpg->pubsub->listen('job:finished', sub {
		my ($pubsub, $payload) = @_;
		$self->log->debug("notify job:finished $payload");
		#print 'jobs: ', Dumper($self->{jobs});
		my $job = $self->{jobs}->{$payload};
		return unless $job;
		local $@;
		eval { $job->{lcb}->($self, $job); };
		$self->log->debug("pubsub cb $@") if $@;
	});

	my $rpc = $self->{rpc} = JSON::RPC2::TwoWay->new(debug => $debug) or die 'no rpc?';

	$rpc->register('announce', sub { $self->rpc_announce(@_) }, non_blocking => 1, state => 'auth');
	$rpc->register('create_job', sub { $self->rpc_create_job(@_) }, non_blocking => 1, state => 'auth');
	$rpc->register('find_jobs', sub { $self->rpc_find_jobs(@_) }, non_blocking => 1, state => 'auth');
	$rpc->register('get_api_status', sub { $self->rpc_get_api_status(@_) }, state => 'auth');
	$rpc->register('get_job_status', sub { $self->rpc_get_job_status(@_) }, non_blocking => 1, state => 'auth');
	$rpc->register('get_task', sub { $self->rpc_get_task(@_) }, non_blocking => 1, state => 'auth');
	$rpc->register('hello', sub { $self->rpc_hello(@_) }, non_blocking => 1);
	$rpc->register('ping', sub { $self->rpc_ping(@_) });
	$rpc->register('task_done', sub { $self->rpc_task_done(@_) }, notification => 1, state => 'auth');
	$rpc->register('withdraw', sub { $self->rpc_withdraw(@_) }, state => 'auth');

	$self->{auth} = JobCenter::Api::Auth->new(
		$cfg, 'api|auth',
	) or die 'no auth?';

	my @servers;
	die "no listen configuration?" unless ref $cfg->{'api|listen'} eq 'HASH';
	for my $l (keys %{$cfg->{'api|listen'}}) {

		my $lc = $cfg->{"api|listen|$l"} or
			die "no listen configuration for $l?";

		push @servers, JobCenter::Api::Server->new($self, $l, $lc);
	}

	# keep sorted
	$self->{actionnames} = {};
	$self->{clients} = {};
	$self->{listenstrings} = {}; # connected workers, grouped by listenstring
	$self->{pending} = {}; # pending tasks flags for listenstrings
	$self->{ping} = $args{ping} || 60;
	$self->{pqq} = undef; # ping query queue
	$self->{servers} = \@servers;
	$self->{tasks} = {};
	$self->{timeout} = $args{timeout} // 60; # 0 is a valid timeout?

	return $self;
}


sub work {
	my ($self) = @_;

	local $SIG{TERM} = local $SIG{INT} = sub {
		$self->_shutdown(@_);
	};

	$self->log->debug('JobCenter::Api::JsonRpc starting work');
	Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
	#my $reactor = Mojo::IOLoop->singleton->reactor;
	#$reactor->{running}++;
	#while($reactor->{running}) {
	#	$reactor->one_tick();
	#}
	$self->log->info('JobCenter::Api::JsonRpc done?');

	return 0;
}

sub _unlisten_client_action {
	my ($self, $client, $action) = @_;
	#
	# remove this action from the clients action list
	my $wa = delete $client->actions->{$action} 
		or die "worker action not found: $action";

	my $listenstring = $wa->listenstring or die "unknown listenstring";

	# now remove this workeraction from the listenstring workeraction list
	my $l = $self->listenstrings->{$listenstring};
	my @idx = grep { refaddr $$l[$_] == refaddr $wa } 0..$#$l;
	splice @$l, $_, 1 for @idx;

	# delete if the listenstring client list is now empty
	unless (@$l) {
		delete $self->listenstrings->{$listenstring};
		delete $self->actionnames->{$action};
		# not much we can do about pending jobs now..
		delete $self->pending->{$listenstring};
		$self->jcpg->pubsub->unlisten($listenstring);
		$self->log->debug("unlisten $listenstring");
	}
}


sub _disconnect {
	my ($self, $client) = @_;
	$self->log->info('oh my.... ' . ($client->who // 'somebody')
		. ' (' . $client->from. ') disonnected..');

	return unless $client->who;

	if ($client->worker_id) {
		# the client was a worker at some point..
		# let's assume things are initialized correctly
		$self->log->debug("worker gone processing $client->{workername}");

		# clean up actions
		for my $action (keys %{$client->actions}) {
			$self->_unlisten_client_action($client, $action);
		}

		# todo: non-blocking?
		my ($res) = $self->jcpg->db->dollar_only->query(
				q[select disconnect($1)],
				$client->workername,
			)->array;
		die "no result" unless $res and @$res;
	}

	# the client might have a active timer if it was a worker
	if (my $tmr = delete $client->{tmr}) {
		# cleanup ping timer
		Mojo::IOLoop->remove($tmr);
	}

	delete $self->clients->{refaddr($client)};
}


sub rpc_ping {
        my ($self, $c, $i, $rpccb) = @_;
        return 'pong?';
}


sub rpc_hello {
	my ($self, $con, $args, $rpccb) = @_;
	my $client = $con->owner;
	my $who = $args->{who} or die "no who?";
	my $method = $args->{method} or die "no method?";
	my $token = $args->{token} or die "no token?";

	$self->auth->authenticate($method, $client, $who, $token, sub {
		my ($res, $msg, $reqauth) = @_;
		if ($res) {
			$self->log->debug("hello from $who succeeded: method $method msg $msg");
			$client->who($who);
			$client->reqauth($reqauth);
			$con->state('auth');
			$rpccb->(JSON->true, "welcome to the clientapi $who!");
		} else {
			$self->log->debug("hello failed for $who: method $method msg $msg");
			$con->state(undef);
			# close the connecion after sending the response
			Mojo::IOLoop->next_tick(sub {
				$client->close;
			});
			$rpccb->(JSON->false, 'you\'re not welcome!');
		}
	});
}


sub rpc_create_job {
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	#$self->log->debug('create_job: ' . Dumper(\@_));
	my $wfname = $i->{wfname} or die 'no workflowname?';
	my $inargs = $i->{inargs} // '{}';
	my $vtag = $i->{vtag};
	my $timeout = $i->{timeout} // 60;
	my $impersonate = $client->who;
	my $env;
	if ($client->reqauth) {
		my ($res, $log, $authscope) = $client->reqauth->request_authentication($client, $i->{reqauth});
		unless ($res) {
			$rpccb->(undef, $log);
			return;
		}
		$env = decode_utf8(encode_json({authscope => $authscope}));
	}
	my $cb = sub {
		my ($job_id, $outargs) = @_;
		$con->notify('job_done', {job_id => $job_id, outargs => $outargs})
			if %$con; # mild hack: the con object will be empty when
			          # the client is already disconnected
	};

	die  'inargs should be a hashref' unless ref $inargs eq 'HASH';
	$inargs = decode_utf8(encode_json($inargs));

	$self->log->debug("calling $wfname with '$inargs'" . (($vtag) ? " (vtag $vtag)" : ''));

	# create_job throws an error when:
	# - wfname does not exist
	# - inargs not valid
	Mojo::IOLoop->delay(
		sub {
			my ($d) = @_;
			$self->jcpg->queue_query($d->begin(0));
		},
		sub {
			my ($d, $db) = @_;
			#($job_id, $listenstring) = @{
			$db->dollar_only->query(
				q[select * from create_job(wfname := $1, args := $2, tag := $3, impersonate := $4, env := $5)],
				$wfname,
				$inargs,
				$vtag,
				$impersonate,
				$env,
				$d->begin
			);
		},
		sub {
			my ($d, $err, $res) = @_;

			if ($err) {
				$rpccb->(undef, $err);
				return;
			}
			my ($job_id, $listenstring) = @{$res->array};
			$res->finish; # free up db con..
			unless ($job_id) {
				$rpccb->(undef, "no result from call to create_job");
				return;
			}

			# report back to our caller immediately
			# this prevents the job_done notification overtaking the 
			# 'job created' result...
			$self->log->debug("created job_id $job_id listenstring $listenstring");
			$rpccb->($job_id, undef);

			my $job = JobCenter::Api::Job->new(
				cb => $cb,
				job_id => $job_id,
				inargs => $inargs,
				listenstring => $listenstring,
				vtag => $vtag,
				wfname => $wfname,
			);

			# register for the central job finished listen
			$self->{jobs}->{$job_id} = $job;

			my $tmr;
			$tmr = Mojo::IOLoop->timer($timeout => sub {
				# request failed, cleanup
				delete $self->{jobs}->{$job_id};
				# the cb might fail if the connection is gone..
				eval { &$cb($job_id, {'error' => 'timeout'}); };
				$job->delete;
			}) if $timeout > 0;
			#$self->log->debug("setting tmr: $tmr") if $tmr;

			$job->update(tmr => $tmr, lcb => \&_poll_done);

			# do one poll first..
			$self->_poll_done($job);
		}
	)->catch(sub {
		my ($err) = @_;
		$rpccb->(undef, $err);
	});
}


sub _poll_done {
	my ($self, $job) = @_;
	Mojo::IOLoop->delay(
		sub {
			my ($d) = @_;
			$self->jcpg->queue_query($d->begin(0));
		},
		sub {
			my ($d, $db) = @_;
			$db->dollar_only->query(
				q[select * from get_job_status($1)],
				$job->job_id,
				$d->begin
			);
		},
		sub {
			my ($d, $err, $res) = @_;
			die $err if $err;
			my ($outargs) = @{$res->array};
			$res->finish;
			return unless $outargs;
			delete $self->{jobs}->{$job->{job_id}};
			Mojo::IOLoop->remove($job->tmr) if $job->tmr;
			$self->log->debug("calling cb $job->{cb} for job_id $job->{job_id} outargs $outargs");
			my $outargsp;
			local $@;
			eval { $outargsp = decode_json(encode_utf8($outargs)); };
			$outargsp = { error => 'error decoding json: ' . $outargs } if $@;
			eval { $job->cb->($job->{job_id}, $outargsp); };
			$self->log->debug("got $@ calling callback") if $@;
			$job->delete;
		}
	)->catch(sub {
		 $self->log->error("_poll_done caught $_[0]");
	});
}


sub rpc_find_jobs {
	my ($self, $con, $i, $rpccb) = @_;
	my $filter = $i->{filter} or die 'no job_id?';
	Mojo::IOLoop->delay(
		sub {
			my ($d) = @_;
			$self->jcpg->queue_query($d->begin(0));
		},
		sub {
			my ($d, $db) = @_;
			$db->dollar_only->query(
				q[select find_jobs($1)],
				$filter,
				$d->begin
			);
		},
		sub {
			my ($d, $err, $res) = @_;
			if ($err) {
				$rpccb->(undef, $err);
				return;
			}
			my ($jobs) = @{$res->array};
			unless (ref $jobs eq 'ARRAY') {
				$rpccb->(undef, undef);
				return;
			}
			$self->log->debug("found jobs for filter $filter: " . join(' ,', @$jobs));
			$rpccb->($jobs);
		}
	)->catch(sub {
		 $self->log->error("rpc_find_jobs caught $_[0]");
	});
}


# fixme: reuse _poll_done?
sub rpc_get_job_status {
	my ($self, $con, $i, $rpccb) = @_;
	my $job_id = $i->{job_id} or die 'no job_id?';
	Mojo::IOLoop->delay(
		sub {
			my ($d) = @_;
			$self->jcpg->queue_query($d->begin(0));
		},
		sub {
			my ($d, $db) = @_;
			$db->dollar_only->query(
				q[select * from get_job_status($1)],
				$job_id,
				$d->begin
			);
		},
		sub {
			my ($d, $err, $res) = @_;
			if ($err) {
				$rpccb->(undef, $err);
				return;
			}
			my ($outargs) = @{$res->array};
			unless ($outargs) {
				$rpccb->(undef, undef);
				return;
			}
			$self->log->debug("got status for job_id $job_id outargs $outargs");
			$outargs = decode_json(encode_utf8($outargs));
			$rpccb->($job_id, $outargs);
		}
	)->catch(sub {
		 $self->log->error("rpc_job_job_status caught $_[0]");
	});
}


sub rpc_announce {
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	my $actionname = $i->{actionname} or die 'actionname required';
	my $slots      = $i->{slots} // 1;
	my $workername = $i->{workername} // $client->workername // $client->who;
	my $filter     = $i->{filter};
	if (defined $filter) {
		die "filter must be a json object" unless ref $filter eq 'HASH';
		$filter = decode_utf8(encode_json($filter));
	}

	my ($worker_id, $listenstring);
	local $@;
	eval {
		# announce throws an error when:
		# - workername is not unique
		# - actionname does not exist
		# - worker has already announced action
		($worker_id, $listenstring) = @{$self->jcpg->db->dollar_only->query(
			q[select * from announce($1, $2, $3, $4)],
			$workername,
			$actionname,
			$client->who,
			$filter,
		)->array};
		die "no result" unless $worker_id;
	};
	if ($@) {
		warn $@;
		$rpccb->(JSON->false, $@);
		return;
	}
	$self->log->debug("worker_id $worker_id listenstring $listenstring");

	# always poll for filters
	$self->pending->{$listenstring} = $filter ? $worker_id : 0;

	unless ($self->listenstrings->{$listenstring}) {
		# oooh.. a totally new action
		$self->log->debug("listen $listenstring");
		$self->jcpg->pubsub->listen( $listenstring, sub {
			my ($pubsub, $payload) = @_;
			local $@;
			eval { $self->_task_ready($listenstring, $payload) };
			warn $@ if $@;
		});
		# assumption 1:1 relation actionname:listenstring
		$self->actionnames->{$actionname} = $listenstring;
		$self->listenstrings->{$listenstring} = [];
		# let's assume there are pending jobs, this will trigger a poll
		$self->pending->{$listenstring} = $filter ? $worker_id : -1;
	}		


	my $wa = JobCenter::Api::WorkerAction->new(
		actionname => $actionname,
		client => $client,
		listenstring => $listenstring,
		slots => $slots,
		filter => $filter,
		used => 0,
	);

	$client->workername($workername);
	$client->worker_id($worker_id);
	$client->actions->{$actionname} = $wa;
	# note that this client is interested in this listenstring
	push @{$self->listenstrings->{$listenstring}}, $wa;

	# set up a ping timer to the client after the first succesfull announce
	unless ($client->tmr) {
		$client->{tmr} = Mojo::IOLoop->recurring( $client->ping, sub { $self->_ping($client) } );
	}

	# reply to the client/worker first
	$rpccb->(JSON->true, 'success');

	# before potentially sending any pending work
	# if this is a new action or this  worker has a filter
	# force a poll for this specific worker
	$self->_task_ready(
		$listenstring,
		encode_json({
			poll => "first_$actionname:$worker_id",
			( $filter ? (workers => [$worker_id]) : ()),
		})
	) if $self->pending->{$listenstring} < 0 or
		$self->pending->{$listenstring} == $worker_id;

	return;
}


sub rpc_withdraw {
	my ($self, $con, $i) = @_;
	my $client = $con->owner;
	my $actionname = $i->{actionname} or die 'actionname required';

	$self->_unlisten_client_action($client, $actionname);

	my ($res) = $self->jcpg->db->query(
			q[select withdraw($1, $2)],
			$client->workername,
			$actionname
		)->array;
	die "no result" unless $res and @$res;
	
	if (not %{$client->actions} and $client->tmr) {
		# cleanup ping timer if client has no more actions
		$self->log->debug("remove tmr $client->{tmr}");
		Mojo::IOLoop->remove($client->tmr);
		delete $client->{tmr};
	}

	return 1;
}


sub _ping {
	my ($self, $client) = @_;
	my $tmr;
	Mojo::IOLoop->delay(
	sub {
		my $d = shift;
		my $e = $d->begin;
		$tmr = Mojo::IOLoop->timer(30 => sub { $e->(@_, 'timeout') } );
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
			#$self->pg->db->query(q[select ping($1)], $client->worker_id, $d->begin);
			my $pqq = $self->pqq;
			#print 'pqq: ', Dumper($pqq);
			if ($pqq) {
				# pqq already active, just push
				push @$pqq, $client->worker_id;
			} else {
				# start queue processing
				$self->pqq([$client->worker_id]);
				$self->_ppqq($self->jcpg->db); # fixme.. queue_query?
				#$self->_ppqq();
			}
		}
	})->catch(sub {
		 $self->log->error("_ping caught $_[0]");
	});
}


# process ping query queue: serialize calls to ping on one db connection
# because the pongs tend to come in in batches
sub _ppqq {
	my ($self, $db) = @_;
	#say 'in _ppqq';
	my $pqq = $self->pqq or return; # should not happen?
	my $wi = shift @$pqq;
	unless ($wi) {
		# done with processing the queue
		#$self->log->debug('done with pqq');
		$self->{pqq} = undef;
		return;
	}
	#$self->log->debug("select ping($wi)");
	$db->query(q[select ping($1)], $wi, sub {
		my ($db2, $err, $res) = @_;
		if ($err) {
			$self->log->error("err in ping cb:$err");
			return;
		}
		#print 'res in cb ', Dumper($res->array);
		$res->finish;
		Mojo::IOLoop->next_tick(sub {
			#say 'next tick';
			$self->_ppqq($db);
		});
	});
}


# fixme: merge with _task_ready_next
sub _task_ready {
	my ($self, $listenstring, $payload) = @_;
	
	die '_task_ready: no payload?' unless $payload; # whut?
	$self->log->debug("_task_ready $listenstring payload $payload");

	$payload = decode_json($payload);
	my $job_id = $payload->{job_id} // $payload->{poll} // die '_task_ready: invalid payload?';

	my $workers;
	%$workers = map { $_ => 1 } @{$payload->{workers}} if ref $payload->{workers} eq 'ARRAY';

	if ($payload->{poll}) {
		$self->pending->{$listenstring} = $workers ? ${$payload->{workers}}[0] : -1;
	}

	my $l = $self->listenstrings->{$listenstring};
	return unless $l; # should not happen? maybe unlisten here?

	push @$l, shift @$l; # rotate listenstrings list (list of workeractions)

	my $wa;
	for (@$l) { # now find a worker with a free slot
		my $worker_id = $_->client->worker_id;
		if ($workers) {
			unless ($workers->{$worker_id}) {
				$self->log->debug("skipping $worker_id because of filter");
				next;
			}
		}
		$self->log->debug('worker ' . $worker_id . ' has ' . $_->used . ' of ' . $_->slots . ' used');
		if ($_->used < $_->slots) {
			$wa = $_;
			last;
		}
	}

	unless ($wa) {
		$self->log->debug("no free slots for $listenstring!?");
		$self->pending->{$listenstring} = $workers ? ${$payload->{workers}}[0] : -1;
		# we'll do a poll when a worker becomes available
		# and the maestro will bother us again later anyways
		return;
	}

	$wa->{used}++; # let's assmume the worker takes it

	$self->log->debug('sending task ready to worker ' . $wa->client->worker_id . ' for ' . $wa->actionname);

	$wa->client->con->notify('task_ready', {actionname => $wa->actionname, job_id => $job_id});

	# ask the next worker after 3 seconds
	my $tmr = Mojo::IOLoop->timer(3 => sub { $self->_task_ready_next($job_id) } );

	my $task = JobCenter::Api::Task->new(
		actionname => $wa->actionname,
		#client => $client,
		job_id => $job_id,
		listenstring => $listenstring,
		tmr => $tmr,
		workeraction => $wa,
		workers => $workers,
	);
	$self->{tasks}->{$job_id} = $task;
}


# fixme: merge with _task_ready
sub _task_ready_next {
	my ($self, $job_id) = @_;
	
	my $task = $self->{tasks}->{$job_id} or return; # die 'no task in _task_ready_next?';
	$task->workeraction->{used}--; # this worker didn't take the job
	my $workers = $task->workers;
	
	$self->log->debug("try next client for $task->{listenstring} for $task->{job_id}");
	my $l = $self->listenstrings->{$task->listenstring};

	return unless $l; # should not happen?

	push @$l, shift @$l; # rotate listenstrings list (list of workeractions)

	my $wa;
	for (@$l) { # now find a worker with a free slot
		my $worker_id = $_->client->worker_id;
		if ($workers) {
			unless ($workers->{$worker_id}) {
				$self->log->debug("skipping $worker_id because of filter");
				next;
			}
		}
		$self->log->debug('worker ' . $worker_id . ' has ' . $_->used . ' of ' . $_->slots . ' used');
		if ($_->used < $_->slots) {
			$wa = $_;
			last;
		}
	}

	unless ($wa) {
		$self->log->debug("no free slots for $task->{listenstring}!?");
		my @workers = keys %{$task->workers};
		$self->pending->{$task->listenstring} = @workers ? $workers[0] : -1;
		# we'll do a poll when a worker becomes available
		# and the maestro will bother us again later anyways
		return;
	}

	if (refaddr $wa == refaddr $task->workeraction) {
		$self->log->debug("no other worker for $task->{listenstring}!?");
		# needtothink
		#$self->pending->{$task->listenstring} = 1;
		# no other workers available than the one we already tried?
		# give up for now and let the retry mechanisms cope with this
		return;
	}

	$wa->{used}++; # let's assmume the next worker takes it
	$wa->client->con->notify('task_ready', {actionname => $wa->actionname, job_id => $job_id});

	my $tmr = Mojo::IOLoop->timer(3 => sub { $self->_task_ready_next($job_id) } );

	$task->update(
		#client => $client,
		tmr => $tmr,
		workeraction => $wa,
		#job_id => $job_id,
	);
}


sub rpc_get_task {
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	my $workername = $client->workername;
	my $actionname = $i->{actionname};
	my $job_id = $i->{job_id};

	#say 'tasks: ', join(', ', keys %{$self->{tasks}});

	# need to think about this relating to the poll scenario..
	my $task = delete $self->{tasks}->{$job_id};
	unless ($task) {
		$self->log->debug("get_task: no task!?");
		$rpccb->();
		return;
	}

	# should not happen?
	Mojo::IOLoop->remove($task->tmr) if $task->tmr;

	$self->log->debug("get_task: workername '$workername', actioname '$actionname', job_id $job_id");

	# in the stored-procedure low-level api a null value means poll
	# (yeah it's a hack)
	$job_id = undef if $job_id !~ /^\d+/;
	
	#local $SIG{__WARN__} = sub {
	#	$self->log->debug($_[0]);
	#};

	Mojo::IOLoop->delay(
		sub {
			my ($d) = @_;
			$self->jcpg->queue_query($d->begin(0));
		},
		sub {
			my ($d, $db) = @_;
			$db->dollar_only->query(
				q[select * from get_task($1, $2, $3)],
				$workername, $actionname, $job_id,
				$d->begin
			);
		},
		sub {
			my ($d, $err, $res) = @_;
			if ($err) {
				$self->log->error("get_task threw $err");
				$rpccb->();
				return;
			}
			#$res = $res->array;
			my ($job_id2, $cookie, $inargsj, $env);
			($job_id2, $cookie, $inargsj, $env) = @{$res->array}; # if ref $res;
			$res->finish;
			unless ($cookie) {
				$self->log->debug("no cookie?");
				$rpccb->();
				if (not defined $job_id	and my $p = $self->pending->{$task->listenstring}) {
					if ($p < 0 or $p == $client->worker_id) {
						$self->log->debug("resetting pending flag $p for $task->{listenstring}");
						$self->pending->{$task->listenstring} = 0;
					}
				}
				# no need to consider the worker busy then..
				$task->{workeraction}->{used}--;
				return;
			}

			#say 'HEX ', join(' ', unpack('(H2)*', encode_utf8($inargsj)));
			my $inargs = decode_json(encode_utf8($inargsj)); # unless $self->json;
			$env = decode_json(encode_utf8($env)) if $env;

			# timeouts (if any) will be done by the maestro..
			#my $tmr = Mojo::IOLoop->timer($self->timeout => sub { $self->_task_timeout($cookie) } );

			$task->update(
				job_id => $job_id2,
				cookie => $cookie,
				inargs => $inargs,
				#tmr => $tmr,
			);
			#$task->workeraction->{used}++;
			# ugh.. what a hack
			$self->{tasks}->{$cookie} = $task;

			$self->log->debug("get_task sending job_id $task->{job_id} to "
				 . "$task->{workeraction}->{client}->{worker_id} used $task->{workeraction}->{used} "
				 . "cookie $cookie inargs $inargsj");

			$rpccb->($job_id2, $cookie, $inargs, $env);
		}
	)->catch(sub {
		 $self->log->error("rpc_get_task caught $_[0]");
	});
}


sub rpc_task_done {
	#my ($self, $task, $outargs) = @_;
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	my $cookie = $i->{cookie} or die 'no cookie!?';
	my $outargs = $i->{outargs} or die 'no outargs!?';

	my $task = delete $self->{tasks}->{$cookie};
	return unless $task; # really?	
	Mojo::IOLoop->remove($task->tmr) if $task->tmr;
	# try to prevent used going negative..
	$task->{workeraction}->{used}-- if $task->{workeraction}->{used} > 0;

	local $@;
	eval {
		$outargs = decode_utf8(encode_json($outargs));
	};
	$outargs = decode_utf8(encode_json({'error' => 'cannot json encode outargs: ' . $@})) if $@;
	$self->log->debug("task_done got $@") if $@;

	$self->log->debug("worker '$client->{workername}' done with action '$task->{actionname}' for job $task->{job_id}"
		." slots used $task->{workeraction}->{used} outargs '$outargs'");

	Mojo::IOLoop->delay(
		sub {
			my ($d) = @_;
			$self->jcpg->queue_query($d->begin(0));
		},
		sub {
			my ($d, $db) = @_;
			$db->dollar_only->query(
				q[select task_done($1, $2)],
				$cookie, $outargs, $d->begin
			);
		},
		sub {
			my ($d, $err, $res) = @_;
			if ($err) {
				$self->log->error("task_done threw $err");
				return;
			}
			#$self->log->debug("task_done_callback!");
			my $p = $self->pending->{$task->workeraction->listenstring} // 0;
			if ($p < 0) {
				$self->log->debug("calling _task_ready from task_done_callback!");

				$self->_task_ready(
					$task->workeraction->listenstring,
					encode_json({
						poll => "please_$task->{actionname}",
					})
				);
			} elsif ($p == $client->{worker_id}) {
				$self->log->debug("calling _task_ready from task_done_callback for $client->{worker_id}!");

				$self->_task_ready(
					$task->workeraction->listenstring,
					encode_json({
						poll => "please_$task->{actionname}:$client->{worker_id}",
						workers => [$client->{worker_id}],
					})
				);
				#$self->_task_ready(
				#	$task->workeraction->listenstring,
				#	'{"poll":"please"}'
				#);
			}
		},
	)->catch(sub {
		 $self->log->error("rpc_task done caught $_[0]");
	});
	return;
}


sub _shutdown {
	my($self, $sig) = @_;
	$self->log->info("caught sig$sig, shutting down");

	for my $was (values %{$self->listenstrings}) {
		for my $wa (@$was) {
			$self->log->debug("withdrawing '$wa->{actionname}' for '$wa->{client}->{workername}'");
			my ($res) = $self->jcpg->db->query(
					q[select withdraw($1, $2)],
					$wa->client->workername,
					$wa->actionname
				)->array;
			die "no result" unless $res and @$res;
		}
	}

	Mojo::IOLoop->stop;
}


sub rpc_get_api_status {
	my ($self, $con, $i) = @_;
	my $client = $con->owner;
	die 'permission denied' unless $client->who eq 'apimeister';
	my $what = $i->{what} or die 'what status?';
	# find listenstring by actionname

	if ($what eq 'clients') {
		my @out;

		for my $c (values %{$self->clients}) {
			next unless $c;
			my %actions;
			if ($c->actions) {
				$actions{$_->actionname} = {
					filter => $_->filter,
					slots => $_->slots,
					used => $_->used,
				} for values %{$c->actions};
			}
			push @out, {
				actions => \%actions,
				from => $c->from,
				who => $c->who,
				workername => $c->workername,
			}
		}

		return \@out;
	} elsif ($what eq 'pending') {
		my %out;
		for my $l (keys %{$self->pending}) {
			my $wa = $self->listenstrings->{$l}[0];
			$out{$wa->actionname} = ($self->pending->{$l} ? 'jobs pending' : 'no jobs pending');
		}

		return \%out;
	} else {
		return "no status for $what";
	}

}

1;
