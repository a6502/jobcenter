package JobCenter::MojoClient;

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
use Mojo::Pg;

# standard
use Cwd qw(realpath);
use Data::Dumper;
use File::Basename;
use FindBin;
use IO::Pipe;

# other
use Config::Tiny;
use JSON::MaybeXS qw(decode_json encode_json);

# JobCenter
use JobCenter::MojoClient::Job;

has [qw(cfg clientname debug json log pg timeout)];

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

	my $clientname = ($args{clientname} || fileparse($0)) . " [$$]";

	# make our clientname the application_name visible in postgresql
	$ENV{'PGAPPNAME'} = $clientname;
	my $pg = Mojo::Pg->new(
		'postgresql://'
		. $cfg->{client}->{user}
		. ':' . $cfg->{client}->{pass}
		. '@' . ( $cfg->{pg}->{host} // '' )
		. ( ($cfg->{pg}->{port}) ? ':' . $cfg->{pg}->{port} : '' )
		. '/' . $cfg->{pg}->{db}
	);

	$pg->pubsub->listen($clientname, sub { say 'ohnoes!'; exit(1) });

	$self->{cfg} = $cfg;
	$self->{pg} = $pg;
	$self->{clientname} = $clientname;
	$self->{debug} = $args{debug} // 1;
	$self->{json} = $args{json} // 1;
	$self->{log} = $args{log} // Mojo::Log->new;
	$self->{timeout} = $args{timeout} // 60;
	#$self->catch(sub { my ($self, $err) = @_; say "This looks bad: $err"; });
	return $self;
}

sub _poll_done_old {
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

		local $@;
		eval { $job->cb->($job->{job_id}, $outargs); };
		$self->log->debug("got $@ calling callback") if $@;
	}
	return $outargs; # at least true
}

sub _poll_done {
	my ($self, $job) = @_;
	Mojo::IOLoop->delay->steps(
		sub {
			my $d = shift;
			$self->pg->db->dollar_only->query(
				q[select * from get_job_status($1)],
				$job->job_id,
				$d->begin
			);
		},
		sub {
			my ($d, $err, $res) = @_;
			die $err if $err;
			my ($outargs) = @{$res->array};
			return unless $outargs;
			#$self->pg->pubsub->unlisten($job->listenstring);
			$self->pg->pubsub->unlisten('job:finished', $job->lcb);
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
	);
}

sub call {
	my ($self, %args) = @_;
	my ($done, $job_id, $outargs);
	$args{waitcb} = sub{ say 'foo';};
	$args{resultcb} = sub {
		say 'bar', Dumper(\@_);
		($job_id, $outargs) = @_;
		$done++;
	};
	$self->call_nb(%args);

	Mojo::IOLoop->one_tick while !$done;

	return $job_id, $outargs;
}

sub call_nb_old {
	my ($self, %args) = @_;
	my $wfname = $args{wfname} or die 'no workflowname?';
	my $vtag = $args{vtag};
	my $inargs = $args{inargs} // '{}';
	my $cb = $args{cb} or die 'no callback?';
	my $timeout = $args{timeout} // 60;

	if ($self->{json}) {
		# sanity check json string
		my $inargsp = decode_json($inargs);
		die 'inargs is not a json object' unless ref $inargsp eq 'HASH';
	} else {
		die  'inargs should be a hashref' unless ref $inargs eq 'HASH';
		$inargs = encode_json($inargs);
		#$self->log->debug("inargs as json: $inargs");
	}

	$self->log->debug("calling $wfname with '$inargs'" . (($vtag) ? " (vtag $vtag)" : ''));
	#say "inargs: $inargs";
	my ($job_id, $listenstring);
	# create_job throws an error when:
	# - wfname does not exist
	# - inargs not valid
	$self->log->debug("create_job $wfname inargs $inargs");
	($job_id, $listenstring) = @{$self->pg->db->dollar_only->query(
		q[select * from create_job($1, $2, $3)],
		$wfname,
		$inargs,
		$vtag
	)->array};
	die "no result from call to create_job" unless $job_id;
	$self->log->debug("created job_id $job_id listenstring $listenstring");

	my $job = JobCenter::MojoClient::Job->new(
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

sub call_nb {
	my ($self, %args) = @_;
	my $wfname = $args{wfname} or die 'no workflowname?';
	my $vtag = $args{vtag};
	my $inargs = $args{inargs} // '{}';
	my $waitcb = $args{waitcb} or die 'no wait callback?';
	my $resultcb = $args{resultcb} or die 'no result callback?';
	my $timeout = $args{timeout} // 60;

	if ($self->{json}) {
		# sanity check json string
		my $inargsp = decode_json($inargs);
		die 'inargs is not a json object' unless ref $inargsp eq 'HASH';
	} else {
		die  'inargs should be a hashref' unless ref $inargs eq 'HASH';
		$inargs = encode_json($inargs);
		#$self->log->debug("inargs as json: $inargs");
	}

	my $impersonate; # = $client->who;
	my $env;

	#$inargs = decode_utf8(encode_json($inargs));

	$self->log->debug("calling $wfname with '$inargs'" . (($vtag) ? " (vtag $vtag)" : ''));

	# create_job throws an error when:
	# - wfname does not exist
	# - inargs not valid
	Mojo::IOLoop->delay->steps(
		sub {
			my $d = shift;
			#($job_id, $listenstring) = @{
			$self->pg->db->dollar_only->query(
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
				$resultcb->(undef, $err);
				return;
			}
			my ($job_id, $listenstring) = @{$res->array};
			unless ($job_id) {
				$resultcb->(undef, "no result from call to create_job");
				return;
			}

			# report back to our caller immediately
			# this prevents the job_done notification overtaking the 
			# 'job created' result...
			$self->log->debug("created job_id $job_id listenstring $listenstring");
			$waitcb->($job_id, undef);

			my $job = JobCenter::Api::Job->new(
				cb => $resultcb,
				job_id => $job_id,
				inargs => $inargs,
				listenstring => $listenstring,
				vtag => $vtag,
				wfname => $wfname,
			);

			#$self->pg->pubsub->listen($listenstring, sub {
			# fixme: 1 central listen?
			my $lcb = $self->pg->pubsub->listen('job:finished', sub {
				my ($pubsub, $payload) = @_;
				$self->log->debug("notify job:finished $payload");
				return unless $job_id == $payload;
				local $@;
				eval { $self->_poll_done($job); };
				$self->log->debug("pubsub cb $@") if $@;
			});

			my $tmr;
			$tmr = Mojo::IOLoop->timer($timeout => sub {
				# request failed, cleanup
				#$self->pg->pubsub->unlisten($listenstring);
				$self->pg->pubsub->unlisten('job:finished' => $lcb);
				# the cb might fail if the connection is gone..
				eval { &$resultcb->($job_id, {'error' => 'timeout'}); };
				$job->delete;
			}) if $timeout > 0;
			#$self->log->debug("setting tmr: $tmr") if $tmr;

			$job->update(tmr => $tmr, lcb => $lcb);

			# do one poll first..
			$self->_poll_done($job);
		}
	)->catch(sub {
		my ($delay, $err) = @_;
		$resultcb->(undef, $err);
	});
}



1;
