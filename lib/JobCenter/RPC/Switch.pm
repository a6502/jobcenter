package JobCenter::RPC::Switch;

our $VERSION = '0.01'; # VERSION

#
# Mojo's default reactor uses EV, and EV does not play nice with signals
# without some handholding. We either can try to detect EV and do the
# handholding, or try to prevent Mojo using EV.
#
BEGIN {
	$ENV{'MOJO_REACTOR'} = 'Mojo::Reactor::Poll' unless $ENV{'MOJO_REACTOR'};
}
# Mojolicious
use Mojo::Base -base;
use Mojo::IOLoop;
use Mojo::Log;

# standard perl
use Carp qw(croak);
use Scalar::Util qw(blessed refaddr);
use Cwd qw(realpath);
use Data::Dumper;
use Encode qw(encode_utf8 decode_utf8);
use File::Basename;

# from cpan
use Config::Tiny;
use JSON::RPC2::TwoWay 0.04; # for access to the request
# JSON::RPC2::TwoWay depends on JSON::MaybeXS anyways, so it can be used here
# without adding another dependency
use JSON::MaybeXS;
use MojoX::NetstringStream 0.05; # older versions have utf-8 bugs

# jobcenter
use JobCenter::Pg;
use JobCenter::Util qw(:daemon hdiff);

has [qw(
	actions address auth cfg cfgpath channels clientid conn daemon debug
	done jcpg jc_worker_id jobs lastping listenstrings log method
	methods ping_timeout port prefix rpc rpcs_worker_id timeout
	tasks tls tmr token who workername
)]; #

# keep in sync with RPC::Switch::Client
use constant {
	RES_OK => 'RES_OK',
	RES_WAIT => 'RES_WAIT',
	RES_TIMEOUT => 'RES_TIMEOUT',
	RES_ERROR => 'RES_ERROR',
	RES_OTHER => 'RES_OTHER', # 'dunno'
	WORK_OK                => 0,           # exit codes for work method
	WORK_PING_TIMEOUT      => 92,
	WORK_CONNECTION_CLOSED => 91,
};


sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new();

	$self->{cfgpath} = $args{cfgpath} or die 'no cfgpath?';
	my $cfg = Config::Tiny->read($self->cfgpath);
	die 'failed to read config ' . $self->cfgpath . ': ' . Config::Tiny->errstr unless $cfg;
	$self->{cfg} = $cfg;

	my $workername = ($args{workername} || fileparse($0)) . " [$$]";

	my $debug = $args{debug} // 0; # or 1?
	my $log = $args{log} // Mojo::Log->new(level => ($debug) ? 'debug' : 'info');

	# make our workername the application_name visible in postgresql
	$ENV{'PGAPPNAME'} = $workername;
	my $jcpg = JobCenter::Pg->new(
		'postgresql://'
		. $cfg->{jcswitch}->{db_user}
		. ':' . $cfg->{jcswitch}->{db_pass}
		. '@' . ( $cfg->{jcswitch}->{db_host} // '' )
		. ( ($cfg->{jcswitch}->{db_port}) ? ':' . $cfg->{jcswitch}->{db_port} : '' )
		. '/' . $cfg->{jcswitch}->{db}
	);
	$jcpg->log($log);
	#$jcpg->database_class('JobCenter::Pg::Db');
	$jcpg->max_total_connections($cfg->{jcswitch}->{con} // 5); # sane default?
	$jcpg->on(connection => sub { my ($e, $dbh) = @_; $log->debug("jcpg: new connection: $dbh"); });

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

	$self->{jcpg} = $jcpg;
	$self->{workername} = $workername;

	my $timeout = $args{timeout} // 60; # fixme: cfg?

	my $address = $cfg->{jcswitch}->{address} // '127.0.0.1';
	my $method = $cfg->{jcswitch}->{method} // 'password';
	my $port = $cfg->{jcswitch}->{port} // 6551;
	my $tls = $cfg->{jcswitch}->{tls} // 0;
	my $tls_ca = $cfg->{jcswitch}->{tls_ca};
	my $tls_cert = $cfg->{jcswitch}->{tls_cert};
	my $tls_key = $cfg->{jcswitch}->{tls_key};
	my $token = $cfg->{jcswitch}->{token} or croak 'no token?';
	my $who = $cfg->{jcswitch}->{who} or croak 'no who?';
	my $prefix = $cfg->{jcswitch}->{prefix} or croak 'no prefix?';

	my $rpc = JSON::RPC2::TwoWay->new(debug => $debug) or croak 'no rpc?';
	$rpc->register(
		'rpcswitch.greetings',
		sub { $self->rpc_greetings(@_) },
		notification => 1
	);
	$rpc->register(
		'rpcswitch.ping',
		sub { $self->rpc_ping(@_) }
	);
	$rpc->register(
		'rpcswitch.channel_gone',
		sub { $self->rpc_channel_gone(@_) },
		notification => 1
	);
	$rpc->register(
		'rpcswitch.result',
		sub { $self->rpc_result(@_) },
		by_name => 0,
		notification => 1,
		raw => 1
	);

	my $clarg = {
		address => $address,
		port => $port,
		tls => $tls,
	};
	$clarg->{tls_ca} = $tls_ca if $tls_ca;
	$clarg->{tls_cert} = $tls_cert if $tls_cert;
	$clarg->{tls_key} = $tls_key if $tls_key;

	my $clientid = Mojo::IOLoop->client(
		$clarg => sub {
		my ($loop, $err, $stream) = @_;
		if ($err) {
			$err =~ s/\n$//s;
			$log->info('connection to API failed: ' . $err);
			$self->{auth} = 0;
			return;
		}
		my $ns = MojoX::NetstringStream->new(stream => $stream);
		my $conn = $rpc->newconnection(
			owner => $self,
			write => sub { $ns->write(@_) },
		);
		$self->{conn} = $conn;
		$ns->on(chunk => sub {
			my ($ns2, $chunk) = @_;
			#say 'got chunk: ', $chunk;
			my @err = $conn->handle($chunk);
			$log->info('chunk handler: ' . join(' ', grep defined, @err)) if @err;
			$ns->close if $err[0];
		});
		$ns->on(close => sub {
			$conn->close;
			$log->info('connection to rpcswitch closed');
			$self->{_exit} = WORK_CONNECTION_CLOSED;
			$self->{done}++;
			Mojo::IOLoop->stop;
		});
	});

	$self->{actions} = {}; # announced actions by actionname
	$self->{address} = $address;
	$self->{channels} = {}; # per channel hash of jobs/waitids
	$self->{clientid} = $clientid;
	$self->{daemon} = $args{daemon} // 0;
	$self->{debug} = $args{debug} // 1;
	$self->{ping_timeout} = $args{ping_timeout} // 300;
	$self->{listenstrings} = {}; # announced actions by listenstring
	$self->{log} = $log;
	$self->{method} = $method;
	$self->{methods} = {}; # announced methods by methodname
	$self->{port} = $port;
	$self->{prefix} = $prefix;
	$self->{rpc} = $rpc;
	$self->{timeout} = $timeout;
	$self->{tmr} = undef;
	$self->{tls} = $tls;
	$self->{tls_ca} = $tls_ca;
	$self->{tls_cert} = $tls_cert;
	$self->{tls_key} = $tls_key;
	$self->{tasks} = {}; # tasks we're currently working on
	$self->{token} = $token;
	$self->{who} = $who;

	# handle timeout?
	my $tmr = Mojo::IOLoop->timer($timeout => sub {
		my $loop = shift;
		$log->error('timeout wating for greeting');
		$loop->remove($clientid); # disconnect
		$self->{auth} = 0;
	});

	$self->log->debug('starting handshake');
	# fixme: catch signals?
	my $reactor = Mojo::IOLoop->singleton->reactor;
	$reactor->{running}++; # fixme: this assumes Mojo::Reactor::Poll
	while (not defined $self->{auth} and $reactor->{running}) {
		Mojo::IOLoop->singleton->reactor->one_tick;
		#$self->log->debug('tick');
	}
	$reactor->{running}--;
	$self->log->debug('done with handhake?');

	Mojo::IOLoop->remove($tmr);
	return $self if $self->{auth};
	return;
}


sub _reconfigure {
	my ($self, $reload) = @_;

	my ($methods, $actions);

	if ($reload) {
		# reload config and do a diff

		my $oldcfg = $self->cfg;
		my $newcfg = Config::Tiny->read($self->cfgpath);
		die 'failed to read config ' . $self->cfgpath . ': ' . Config::Tiny->errstr unless $newcfg;

		my ($add, $rem) = hdiff($oldcfg->{methods}, $newcfg->{methods});

		#print 'methods to remove ', Dumper($rem);
		for my $methodname (keys %$rem) {
			$self->log->info("withdrawing method $methodname from the rpcswitch");
			$self->withdraw_rpcs(method => $methodname);
		}
		
		$methods = $add;
		#print 'methods to add ', Dumper($add);

		($add, $rem) = hdiff($oldcfg->{actions}, $newcfg->{actions});

		#print 'actions to remove ', Dumper($rem);
		for my $actionname (keys %$rem) {
			$self->log->info("withdrawing action $actionname from the jobcenter");
			$self->withdraw_jc(action => $actionname);
		}

		$actions = $add;
		#print 'actions to add ', Dumper($add);

		$self->{cfg} = $newcfg;
	} else {
		# initial configuration

		my $err = $self->announce_rpcs(
			method => "$self->{prefix}._get_status",
			handler => '_get_status',
		);
		die "could not announce $self->{prefix}._get_status: $err" if $err;

		$methods = $self->cfg->{methods} or die 'no method configuration?';

		$actions = $self->cfg->{actions} or die 'no action configuration?';
	}

	for my $method (keys %$methods) {
		$self->log->info("announcing method $method to the rpcswitch");
		my $err = $self->announce_rpcs(
			method => $method,
			workflow => $methods->{$method},
		);
		die "could not announce_rpcs $method: $err" if $err;
	}

	for my $action (keys %$actions) {
		$self->log->info("announcing action $action to the jobcenter");
		my $err = $self->announce_jc(
			action => $action,
			method => $actions->{$action}
		);
		die "could not announce_jc $action: $err" if $err;
	}
}


# handle the greeting notification from the rpcswitch
sub rpc_greetings {
	my ($self, $c, $i) = @_;
	Mojo::IOLoop->delay(sub {
		my $d = shift;
		die "wrong api version $i->{version} (expected 1.0)" unless $i->{version} eq '1.0';
		$self->log->info('got greeting from ' . $i->{who});
		$c->call(
			'rpcswitch.hello',
			{who => $self->who, method => $self->method, token => $self->token},
			$d->begin(0),
		);
	},
	sub {
		my ($d, $e, $r) = @_;
		my $w;
		#say 'hello returned: ', Dumper(\@_);
		die "hello returned error $e->{message} ($e->{code})" if $e;
		die 'no results from hello?' unless $r;
		($r, $w) = @$r;
		if ($r) {
			$self->log->info("hello returned: $r, $w");
			$self->{auth} = 1;
		} else {
			$self->log->error('hello failed: ' . ($w // ''));
			$self->{auth} = 0; # defined but false
		}
	})->catch(sub {
		my ($err) = @_;
		$self->log->error('something went wrong in handshake: ' . $err);
		$self->{auth} = '';
	});
}


# a result notification on a channel
sub rpc_result {
	my ($self, $c, $r) = @_;
	#$self->log->error('got result: ' . Dumper($r));
	my ($status, $id, $outargs) = @{$r->{params}};
	return unless $id;
	my $vci = $r->{rpcswitch}->{vci};
	return unless $vci;
	my $rescb = delete $self->{channels}->{$vci}->{$id};
	return unless $rescb;
	$rescb->($status, $outargs);
	return;
}


# the rpcswitch telss us that somebody disconnected
sub rpc_channel_gone {
	my ($self, $c, $a) = @_;
	my $ch = $a->{channel};
	return unless $ch;
	$self->log->info("got channel_gone for channel $ch");
	my $wl = delete $self->{channels}->{$ch};
	return unless $wl;
	for my $obj (values %$wl) {
		if (ref $obj eq 'CODE') {
			# obj = rescb
			$obj->(RES_ERROR, 'channel gone');
		} else {
			# obj = job
			$self->log->debug("unlisten for $obj->{job_id}");
			delete $self->{jobs}->{$obj->{job_id}};
			#$self->pg->pubsub->unlisten('job:finished', $obj->{lcb});
			%$obj = (); # nuke
		}
	}
	return;
}


# the rpcswitch pings us
sub rpc_ping {
	my ($self, $c, $i, $rpccb) = @_;
	$self->lastping(time());
	return 'pong!';
}


sub work {
	my ($self) = @_;
	if ($self->daemon) {
		_daemonize();
	}

	my $pt = $self->ping_timeout;
	my $tmr = Mojo::IOLoop->recurring($pt => sub {
		my $ioloop = shift;
		$self->log->debug('in ping_timeout timer: lastping: '
			 . ($self->lastping // 0) . ' limit: ' . (time - $pt) );
		return if ($self->lastping // 0) > time - $pt;
		$self->log->error('ping timeout');
		$ioloop->remove($self->clientid);
		$ioloop->stop;
	}) if $pt > 0;

	$self->{done} = 0;
	my $reload = 0;

	local $SIG{TERM} = local $SIG{INT} = local $SIG{HUP} = sub {
		my $sig = shift;
		$self->log->info("caught sig$sig.");
		$self->{done}++ unless $sig eq 'HUP';
		Mojo::IOLoop->stop;
	};

	$self->log->info(blessed($self) . ' starting work');
	$self->{_exit} = WORK_OK;
	while (!$self->done) {
		$self->_reconfigure($reload++);
		Mojo::IOLoop->start;
	}
	$self->_shutdown(@_);
	$self->log->info(blessed($self) . ' done?');

	return $self->{_exit};
}


# announce a method at the rpcswitch
sub announce_rpcs {
	my ($self, %args) = @_;
	my $method = $args{method} or croak 'no method?';
	my $workflow = $args{workflow};

	croak "already have method $method" if $self->methods->{$method};

	my $doc;
	$doc = $self->_get_workflow_info($workflow) if $workflow;
	
	my $err;
	Mojo::IOLoop->delay(sub {
		my $d = shift;
		# fixme: check results?
		$self->conn->call(
			'rpcswitch.announce',
			{
				workername => $self->{workername},
				method => $method,
				#slots => $slots,
				#(($args{filter}) ? (filter => $args{filter}) : ()),
				($doc ? (doc => $doc) : ()),
			},
			$d->begin(0)
		);
	},
	sub {
		#say 'call returned: ', Dumper(\@_);
		my ($d, $e, $r) = @_;
		if ($e) {
			$self->log->debug("announce got error " . Dumper($e));
			$err = $e->{message};
			return;
		}
		my ($res, $msg) = @$r;
		unless ($res) {
			$err = $msg;
			$self->log->error("announce got res: $res msg: $msg");
			return;
		}
                $self->{rpcs_worker_id} = $msg->{worker_id};
		my $mi = { # method information
			method => $method,
			workflow => $workflow,
		};
		$self->methods->{$method} = $mi;
		$self->rpc->register(
			$method,
			sub { $self->_wrap($mi, @_) },
			non_blocking => 1,
			raw => 1,
		);
		$self->log->debug("succesfully announced $method");
	})->catch(sub {
		($err) = @_;
		$self->log->error("something went wrong with announce_rpcs: $err");
	})->wait();

	return $err;
}


sub _get_workflow_info {
	my ($self, $workflow) = @_;
	die 'no workflow?' unless $workflow;

	my $res = $self->jcpg->db->dollar_only->query(
		q[select * from get_workflow_info($1)],
		$workflow,
	)->array;
	die "workflow $workflow not found" unless $res and $res->[0];
	#print "info for $workflow:", Dumper($res);
	return decode_json($res->[0]);
}


# handle the rpcswitch magic
sub _wrap {
	my ($self, $mi, $con, $request, $rpccb) = @_;
	my $req_id = $request->{id};
	my $method = $request->{method};
	my $params = $request->{params};

	my $rpcswitch = $request->{rpcswitch} or
		die "no rpcswitch information?";

	$rpcswitch->{worker_id} = $self->{rpcs_worker_id};

	my $resp = {
		jsonrpc	    => '2.0',
		id	    => $req_id,
		rpcswitch   => $rpcswitch,
	};
	# the 'fast' response
	my $cb1 = sub {
		$resp->{result} = \@_;
		$rpccb->($resp);
	};
	# to be used when the 'fast' response was 'wait'
	my $cb2 = sub {
		my $request = encode_json({
			jsonrpc => '2.0',
			method => 'rpcswitch.result',
			rpcswitch   => $rpcswitch,
			params => \@_,
		});
		$con->write($request);
	};
	my $handler = $mi->{handler};
	eval {
		$self->_create_job($mi, $request, $cb1, $cb2);
	};
	if ($@) {
		$cb1->(RES_ERROR, $@);
	}
}


# method call to jobcenter job
sub _create_job {
	my ($self, $mi, $request, $cb1, $cb2) = @_;
	my $method = $request->{method};
	my $params = $request->{params};

	die "params should be by name" unless ref $params eq 'HASH';

	unless ($mi->{method} eq $method) {
		die "_create_job for unknown method $method";
	}

	my $wfname = $mi->{workflow} or die 'no workflowname?';
	my $vtag = $mi->{vtag};

	my $rpcswitch = $request->{rpcswitch}; # should be there
	my $impersonate = $rpcswitch->{who};
	my $vci = $rpcswitch->{vci};
	my $env;
	if ($rpcswitch->{reqauth}) {
		$env = decode_utf8(encode_json({
			reqauth => $rpcswitch->{reqauth},
			rpcswitch => JSON->true,
		}));
	} else {
		$env = '{"rpcswitch":true}';
	}

	my $inargs = decode_utf8(encode_json($params));

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
			$cb1->(RES_ERROR, $err);
			return;
		}
		my ($job_id, $listenstring) = @{$res->array};
		$res->finish; # free up db con..
		unless ($job_id) {
			$cb1->(RES_ERROR, "no result from call to create_job");
			return;
		}

		# report back to our caller immediately
		# this prevents the job_done notification overtaking the
		# 'job created' result...
		$self->log->info("$vci ($impersonate): created job_id $job_id for $wfname with '$inargs'"
			. (($vtag) ? " (vtag $vtag)" : ''));

		$cb1->(RES_WAIT, "$self->{prefix}:$job_id");

		my $job = {
			_what => 'job',
			cb => $cb2,
			job_id => $job_id,
			lcb => \&_poll_done,
			vci => $vci,
		};

		# to handle channel gone..
		$self->{channels}->{$vci}->{$job_id} = $job;
		# register for the central job finished listen
		$self->{jobs}->{$job_id} = $job;

		# do one poll first..
		$self->_poll_done($job);
	})->catch(sub {
		my ($err) = @_;
		$self->log->error("_create_job caught $err");
		$cb1->(RES_ERROR, $err);
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
			$job->{job_id},
			$d->begin
		);
	},
	sub {
		my ($d, $err, $res) = @_;
		die $err if $err;
		my ($job_id2, $outargs) = @{$res->array};
		return unless $outargs; # job not finished
		my $job_id=$job->{job_id};
		delete $self->{jobs}->{$job_id};
		delete $self->{channels}->{$job->{vci}}->{$job_id} if $self->{channels}->{$job->{vci}};
		#$self->log->debug("calling cb $job->{cb} for job_id $job->{job_id} outargs $outargs");
		$self->log->info("job $job_id done: outargs $outargs");
		my $outargsp;
		local $@;
		eval { $outargsp = decode_json(encode_utf8($outargs)); };
		# should not happen?
		$outargsp = { error => "$@ error decoding json: " . $outargs } if $@;
		if ($outargsp->{error}) {
			$job->{cb}->(RES_ERROR, "$self->{prefix}:$job_id", $outargsp->{error});
		} else {
			$job->{cb}->(RES_OK, "$self->{prefix}:$job_id", $outargsp);
		}
		%$job = (); # delete
	})->catch(sub {
		 $self->log->error("_poll_done caught $_[0]");
	});
}


sub _get_status {
	my ($self, $mi, $request, $cb1, $cb2) = @_;
	#my $method = $request->{method}; # check?
	my $params = $request->{params};

	die "params should be by name" unless ref $params eq 'HASH';
	my $wait_id = $params->{wait_id} or die 'no wait_id?';
	my ($ns, $job_id) = split /:/, $wait_id, 2;
	die "unkown wait_id namespace $ns" unless $ns eq $self->{prefix};
	my $notify = $params->{notify};
	my $vci = $request->{rpcswitch}->{vci}; # should exist?

	# listen before poll.. to avoid a race condition
	if ($notify) {
		$self->log->debug("get_status: listen for $job_id");
		my $job = {
			_what => 'job',
			lcb => \&_poll_done,
			cb => $cb2,
			job_id => $job_id,
			vci => $vci,
		};
		# to handle channel gone..
		$self->{channels}->{$vci}->{$job_id} = $job;
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
			$cb1->(RES_OTHER, $err);
			goto cleanup; # ugly..
		}
		my ($outargs) = @{$res->array};
		unless ($outargs) {
			$cb1->(RES_WAIT, $wait_id);
			return;
		}
		$self->log->debug("got status for job_id $job_id outargs $outargs");
		$outargs = decode_json(encode_utf8($outargs));
		if ($outargs->{error}) {
			$cb1->(RES_ERROR, $outargs->{error});
		} else {
			$cb1->(RES_OK, $outargs);
		}
		cleanup:
		if ($notify) {
			# cleanup
			my $job = delete $self->{jobs}->{$job_id};
			delete $self->{channels}->{$vci}->{$job_id}
				if $self->{channels}->{$vci};
			%$job = ();
		}
	})->catch(sub {
		 $self->log->error("_get_status caught $_[0]");
	});
}


