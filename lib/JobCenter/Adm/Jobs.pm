package JobCenter::Adm::Jobs;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	my $verbose;

	my @states;
	for (@_) {
		/^-v$/ and do { $verbose = 1; next };
		/^-/   and do { die "unknown flag: $_\n" };
		push @states, $_;
	}
	
	return $verbose ? $self->_verbose(@states) : $self->_summary(@states);
}

sub _select_counts {
	my $self = shift;
	my @qs   = ("?")x@_;
	local $" = ', ';

	my $states = @qs ? "and state in (@qs)" : '';
	my $result = eval { $self->adm->pg->db->query(qq[
		select
			state,
			count(*) as count
		from
			jobs
		where
			job_finished is null
			$states
		group by
			state
		order by
			count desc
	], @_)};

	if (my $e = $@) {
		die $e =~ /invalid input value for enum job_state: "([^"]+)"/
			? "unknown job_state: $1\n"
			: $e;
	}

	return $result;
}

sub _verbose {
	my $self = shift;
	my $result = $self->_select_counts(@_);

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

