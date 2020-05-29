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
use File::Basename qw(fileparse);
use Ref::Util qw(is_arrayref is_hashref);
use Scalar::Util qw(refaddr);

# cpan
use Config::Tiny;
use Data::Printer;
use JSON::MaybeXS;
use JSON::RPC2::TwoWay;

# JobCenter
use JobCenter::Api::Action;
use JobCenter::Api::Auth;
use JobCenter::Api::Job;
use JobCenter::Api::Server;
use JobCenter::Api::SlotGroup;
use JobCenter::Api::Task;
use JobCenter::Api::WorkerAction;
use JobCenter::Pg;
use JobCenter::Util qw(rm_ref_from_arrayref);

has [qw(
	actionnames
	apiname
	auth
	cfg
	clients
	debug
	jcpg
	jobs
	listenstrings
	log
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
	my $log = $self->{log} = $args{log} //
		 Mojo::Log->new(level => ($debug) ? 'debug' : 'info');

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
	$jcpg->log($log);
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
		eval {
			$self->log->debug("calling lcb $job->{lcb}");
			$job->{lcb}->($self, $job);
		};
		$self->log->debug("pubsub cb $@") if $@;
	});

	my $rpc = $self->{rpc} = JSON::RPC2::TwoWay->new(debug => $debug) or die 'no rpc?';

	$rpc->register('announce', sub { $self->rpc_announce(@_) }, non_blocking => 1, state => 'auth');
	$rpc->register('create_job', sub { $self->rpc_create_job(@_) }, non_blocking => 1, state => 'auth');
	$rpc->register('create_slotgroup', sub { $self->rpc_create_slotgroup(@_) }, state => 'auth');
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
	die "no listen configuration?" unless is_hashref($cfg->{'api|listen'});
	for my $l (keys %{$cfg->{'api|listen'}}) {

		my $lc = $cfg->{"api|listen|$l"} or
			die "no listen configuration for $l?";

		push @servers, JobCenter::Api::Server->new($self, $l, $lc);
	}

	# keep sorted
	$self->{actionnames} = {};    # low level announced actions by actionname
	$self->{clients} = {};        # connected clients
	$self->{jobs} = {};           # currently active jobs
	$self->{listenstrings} = {};  # low level announced actions by listenstrings
	$self->{ping} = $args{ping} || 60; # how often to ping workers
	$self->{pqq} = undef;         # ping query queue
	$self->{servers} = \@servers; # network ports
	$self->{tasks} = {};          # tasks currently beging processed
	$self->{timeout} = $args{timeout} // 60; # 0 is a valid timeout?
	$self->{tmr} = Mojo::IOLoop->recurring( $self->{ping}, sub { $self->_poll_tasks() } );

	return $self;
}


sub work {
	my ($self) = @_;

	local $SIG{TERM} = local $SIG{INT} = sub {
		my ($sig) = @_;
		$self->log->info("caught sig$sig, shutting down");
		Mojo::IOLoop->stop;
	};

	local $SIG{HUP} = "IGNORE";

	$self->log->info('JobCenter::Api::JsonRpc starting work');
	Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
	#my $reactor = Mojo::IOLoop->singleton->reactor;
	#$reactor->{running}++;
	#while($reactor->{running}) {
	#	$reactor->one_tick();
	#}
	$self->_shutdown();
	$self->log->info('JobCenter::Api::JsonRpc done?');

	return 0;
}


sub _unlisten_client_action {
	my ($self, $client, $wa) = @_;
	#
	# remove this action from the clients action list

	my $action = $wa->action;
	my $l = $action->workeractions;
	# now remove this workeraction from the listenstring workeraction list
	rm_ref_from_arrayref($l, $wa);

	# unlisten if the action->workeraction list is now empty
	unless (@$l) {
		my $listenstring = $action->listenstring;
		delete $self->listenstrings->{$listenstring};
		delete $self->actionnames->{$action->actionname};
		$self->jcpg->pubsub->unlisten($listenstring);
		$self->log->info("unlisten $listenstring for $action->{actionname}");
		$action->delete(); # done with action
	}
}