# withdraw a method at the rpcswitch
sub withdraw_rpcs {
	my ($self, %args) = @_;
	my $method = $args{method} or croak 'no method?';

	croak "unnannounced method $method?" unless $self->methods->{$method};

	my ($done, $err);
	Mojo::IOLoop->delay(sub {
		my $d = shift;
		$self->conn->call(
			'rpcswitch.withdraw',
			{
				 workername => $self->{workername},
				 method => $method,
			},
			$d->begin(0)
		);
	},
	sub {
		#say 'call returned: ', Dumper(\@_);
		my ($d, $e, $r) = @_;
		$done++;
		if ($err) {
			$self->log->debug("withdraw_rpcs got error " . Dumper($e));
			$err = $e->{message};
			return;
		}
		unless ($r) {
			$err = 'withdraw_pcs failed';
			$self->log->error('withdraw_rpcs failed');
			return;
		}
		$self->rpc->unregister($method);
		delete $self->methods->{$method};
		$self->log->info("succesfully withdrew method $method");
	})->catch(sub {
		$done++;
		($err) = @_;
		$self->log->debug("something went wrong with withdraw_rpcs: $err");
	})->wait();
	
	# we could recurse here
	#Mojo::IOLoop->singleton->reactor->one_tick while !$done;

	return $err;
}


