package JobCenter::MojoClient;

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

	my $clientname = $args{clientname} || fileparse($0);

	# make our clientname the application_name visible in postgresql
	$ENV{'PGAPPNAME'} = $clientname . " [$$]";
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
	$self->{clientname} = $clientname . " [$$]";
	$self->{debug} = $args{debug} // 1;
	$self->{json} = $args{json} // 1;
	$self->{log} = $args{log} // Mojo::Log->new;
	$self->{timeout} = $args{timeout} // 60;
	$self->catch(sub { my ($self, $err) = @_; say "This looks bad: $err"; });
	return $self;
}

sub _poll_done {
	my ($self, $job) = @_;
	my $res = $self->pg->db->dollar_only->query(q[select * from get_job_status($1)], $job->job_id)->array;
	return unless $res and @$res and @$res[0];
	my $outargs = @$res[0];
	$self->pg->pubsub->unlisten($job->listenstring);
	Mojo::IOLoop->remove($job->tmr) if $job->tmr;
	if ($job->cb) {
		$self->log->debug("calling cb $job->{cb} for job_id $job->{job_id} outargs $outargs");
		local $@;
		eval { &{$job->cb}($outargs); };
		self->log->debug("got $@") if $@;
	}
	return $outargs; # at least true
}

sub call {
	my ($self, %args) = @_;
	my $wfname = $args{wfname} or die 'no workflowname?';
	my $vtag = $args{vtag};
	my $inargs = $args{inargs} // '{}';
	my $cb = $args{cb};
	say 'foo!';

	if ($self->{json}) {
		# sanity check json string
		my $inargsp = decode_json($inargs);
		die 'inargs is not a json object' unless ref $inargsp eq 'HASH';
	} else {
		die  'inargs should be a hashref' unless ref $inargs eq 'HASH';
		$inargs = encode_json($inargs);
		$self->log->debug("inargs as json: $inargs");
	}

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
		say "pubsub cb $@" if $@;
	});

	# do one poll first..
	my ($out);
	if ($out = $self->_poll_done($job)) {
		return $out;
	} else {
		# set up timeout of 60 seconds
		my $tmr = Mojo::IOLoop->timer( 300 => sub {
			# request failed, cleanup
			$self->pg->pubsub->unlisten($listenstring);
			&$cb($job_id, {'error' => 'timeout'});
		});
		$job->update(cb => $cb, tmr => $tmr);
	};

	say "bar!";
	return if $cb;

	# how do we wait?
	while (not $out = $self->_poll_done($job)) {
		Mojo::IOLoop->one_tick;
	}

	return $out;
}


1;