sub _disconnect {
	my ($self, $client) = @_;
	$self->log->info('oh my.... ' . ($client->who // 'somebody')
		. ' (' . $client->from. ') disonnected..');

	my $addr = refaddr($client);

	if ($client->worker_id) {
		# the client was a worker at some point..
		# let's assume things are initialized correctly
		$self->log->info("worker gone processing $client->{workername}");

		# delete all tasks pointing to this worker
		# this is expensive.. take the memleak instead?
		my $t = $self->tasks;
		keys %$t; # reset each;
		my ($k, $v, @d);
		while (($k, $v) = each %$t) {
			push @d, $k if refaddr($v->{workeraction}->{client}) == $addr;
		}
		# do not modify hash while iterating
		delete @$t{@d};

		# clean up workeractions
		for my $wa (values %{$client->{workeractions}}) {
			$self->_unlisten_client_action($client, $wa);
			$wa->delete();
		}
		delete $client->{workeractions};

		# ditto for slotgroups
		$_->delete() for values %{$client->slotgroups};

		# todo: non-blocking?
		my ($res) = $self->jcpg->db->dollar_only->query(
				q[select disconnect($1)],
				$client->workername,
			)->array;
		die "no result" unless $res and @$res;
		$self->log->debug("done cleaning up worker?");
	}

	# the client might have a active timer if it was a worker
	if (my $tmr = delete $client->{tmr}) {
		# cleanup ping timer
		Mojo::IOLoop->remove($tmr);
	}

	delete $self->clients->{$addr};
	$client->con->close if $client->con; # paranoia
	$client->delete();
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
			$self->log->info("client $client->{from}: hello from $who succeeded: method $method msg $msg");
			$client->who($who);
			$client->reqauth($reqauth);
			$con->state('auth');
			$rpccb->(JSON->true, "welcome to the clientapi $who!");
		} else {
			$self->log->info("client $client->{from}: hello failed for $who: method $method msg $msg");
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
	my $timeout = $i->{timeout} // 0;
	my $impersonate = $client->who;
	my $env;
	if (is_hashref($i->{clenv})) {
		$env->{clenv} = $i->{clenv};
	}
	if ($client->reqauth) {
		my ($res, $log, $authscope) = $client->reqauth->request_authentication($client, $i->{reqauth});
		unless ($res) {
			$rpccb->(undef, $log);
			return;
		}
		$env->{authscope} = {authscope => $authscope};
	}
	$env = decode_utf8(encode_json($env)) if $env;
	my $cb = sub {
		my ($job_id, $outargs) = @_;
		$con->notify('job_done', {job_id => $job_id, outargs => $outargs})
			if %$con; # mild hack: the con object will be empty when
			          # the client is already disconnected
	};

	die  'inargs should be a hashref' unless is_hashref($inargs);
	$inargs = decode_utf8(encode_json($inargs));

	$self->log->debug("calling $wfname with '$inargs'" . (($vtag) ? " (vtag $vtag)" : ''));

	# create_job throws an error when:
	# - wfname does not exist
	# - inargs not valid
	Mojo::IOLoop->delay(sub {
		my ($d) = @_;
		$self->jcpg->queue_query($d->begin(0));
	},
	sub {
		my ($d, $db) = @_;
		#($job_id, $listenstring) = @{
		$db->dollar_only->query(
			q[select * from create_job(
				wfname := $1,
				args := $2,
				tag := $3,
				impersonate := $4,
				env := $5
			)],
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
		#$self->log->debug("job_id $job_id listenstring $listenstring");
		$self->log->info("client $client->{from}: created job_id $job_id for $wfname with '$inargs'"
			. (($vtag) ? " (vtag $vtag)" : ''));
		$rpccb->($job_id, undef);

		my $job = JobCenter::Api::Job->new(
			cb => [ $cb ],
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
			eval { $cb->($job_id, {'error' => 'timeout'}); };
			$job->delete;
		}) if $timeout > 0;
		#$self->log->debug("setting tmr: $tmr") if $tmr;

		$job->update(tmr => $tmr, lcb => \&_poll_done);

		# do one poll first..
		$self->_poll_done($job);
	})->catch(sub {
		my ($err) = @_;
		$rpccb->(undef, $err);
	});
}


sub _poll_done {
	my ($self, $job) = @_;
	Mojo::IOLoop->delay(sub {
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
		my ($job_id2, $outargs) = @{$res->array};
		$res->finish;
		return unless $outargs;
		my $job_id=$job->{job_id};
		delete $self->{jobs}->{$job_id};
		Mojo::IOLoop->remove($job->{tmr}) if $job->{tmr};
		my $outargsp;
		local $@;
		eval { $outargsp = decode_json(encode_utf8($outargs)); };
		$outargsp = { error => "$@ error decoding json: " . $outargs } if $@;
		for my $cb ( @{$job->{cb}} ) {
			$self->log->info("job $job_id done: outargs $outargs");
			eval { $cb->($job_id, $outargsp); };
			$self->log->warn("got $@ calling callback") if $@;
		}
		$job->delete;
	})->catch(sub {
		 $self->log->error("_poll_done caught $_[0]");
	});
}


sub rpc_find_jobs {
	my ($self, $con, $i, $rpccb) = @_;
	my $filter = $i->{filter} or die 'no job_id?';
	Mojo::IOLoop->delay(sub {
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
		unless (is_arrayref($jobs)) {
			$rpccb->(undef, undef);
			return;
		}
		$self->log->debug("found jobs for filter $filter: " . join(' ,', @$jobs));
		$rpccb->($jobs);
	})->catch(sub {
		 $self->log->error("rpc_find_jobs caught $_[0]");
	});
}


sub rpc_get_job_status {
	my ($self, $con, $i, $rpccb) = @_;
	my $job_id = $i->{job_id} or die 'no job_id?';
	die "invalid $job_id" unless $job_id =~ /^\d+$/;

	my $job;
	if ($i->{notify}) {
		# registering the callback before we do the get_job_status query
		# could lead to the job_done done notification being received by the
		# client before we send the get_job_status rpc result. client libraries
		# offering the notify option on get_job_status should be prepared for
		# this
		my $cb = sub {
			my ($job_id, $outargs) = @_;
			$con->notify('job_done', {job_id => $job_id, outargs => $outargs})
				if %$con; # mild hack: the con object will be empty when
					  # the client is already disconnected
		};
		#$self->log->debug("get_status: listen for $job_id");
		$job = $self->{jobs}->{$job_id} // JobCenter::Api::Job->new(
			cb => [],
			job_id => $job_id,
			lcb => \&_poll_done,
		);
		push @{$job->{cb}}, $cb; # we might be adding to a existing job
		# (re)register for the central job finished listen
		$self->{jobs}->{$job_id} = $job;
	}

	Mojo::IOLoop->delay(sub {
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
			# unknown job_id.. removing the callback is save
			#$self->log->debug("get_status: remove listen for $job_id");
			delete $self->{jobs}->{$job_id} if $job;
			return;
		}
		my ($job_id2, $outargs) = @{$res->array};
		$res->finish;
		$self->log->debug("got status for job_id $job_id outargs @{[ $outargs // '<null>']}");
		$outargs = decode_json(encode_utf8($outargs)) if $outargs;
		$rpccb->($job_id2, $outargs);
		# if the job is finished we can remove our notify callback but we have
		# to be careful not to remove a _poll_done callback as well, so we'll
		# only remove if there is only one callback registered. if there is
		# more than one the client might receive a job_done notification for
		# a job it is (no longer) waiting for. because of the race condition
		# mentioned above that should not be an issue
		if ( $job and $outargs
			and scalar @{$job->{cb}} == 1 ) {
			#$self->log->debug("get_status: remove listen for $job_id");
			delete $self->{jobs}->{$job_id};
		}
	})->catch(sub {
		 $self->log->error("rpc_job_job_status caught $_[0]");
	});
}