# announce a rpcswitch method as an action to the jobcenter
sub announce_jc {
	my ($self, %args) = @_;
	my $actionname = $args{action} or croak 'no action?';
	my $methodname = $args{method} or croak 'no method?';

	my ($worker_id, $listenstring);
	local $@;
	eval {
		# announce throws an error when:
		# - workername is not unique
		# - actionname does not exist
		my $res = $self->jcpg->db->dollar_only->query(
			q[select * from announce($1, $2)],
			$self->{workername},
			$actionname
		)->array;
		die "no result" unless $res and @$res;
		($worker_id, $listenstring) = @$res;
	};
	if ($@) {
		warn $@;
		return $@;
	}
	my $action = {
		actionname => $actionname,
		listenstring => $listenstring,
		methodname => $methodname,
		pending => 0,
	};
	$self->log->debug("worker_id $worker_id listenstring $listenstring");
	$self->jcpg->pubsub->listen($listenstring, sub {
		my ($pubsub, $payload) = @_;
		$self->_get_task($action, $payload);
	});
	$self->actions->{$actionname} = $action;
	$self->listenstrings->{$listenstring} = $action;
	$self->jc_worker_id($worker_id);
	# set up a ping timer after the first succesfull announce
	unless ($self->tmr) {
		$self->{tmr}  = Mojo::IOLoop->recurring( 60, sub { $self->_ping($worker_id) } );
	}
	return;
}


