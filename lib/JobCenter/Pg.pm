package JobCenter::Pg;
use Mojo::Base 'Mojo::Pg';

use JobCenter::Pg::Db;

has log => sub { Mojo::Log->new(level => 'debug'); };
has max_total_connections =>   10; # or what?
has max_connection_reuse  => 5432; # drop connection after this many dequeues

sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);

	$self->{database_class} = 'JobCenter::Pg::Db';

	$self->{__jcpg_concount} = 0;
	$self->{__jcpg_queryqueue} = undef;
	$self->{__jcpg_dbhqueue} = [];

	#say "made $self";
	return $self;
}

sub db {
	my ($self) = @_;
	return JobCenter::Pg::Db->new(
		dbh => $self->__jcpg_dequeue('yes, really'),
		pg => $self,
	);
}

# fixme: better name?
sub queue_query {
	my ($self, $cb) = @_;
	die 'no cb?' unless ref $cb eq 'CODE';

	#$self->log->debug("queue_query for $cb");

	# query queue
	my $qq = $self->{__jcpg_queryqueue};

	# if a query queue exists, put ourselves at the back to prevent
	# starvation
	if ($qq) {
		#$self->log->info("queue_query: queueing $cb because of existing queue");
		push @$qq, $cb;
		return;
	}

	my $dbh = $self->__jcpg_dequeue;
	
	if (not $dbh) {
		# out of dbhs, create the queue and put ourselves
		# on it
		#$self->log->info("queue_query: queueing $cb because of no more dbhs");
		$self->{__jcpg_queryqueue} = [ $cb ];
		return;
	}

	# make a new JobCenter::Pg::Db object around the dbh
	my $db = JobCenter::Pg::Db->new(dbh => $dbh, pg => $self);
	
	#$self->log->debug("queue_query: scheduling $cb with $dbh");
	# and schedeule the cb to be called
	Mojo::IOLoop->next_tick(sub {
		#$self->log->debug("queue_query: calling $cb with $dbh");
		local $@;
		unless (eval { $cb->($db); 1;}) {
			$self->log->error("queue_query: $cb got $@");
			# do not try to reuse after an error
			$db->dbh->{private_mojo_no_reuse} = 1;
			# maybe we want our own flag for that?
		}
		#$self->log->debug("queue_query: done with $cb with $db");
	});
}

# our own private methods, different from those of the parent...

sub __jcpg_dequeue {
	my ($self, $really) = @_;

	# Fork-safety
	delete @$self{qw(pid queue)} unless ($self->{pid} //= $$) eq $$;

	my $dbhqueue = $self->{__jcpg_dbhqueue} // [];

	while (my $dbh = shift @$dbhqueue) {
		if ($dbh->ping()) {
			$self->log->debug("__jcpg_dequeue: using cached connection $dbh; ".
				(scalar @$dbhqueue) . ' cached connections left');
			$dbh->{private_jcpg_times_used}++;
			return $dbh;
		}
	}

	if ($self->{__jcpg_concount} >= $self->{max_total_connections}) {
		$self->log->debug('__jcpg_dequeue: concount ' . $self->{__jcpg_concount} .
			' >= maxcon ' . $self->{max_total_connections});
		# the $really flag allows the caller to signal it really needs a dbh now
		return unless $really;
	}

	my $dbh = DBI->connect(map { $self->$_ } qw(dsn username password options));

	# Search path
	if (my $path = $self->search_path) {
		my $search_path = join ', ', map { $dbh->quote_identifier($_) } @$path;
		$dbh->do("set search_path to $search_path");
	}

	$self->log->debug("__jcpg_dequeue: new dbh $dbh");
	$self->emit(connection => $dbh);
	$self->{__jcpg_concount}++;

	$self->log->debug("__jcpg_dequeue: $self->{__jcpg_concount} total connections");

	$dbh->{private_jcpg_max_reuse} = $self->max_connection_reuse
		- int(rand($self->max_connection_reuse / 10));
	$dbh->{private_jcpg_times_used}++;

	return $dbh;
}

sub __jcpg_enqueue {
	my ($self, $dbh) = @_;
	#$self->log->info("__jcpg_enqueue: $dbh");

	# fixme: own flag?
	if ($dbh->{private_mojo_no_reuse} or not $dbh->{Active}) {
		$self->log->debug("__jcpg_enqueue: freeing dbh $dbh because of no reuse");
		$self->{__jcpg_concount}--;
		$dbh = undef;
		return;
	}

	my $qq = $self->{__jcpg_queryqueue};
	if ($qq) {
		$self->log->debug('__jcpg_enqueue: ' . scalar @$qq . ' queries in queue');

		my $cb = shift @$qq;
		$self->{__jcpg_queryqueue} = undef unless @$qq;

		# make a new JobCenter::Pg::Db object around the dbh
		my $db = JobCenter::Pg::Db->new(dbh => $dbh, pg => $self);

		#$self->log->debug("__jcpg_enqueue: scheduling $cb with $dbh");
		
		# and schedeule the cb to be called
		Mojo::IOLoop->next_tick(sub {
			local $@;
			#$self->log->debug("__jcpg_enqueue: calling $cb with $dbh");
			unless (eval { $cb->($db); 1;}) {
				$self->log->error("$cb got $@");
				# do not try to reuse after an error
				$db->dbh->{private_mojo_no_reuse} = 1;
				# maybe we want our own flag for that?
			}
			#$self->log->debug("__jcpg_enqueue: done $cb with $db");
		});
		return;
	}

	# if we really have no work for this dbh (i.e. queryqueue empty) see if it
	# has been overused
	if ( ($dbh->{private_jcpg_times_used} // 0) >
		 ($dbh->{private_jcpg_max_reuse} // $self->max_connection_reuse)) {
		$self->log->debug("__jcpg_enqueue: freeing dbh $dbh after being used " . 
			"$dbh->{private_jcpg_times_used} times");
		$self->{__jcpg_concount}--;
		$dbh = undef;
		return;
	}

	#$self->log->debug("__jcpg_enqueue: times used: $dbh->{private_jcpg_times_used}");

	my $dbhqueue = $self->{__jcpg_dbhqueue} ||= [];
	push @$dbhqueue, $dbh; # if $dbh->{Active};

	#$self->log->debug("__jcpg_enqueue: dbhqueue: before " . join(', ', @$dbhqueue));
	while (scalar @$dbhqueue > $self->{max_total_connections}) {
		my $foo = shift @$dbhqueue;
		$self->log->debug("__jcpg_enqueue: freeing dbh $foo");
		$foo = undef;
		$self->{__jcpg_concount}--;
	}
	#$self->log->debug("__jcpg_enqueue: dbhqueue: after  " . join(', ', @$dbhqueue));

	$self->log->debug("__jcpg_enqueue: $self->{__jcpg_concount} total connections and " .
		scalar @$dbhqueue . ' cached connections');
}


1;