sub rpc_create_slotgroup {
	my ($self, $con, $i) = @_;
	my $client = $con->owner;
	my $name = $i->{name} or die 'slotgroup name required';
	die 'invalid slotgroup name' if $name =~ /^_/;
	my $slots = $i->{slots} // 1;
	die 'slots should be a positive number'
		unless $slots > 0;

	die "slotgroup $name already exists"
		if $client->slotgroups->{$name};

	$client->slotgroups->{$name} = JobCenter::Api::SlotGroup->new(
		name => $name,
		pending => [],
		slots => $slots,
		used => 0,
	);

	return '';
}


sub rpc_announce {
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	my $actionname = $i->{actionname} or die 'actionname required';
	my $sgname = $i->{slotgroup};
	my $slots = $i->{slots};
	my $slotgroup;
	if ($sgname and $slots) {
		die 'cannot provide both slotgroup and slots';
	} elsif ($sgname) {
		$slotgroup = $client->slotgroups->{$sgname};
		die "slotgroup $sgname does not exist"
			unless $slotgroup;
	} else {
		$slots //= 1;
		die 'slots should be a positive number'
			unless $slots > 0;
		$slotgroup = JobCenter::Api::SlotGroup->new(
			name => "_$actionname",
			pending => [],
			slots => $slots,
			used => 0,
		);
		$client->slotgroups->{"_$actionname"} = $slotgroup;
	}
	die 'no slotgroup?' unless $slotgroup;
	my $workername = $i->{workername} // $client->workername // $client->who;
	my $filter     = $i->{filter};
	if (defined $filter) {
		die "filter must be a json object" unless is_hashref($filter);
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
		my $err = $@;
		$self->log->warn($err);
		$rpccb->(JSON->false, $err);
		return;
	}
	$self->log->info("client $client->{from} who $client->{who} workername"
               . " '$workername' worker_id $worker_id action $actionname"
               . " listenstring $listenstring");

	my ($action, $new);

	unless ($action = $self->listenstrings->{$listenstring}) {
		# oooh.. a totally new action
		$self->log->info("add listen $listenstring");
		# assumption 1:1 relation actionname:listenstring
		$action = JobCenter::Api::Action->new(
			actionname => $actionname,
			listenstring => $listenstring,
			workeractions => [],
		);
		$self->jcpg->pubsub->listen($listenstring, sub {
			my ($pubsub, $payload) = @_;
			local $@;
			eval { $self->_task_ready($action, $payload) };
			warn $@ if $@;
		});
		$self->actionnames->{$actionname} = $action;
		$self->listenstrings->{$listenstring} = $action;
		# let's assume there are pending jobs, this will trigger a ping
		$new++;
	}		


	my $wa = JobCenter::Api::WorkerAction->new(
		action => $action,
		client => $client,
		slotgroup => $slotgroup,
		filter => $filter,
	);

	$client->workername($workername);
	$client->worker_id($worker_id);
	$client->workeractions->{$actionname} = $wa;
	# now make the wa callable
	push @{$action->workeractions}, $wa;
	#$slotgroup->workeractions->{$actionname} = $wa;

	# set up a ping timer to the client after the first succesfull announce
	unless ($client->tmr) {
		$client->{tmr} = Mojo::IOLoop->recurring( $client->ping, sub { $self->_ping($client) } );
	}

	# reply to the client/worker first:
	$rpccb->(JSON->true, 'success');

	# need to rethink this: we only want to do a ping after the announces are finished
	# a minute might be a bit long but otherwise we have to introduce a oneshot timer..

=pod
	# before potentially sending any pending work:
	# if this is a new action or this worker has a filter
	# or there is work pending anyways do a premature 'ping'
	# that will cause task_ready notifications to be sent
	if ($new or $filter or
		$self->pending->{$listenstring}->{'*'} or
		$self->pending->{$listenstring}->{$worker_id}) {

		$self->log->debug('doing ping after announce!');
		$self->jcpg->db->query(q[select ping($1)], $worker_id, sub {
			my ($db2, $err, $res) = @_;
			if ($err) {
				$self->log->error("err in ping cb:$err");
				return;
			}
			$res->finish;
		});
	}
=cut

	return;
}