sub _get_task {
	my ($self, $action, $payload) = @_;

	die '_task_ready: no payload?' unless $payload; # whut?

	my $actionname = $action->{actionname};
	my $methodname = $action->{methodname};

	$self->log->debug("get_task: actioname $actionname, methodname $methodname, payload $payload");

	$payload = decode_json($payload);
	my $job_id = $payload->{job_id} // $payload->{poll} // die '_task_ready: invalid payload?';

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
			$self->{workername},
			$actionname,
			$job_id,
			$d->begin
		);
	},
	sub {
		my ($d, $err, $res1) = @_;
		if ($err) {
			$self->log->error("get_task threw $err");
			return;
		}
		my $res2 = $res1->array;
		$res1->finish;
		my ($job_id, $cookie, $inargs, $env);
		($job_id, $cookie, $inargs, $env) = @$res2 if $res2;
		unless ($cookie) {
			$action->{pending}-- if $action->{pending};
			$self->log->debug("no cookie? unset pending flag for $actionname: "
				. $action->{pending});
			return;
		}
		$self->log->info("actionname $actionname job_id $job_id cookie $cookie"
			. " inargs '$inargs'");
		$inargs = decode_json(encode_utf8($inargs));

		my $task = {
			action => $action,
			inarggs => $inargs,
			cookie => $cookie,
			job_id => $job_id,
		};
		$self->tasks->{$cookie} = $task;

		$self->call_rpcs_nb(
			method => $methodname,
			inargs => $inargs,
			# no wait cb
			resultcb => sub {
				$self->_task_done($task, @_);
			},
		);
	})->catch(sub {
		 $self->log->error("_get_task caught $_[0]");
	}); # catch?
}


