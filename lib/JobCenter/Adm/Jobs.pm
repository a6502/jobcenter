package JobCenter::Adm::Jobs;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	my $verbose = 0;

	my @states;
	for (@_) {
		/^(?:-v|--verbose)$/ and do { $verbose++; next };
		/^-(v+)$/            and do { $verbose += length $1; next };
		/^-/                 and do { die "unknown flag: $_\n" };
		push @states, $_;
	}
	
	return $verbose > 1 ? $self->_verbose(\@states) : $self->_summary(\@states, $verbose);
}

sub _select_counts {
	my ($self, $states, $details) = @_;

	my @det = $details ? ('a.name,', 'join actions a on j.workflow_id = a.action_id') : ('', '');

	my @qs   = ("?")x@$states;
	local $" = ', ';

	my $cond = @qs ? "and j.state in (@qs)" : '';
	my $result = eval { $self->adm->pg->db->query(qq[
		select
			j.state, 
			$det[0]
			count(*) as count
		from
			jobs j
			$det[1]
		where
			j.job_finished is null
			$cond
		group by
			$det[0]
			j.state
		order by
			$det[0]
			count desc
	], @$states)};

	if (my $e = $@) {
		die $e =~ /invalid input value for enum job_state: "([^"]+)"/
			? "unknown job_state: $1\n"
			: $e;
	}

	return $result;
}

sub _verbose {
	my ($self, $states) = @_;
	my $result = $self->_select_counts($states, 0);

	my $found;
	
	for my $jobs (@{$result->hashes}) {

		my $result = $self->adm->pg->db->query(q[
			select
				j.job_id as job_id,
				j.workflow_id as workflow_id,
				wf.name as workflow_name,
				to_char(j.job_created, 'yyyy-mm-dd HH24:MI:SS') as created,
				to_char(j.tasK_started, 'yyyy-mm-dd HH24:MI:SS') as started
			from
				jobs as j join actions as wf
			on 
				j.workflow_id = wf.action_id
			where
				j.state = ? and
				j.job_finished is null
			order by
				j.job_id desc, j.workflow_id
		], $jobs->{state});

		my @rows = ($result->columns, @{$result->arrays});

		if (@rows > 1) {
			$found = 1;
			$self->tablify(\@rows, "\njobs: unfinished - $jobs->{state} ($jobs->{count})");
		}
	}

	say 'no unfinished jobs' unless $found;

	return 0;
}

sub _summary {
	my $self = shift;
	my $result = $self->_select_counts(@_);
	
	my @rows;
	push @rows, $result->columns();
	push @rows, @{$result->arrays()};

	if ($#rows) {
		$self->tablify(\@rows, 'unfinished jobs:');
	} else {
		say 'no unfinished jobs';
	}

	return 0;
}

1;