sub rpc_withdraw {
	my ($self, $con, $i) = @_;
	my $client = $con->owner;
	my $actionname = $i->{actionname} or die 'actionname required';

	my $wa = delete $client->workeractions->{$actionname}
		or die "actionname $actionname not announced?";

	$self->_unlisten_client_action($client, $wa);
	$wa->reset_pending(); # remove from slotgroup pending list
	$wa->delete();

	my ($res) = $self->jcpg->db->query(
			q[select withdraw($1, $2)],
			$client->workername,
			$actionname
		)->array;
	die "no result" unless $res and @$res;
	
	if (not %{$client->workeractions} and $client->tmr) {
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


sub _poll_tasks {
	my ($self) = @_;

	# fixme: cache this?
	my @worker_ids;
	for (values %{$self->clients}) {
		push @worker_ids, $_->{worker_id} if $_->{worker_id};
	}

	$self->log->debug('_poll_tasks({' . join(',', @worker_ids) . '})');

	Mojo::IOLoop->delay(sub {
		my ($d) = @_;
		$self->jcpg->queue_query($d->begin(0));
	},
	sub {
		my ($d, $db) = @_;
		$db->dollar_only->query(
			q[select * from poll_tasks($1)],
			'{' . join(',', @worker_ids) . '}',
			$d->begin
		);
	},
	sub {
		my ($d, $err, $res) = @_;
		if ($err) {
			$self->log->error("_poll threw $err");
			return;
		}
		my $rows = $res->sth->fetchall_arrayref();
		$res->finish;
		$self->log->debug('_process_poll: ' . Dumper(@$rows));
		$self->_process_poll($rows) if @$rows;
	})->catch(sub {
		 $self->log->error("_poll caught $_[0]");
	});

}


sub _process_poll {
	my ($self, $rows) = @_;

	while (@$rows) {
		my ($ls, $worker_ids, $count) = @{shift @$rows};
		$self->log->debug("row: $ls, ", ($worker_ids // 'null'), " $count");
		my $action =  $self->listenstrings->{$ls};
		next unless $action; # die?

		my $workers;
		%$workers = map { $_ => 1 } @{$worker_ids} if is_arrayref $worker_ids;

		my $wa = $self->_find_free_worker_slot($action, $workers, 1);
		next unless $wa;

		# fixme: dup with check_pending
		my $actionname = $action->actionname;

		my $task = JobCenter::Api::Task->new(
			action => $action,
			job_id => "please_$actionname",
			workeraction => $wa,
		);

		$self->log->debug("sending task ready to worker \"$wa->{client}->{workername}\""
			 . " for \"$actionname\" ($task)") if $self->{debug};

		$wa->client->con->notify('task_ready',
			{actionname => $actionname, job_id => "$task"});

		$self->{tasks}->{"$task"} = $task;

		$count--;
		push @$rows, [$ls, $worker_ids, $count] if $count > 0;
	}
}


sub _find_free_worker_slot {
	my ($self, $action, $workers, $set_pending) = @_;

	$self->log->debug("_find_free_worker_slot $action->{actionname}");

	my $l = $action->workeractions;
	return unless @$l;
	push @$l, shift @$l if $#$l; # rotate list of workeractions

	my $debug = $self->{debug};

	my $found;
	FOR: for my $wa (@$l) {
		my $worker_id = $wa->client->worker_id;
		if ($workers and not $workers->{$worker_id}) {
			$self->log->debug("skipping $worker_id because of filter");
			next FOR;
		}
		my $sg = $wa->slotgroup or die "no slogroup in worker $worker_id!?";
		$self->log->debug("worker \"$wa->{client}->{workername}\" ($worker_id)"
			. " slotgroup $sg->{name} has "
			. $sg->free . " of $sg->{slots} free") if $debug;
		next unless $sg->free;
		$found = $wa;
		$sg->used(1); # mark as used for now
		last if $found;
	}

	if (not $found and $set_pending) {
		if ($workers) {
			for my $wa (@$l) {
				next unless $workers->{$wa->client->worker_id};
				$wa->set_pending();
			}
		} else {
			$_->set_pending() for @$l;
		}
	}

	return $found;
}


#
# the maestro notifies us that a task has just entered the ready state, look
# for a available worker slot
#
sub _task_ready {
	my ($self, $action, $payload) = @_;
	die '_task_ready: no payload?' unless $payload; # whut?

	my $actionname = $action->actionname;
	$self->log->debug("_task_ready $actionname payload $payload");

	$payload = decode_json($payload);
	my $job_id = $payload->{job_id};

	my $workers;
	%$workers = map { $_ => 1 } @{$payload->{workers}} if is_arrayref $payload->{workers};

	my $wa = $self->_find_free_worker_slot($action, $workers, 1);

	unless ($wa) {
		$self->log->debug("no free slots for $actionname!?");
		# we'll do a poll when a worker becomes available
		# and the maestro will bother us again later anyways
		return;
	}

	my $tmr;
	$tmr = Mojo::IOLoop->timer(10 => sub { $self->_task_ready_next($job_id) } );

	my $task = JobCenter::Api::Task->new(
			action => $action,
			job_id => $job_id,
			workeraction => $wa,
			workers => $workers,
			($tmr ? (tmr => $tmr) : ()),
	);

	$self->log->debug("sending task ready to worker $wa->{client}->{worker_id}"
		 . " for $action->{actionname} ($job_id)");

	$wa->client->con->notify('task_ready',
		{actionname => $action->actionname, job_id => $job_id});

	$self->{tasks}->{$job_id} = $task;
}


sub _task_ready_next {
	my ($self, $job_id) = @_;
	
	my $task = delete $self->{tasks}->{$job_id};
	return unless $task;

	$task->workeraction->slotgroup->free(1); # this worker didn't take the job
	
	$self->log->debug("try next client for $task->{action}->{actionname} for $task->{job_id}");

	my $wa = $self->_find_free_worker_slot($task->action, $task->workers);

	unless ($wa) {
		$self->log->debug("_task_ready_next : no free slots for $task->{action}->{actionname}!?");
		# we'll do a poll when a worker becomes available
		# and the maestro will bother us again later anyways
		$task->delete(); # done with task
		return;
	}

	if (refaddr $wa == refaddr $task->workeraction) {
		$self->log->debug("no other worker for $task->{listenstring}!?");
		# no other workers available than the one we already tried?
		# give up for now and let the retry mechanisms cope with this
		$wa->slotgroup->free(1);
		# but don't forget to reduce the used count..
		$task->delete(); # done with task
		return;
	}

	$wa->client->con->notify('task_ready', {actionname => $wa->action->actionname, job_id => $job_id});

	my $tmr = Mojo::IOLoop->timer(10 => sub { $self->_task_ready_next($job_id) } );

	$task->update(
		tmr => $tmr,
		workeraction => $wa,
	);
}


sub rpc_get_task {
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	my $workername = $client->workername;
	my $actionname = $i->{actionname};
	my $job_id = $i->{job_id};

	#say 'tasks: ', join(', ', keys %{$self->{tasks}});

	my $task =  delete $self->{tasks}->{$job_id};
	unless ($task) {
		$self->log->debug("get_task: no task!?");
		$rpccb->();
		return;
	}

	Mojo::IOLoop->remove($task->tmr) if $task->tmr;

	$self->log->debug("get_task: workername '$workername', actioname '$actionname', job_id $job_id");

	# in the stored-procedure low-level api a null value means poll
	# (yeah it's a hack)
	$job_id = undef if $job_id !~ /^\d+/;

	Mojo::IOLoop->delay(sub {
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

			my $wa = $task->workeraction;
			$task->delete(); # done with task

			$wa->reset_pending();

			# check for (other) work in this slotgroup
			$self->_check_pending($wa, 'get_task');

			return;
		}

		#say 'HEX ', join(' ', unpack('(H2)*', encode_utf8($inargsj)));
		my $inargs = decode_json(encode_utf8($inargsj)); # unless $self->json;
		$env = decode_json(encode_utf8($env)) if $env;

		$task->update(
			job_id => $job_id2, # for a poll this will change
			cookie => $cookie,
			inargs => $inargs,
		);

		$self->{tasks}->{$cookie} = $task;

		$self->log->info("get_task sending job_id $task->{job_id} to "
			 . "worker '$workername' "
			 . "used $task->{workeraction}->{slotgroup}->{used} "
			 . "cookie $cookie inargs $inargsj");

		$rpccb->($job_id2, $cookie, $inargs, $env);
	})->catch(sub {
		 $self->log->error("rpc_get_task caught $_[0]");
	});
}


# check for work for this client and this slotgroup
sub _check_pending {
	my ($self, $wa, $from) = @_;

	$from //= '_check_pending';

	my $l = $wa->slotgroup->pending;

	unless (@$l) {
		# wait until now to free the slotgroup slot so that new
		# task_ready notifications don't steal the slot..
		$wa->slotgroup->free(1);
		return;
	}

	push @$l, shift @$l if $#$l; # round-robin

	$wa = $l->[0];

	# fixme: dup with _process_poll
	my $actionname = $wa->action->actionname;

	my $task = JobCenter::Api::Task->new(
		action => $wa->action,
		job_id => "please_$actionname",
		workeraction => $wa,
	);

	$self->log->debug("sending task ready to worker \"$wa->{client}->{workername}\""
		 . " for \"$actionname\" ($task)") if $self->{debug};

	$wa->client->con->notify('task_ready',
		{actionname => $actionname, job_id => "$task"});

	$self->{tasks}->{"$task"} = $task;
}


sub rpc_task_done {
	#my ($self, $task, $outargs) = @_;
	my ($self, $con, $i, $rpccb) = @_;
	my $client = $con->owner;
	my $cookie = $i->{cookie} or die 'task_done: no cookie!?';
	my $outargs = $i->{outargs} or die 'task_done: no outargs!?';

	my $task = delete $self->{tasks}->{$cookie};
	return unless $task; # really?	
	Mojo::IOLoop->remove($task->tmr) if $task->tmr;

	# hack?
	$outargs = [ $outargs ] unless ref $outargs;
	# /hack?
	local $@;
	eval {
		$outargs = decode_utf8(encode_json($outargs));
	};
	$outargs = decode_utf8(encode_json({'error' => 'cannot json encode outargs: ' . $@})) if $@;
	$self->log->debug("task_done got $@") if $@;

	$self->log->info("worker '$client->{workername}' done with action '$task->{action}->{actionname}'"
		. " for job $task->{job_id} slots used $task->{workeraction}->{slotgroup}->{used}"
		. " outargs '$outargs'");

	my $wa = $task->workeraction;
	$task->delete(); # done with task

	Mojo::IOLoop->delay(sub {
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
		$res->finish();

		if ($err) {
			$self->log->error("task_done threw $err");
			$wa->slotgroup->free(1);
			return;
		}
	
		# now check for more work...
		$self->_check_pending($wa, '_task_done');
	})->catch(sub {
		 $self->log->error("rpc_task done caught $_[0]");
	});
	return;
}


sub _shutdown {
	my($self) = @_;

	my $jcpg = $self->jcpg;

	$self->log->info("stop accepting new connections");
	for my $srv (@{$self->servers}) {
		Mojo::IOLoop->acceptor($srv->server)->stop();
	}

	# unlisten so we don't get any new work
	$self->log->info("unlisten actions");
	for my $ls (keys %{$self->listenstrings}) {
		$jcpg->pubsub->unlisten($ls);
	}
	$jcpg->pubsub->unlisten('job:finished');

	$self->log->info("disconnecting clients");
	for my $client (values %{$self->clients}) {
		next unless $client->{from}; # hack to work around leaked clients
		$self->log->debug("disconnecting $client->{from} " . ($client->{workername} // ''));
		$client->close();
	}
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
			next unless is_hashref($c) and %$c;
			my %h = (
				from => $c->from,
				who => $c->who,
				workername => $c->workername,
			);
			if (%{$c->workeractions}) {
				my %was;
				for my $wa (values %{$c->workeractions}) {
					my $sg = $wa->slotgroup;
					$was{$wa->action->actionname} = {
						filter => $wa->filter,
						slotgroup => $wa->slotgroup->name,
					};
				}
				$h{workeractions} = \%was;
			}
			if (%{$c->slotgroups}) {
				my %sgs;
				for my $sg (values %{$c->slotgroups}) {
					$sgs{$sg->name} = {
						used => $sg->used,
						slots => $sg->slots,
						pending => [ map { $_->action->actionname } @{$sg->pending} ],
					}
				}
				$h{slotgroups} = \%sgs;
			}
			push @out, \%h;
		}
		return np(@out);
	} elsif ($what eq 'clientsraw') {
		return np($self->clients);
	} elsif ($what eq 'jobs') {
		return np($self->jobs);
	} elsif ($what eq 'stats') {
		my $clients = $self->clients;
		my ($dead, $workers) = (0,0);
		for my $c (values %{$self->clients}) {
			unless (is_hashref($c) and %$c) {
				$dead++;
				next;
			}
			$workers++ if %{$c->{workeractions}};
		}
		return {
			clients => scalar keys %$clients,
			dead => $dead,
			workers => $workers,
		};
	} elsif ($what eq 'tasks') {
		return np($self->tasks);
	} else {
		return "no status for $what";
	}
}

1;