sub _task_done {
	my ($self, $task, $status, $outargs) = @_;
	
	delete $self->tasks->{$task->{cookie}};

	if (!$status or $status ne RES_OK) {
		# turn 'no worker available' and
		# 'worker gone' into soft errors
		if ($outargs and $outargs =~ /\(-3200(3|6)\)$/) {
			# turn into a soft retryable error
			$outargs = {
				error => {
					class => 'soft',
					msg => $outargs
				},
			};
		} else {
			$outargs = {
				error => $outargs,
			};
		}
	} 

	# in the jobcenter world outargs is always a object
	# so we need to wrap other result types
	if (ref $outargs eq 'ARRAY') {
		$outargs = {array => $outargs};
	} elsif (not ref $outargs) { 
		# do we want to distinguish string/number here?
		$outargs = {scalar => $outargs};
	}
	# should work as it came in via json rpc
	$outargs = decode_utf8(encode_json($outargs));

	$self->log->info("done with action $task->{action}->{actionname}"
		. " for job $task->{job_id}, outargs '$outargs'");

	Mojo::IOLoop->delay(
		sub {
			my ($d) = @_;
			$self->jcpg->queue_query($d->begin(0));
		},
		sub {
			my ($d, $db) = @_;
			$db->dollar_only->query(
				q[select task_done($1, $2)],
				$task->{cookie}, $outargs, $d->begin
			);
		},
		sub {
			my ($d, $err, $res) = @_;
			if ($err) {
				$self->log->error("task_done threw $err");
				return;
			}
			$res->finish(); # because we don't need the results
			#$self->log->debug("task_done_callback!");
			#print 'pending: ', Dumper($self->{pending});
			if ($task->{action}->{pending}) {

				# sigh.. we can't call get_task directly
				# bacause we're in a Mojo::Pg callback chain here
				# and recursing doesn't work
				Mojo::IOLoop->next_tick(sub {
					#$self->log->debug("calling _get_task from next_tick callback!");
					$self->_get_task(
						$task->{action},
						encode_json({
							poll => "pending_$task->{action}->{actionname}",
						})
					);
				});
				$self->log->debug("calling _get_task from task_done callback because of pending flag");
			}
		},
	)->catch(sub {
		 $self->log->error("_task_done caught $_[0]");
	});
}


