package JobCenter::Adm::Errors;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	my ($verbose, $cutoff);

	my @names;
	while (@_) {
		local $_ = shift @_;
		/^(?:-v|--verbose)$/ and do { $verbose = 1; next };
		/^(?:-c|--cutoff)(?:(=)(.*))?$/ and do { 
			$cutoff = $1 ? $2 : shift @_;
			next;
		};
		/^-/ and die "unknown flag: $_\n";
		push @names, $_;
	}

	return $verbose ? $self->_verbose($cutoff, \@names) : $self->_summary($cutoff, \@names);
}

sub _select_counts {
	my ($self, $cutoff, $names) = @_;

	my @qs   = ("?")x@$names;
	local $" = ', ';

	my $cond = '';
	$cond .= 'and coalesce(job_finished, task_completed, task_started, job_created) >= ? ' if $cutoff;
	$cond .= "and a.name in (@qs) " if @$names;

	my $result = eval { $self->adm->pg->db->query(qq[
		select count(*) as count, a.name as workflow_name
		from jobs j
		join actions a 
		on j.workflow_id = a.action_id
		where j.state = 'error'
		$cond
		group by a.name
	], ($cutoff ? $cutoff : ()), @$names)};

	if (my $e = $@) {
		die $e =~ /invalid input syntax for type timestamp with time zone: "([^"]+)"/
			? "invalid cutoff: $1\n"
			: $e;
	}

	return $result;
}

sub _verbose {
	my ($self, $cutoff, $names) = @_;
	my $result = $self->_select_counts($cutoff, $names);

	my $found;
	my $cond = $cutoff
		? 'and coalesce(job_finished, task_completed, task_started, job_created) >= ? '
		: '';
	
	for my $jobs (@{$result->hashes}) {

		my $result = $self->adm->pg->db->query(qq[
			select
				j.job_id as job_id,
				j.workflow_id as workflow_id,
				wf.name as workflow_name,
				to_char(j.job_created, 'yyyy-mm-dd HH24:MI:SS') as created,
				to_char(coalesce(job_finished, task_completed, task_started, job_created), 
					'yyyy-mm-dd HH24:MI:SS') as last_change
			from
				jobs as j join actions as wf
			on 
				j.workflow_id = wf.action_id
			where j.state = 'error' and wf.name = ?
				$cond
			order by
				j.job_id desc, j.workflow_id
		], $jobs->{workflow_name}, ($cutoff ? $cutoff : ()));

		my @rows = ($result->columns, @{$result->arrays});

		if (@rows > 1) {
			$found = 1;
			$self->tablify(\@rows, "\njob errors: - $jobs->{workflow_name} ($jobs->{count})");
		}
	}

	say 'no job errors' unless $found;

	return 0;
}

sub _summary {
	my $self = shift;
	my $result = $self->_select_counts(@_);
	
	my @rows;
	push @rows, $result->columns();
	push @rows, @{$result->arrays()};

	if ($#rows) {
		$self->tablify(\@rows, 'job errors:');
	} else {
		say 'no job errors';
	}

	return 0;
}

1;