# withdraw an action from the jobcenter
sub withdraw_jc {
	my ($self, %args) = @_;
	my $actionname = $args{action} or croak 'no action?';
	my $action = delete $self->actions->{$actionname};
	croak "unannounced action $actionname?" unless $action;
	delete $self->listenstrings->{$action->{listenstring}};

	my ($res) = $self->jcpg->db->query(
			q[select withdraw($1, $2)],
			$self->{workername},
			$actionname
		)->array;
	die "no result" unless $res and @$res;
	
	$self->jcpg->pubsub->unlisten($action->{listenstring});

	return 1;
}


# ping the pg database
sub _ping {
	my $self = shift;
	my $worker_id = shift;
	$self->log->debug("ping($worker_id)!");
	Mojo::IOLoop->delay(sub {
		my ($d) = @_;
		$self->jcpg->queue_query($d->begin(0));
	},
	sub {
		my ($d, $db) = @_;
		$db->query(
			q[select ping($1)],
			$worker_id,
			$d->begin
		);
	},
	sub {
		my ($d, $err, $res) = @_;
		if ($err) {
			$self->log->error("ping threw $err");
			return;
		}
		$res->finish();
		$res->db->dollar_only->query(
			q[select * from poll_tasks($1)],
			'{' . $worker_id . '}',
			$d->begin
		);
	},
	sub {
		my ($d, $err, $res) = @_;
		if ($err) {
			$self->log->error("poll_tasks threw $err");
			return;
		}
		my $rows = $res->sth->fetchall_arrayref();
		$res->finish;
		if (@$rows) {
			$self->log->warn('_process_poll: ' . (scalar @$rows) . ' rows');
			$self->_process_poll($rows);
		}
	})->catch(sub {
		 $self->log->error("_ping caught $_[0]");
	});
}


sub _process_poll {
	my ($self, $rows) = @_;

	for (@$rows) {
		my ($ls, $worker_ids, $count) = @$_;
		$self->log->debug("row: $ls, " . ($worker_ids // 'null') . " $count");
		my $action =  $self->listenstrings->{$ls};
		next unless $action; # die?

		#next if $action->{pending}; # already pending;
		$self->log->debug("set pending flag for $action->{actionname}");
		$action->{pending} = $count;

		Mojo::IOLoop->next_tick(sub {
			#$self->log->debug("calling _get_task from next_tick callback!");
			$self->_get_task(
				$action,
				encode_json({
					poll => "pending_$action->{actionname}",
				})
			);
		});
		$self->log->debug("calling _get_task from _process_poll!");
	}
}


# call a method on the rpc switch
sub call_rpcs_nb {
	my ($self, %args) = @_;
	my $method = $args{method} or die 'no method?';
	my $vtag = $args{vtag};
	my $inargs = $args{inargs} // '{}';
	my $waitcb = $args{waitcb}; # optional
	my $rescb = $args{resultcb} // die 'no result callback?';
	my $timeout = $args{timeout} // $self->timeout * 5; # a bit hackish..
	my $reqauth = $args{reqauth};
	my $inargsj;

	if (0) { # $self->{json}) {
		$inargsj = $inargs;
		$inargs = decode_json($inargs);
		croak 'inargs is not a json object' unless ref $inargs eq 'HASH';
		if ($reqauth) {
			$reqauth = decode_json($reqauth);
			croak 'reqauth is not a json object' unless ref $reqauth eq 'HASH';
		}
	} else {
		croak 'inargs should be a hashref' unless ref $inargs eq 'HASH';
		# test encoding
		$inargsj = encode_json($inargs);
		if ($reqauth) {
			croak 'reqauth should be a hashref' unless ref $reqauth eq 'HASH';
		}
	}

	$inargsj = decode_utf8($inargsj);
	$self->log->debug("calling $method with '" . $inargsj . "'" . (($vtag) ? " (vtag $vtag)" : ''));

	my $delay = Mojo::IOLoop->delay(
		sub {
			my $d = shift;
			$self->conn->callraw({
				method => $method,
				params => $inargs
			}, $d->begin(0));
		},
		sub {
			#print Dumper(@_);
			my ($d, $e, $r) = @_;
			if ($e) {
				$e = $e->{error};
				$self->log->error("call returned error: $e->{message} ($e->{code})");
				$rescb->(RES_ERROR, "$e->{message} ($e->{code})");
				return;
			}
			# print Dumper(\@_) unless Scalar::Util::reftype($r) eq "HASH";
			my ($status, $outargs) = @{$r->{result}};
			if ($status eq RES_WAIT) {
				#print '@$r', Dumper($r);
				my $vci = $r->{rpcswitch}->{vci};
				unless ($vci) {
					$self->log->error("missing rpcswitch vci after RES_WAIT");
					return;
				}

				# note the relation to the channel so we can throw an error if
				# the channel disappears
				# outargs should contain waitid
				# autovivification ftw?
				$self->{channels}->{$vci}->{$outargs} = $rescb;
				$waitcb->($status, $outargs) if $waitcb;
			} else {
				$outargs = encode_json($outargs) if $self->{json} and ref $outargs;
				$rescb->($status, $outargs);
			}
		}
	)->catch(sub {
		my ($err) = @_;
		$self->log->error("Something went wrong in call_rpcs_nb: $err");
		$rescb->(RES_ERROR, $err);
	});
}


sub _shutdown {
	my($self) = @_;
	$self->log->info("shutting down..");

	# explicit copy becuase we modify the hash below
	my @actions = keys %{$self->actions};
	for my $action (@actions) {
		$self->log->debug("withdrawing action $action from the jobcenter");
		$self->withdraw_jc(action => $action);
	}

	# only try to withdraw methods from the rpcswitch if we're still connected..
	unless ($self->{_exit}) {
		for my $method (keys %{$self->methods}) {
			$self->log->debug("withdrawing method $method from the rpcswitch");
			$self->withdraw_rpcs(method => $method);
		}
		$self->methods({});
	}

	$self->log->info('sending soft errors for ' . (scalar keys %{$self->{tasks}}) . ' unfinished tasks');
	$self->_task_done($_, { error => { class => 'soft', msg => 'jcswitch shutting down'}})
		for (%{$self->{tasks}});

}

1;
