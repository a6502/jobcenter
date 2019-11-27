package JobCenter::Adm::Locks;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	my $verbose = 0;

	my @locktypes;
	while (@_) {
		local $_ = shift @_;
		/^(?:-v|--verbose)$/ and do { $verbose++; next };
		/^(?:-vv)$/ and do { $verbose += 2; next };
		/^-/ and die "unknown flag: $_\n";
		push @locktypes, $_;
	}

	# verbosity=0  - print summary
	# verbosity=1  - print delatiled summary
	# verbosity=2+ - print verbose

	return $verbose > 1 
		? $self->_verbose(\@locktypes) 
		: $self->_summary(\@locktypes, $verbose);
}

sub _select_counts {
	my ($self, $locktypes, $detailed) = @_;

	my @qs   = ("?")x@$locktypes;
	local $" = ', ';

	my @det = $detailed ? (', lockvalue', ', l.lockvalue') : ('', '');
	my $cond = @$locktypes ? "locktype in (@qs)" : 'true';

	my $result = $self->adm->pg->db->query(qq[
		select lock, locktype $det[0], count(*) as count
		from (
			select 'waiting' as lock, l.locktype $det[1]
			from jobs j 
			join locks l 
			on j.task_state->>'waitforlocktype' = l.locktype 
				and j.task_state->>'waitforlockvalue' = l.lockvalue 
				and j.state = 'lockwait' 
			union all 
			select 'held' as lock, l.locktype $det[1]
			from jobs j 
			join locks l 
			on j.job_id = l.job_id
		) as ja 
		where $cond
		group by lock, locktype $det[0]
		order by lock, locktype $det[0]
	], @$locktypes);

	return $result;
}

sub _verbose {
	my ($self, $locktypes) = @_;

	my $result = $self->_select_counts($locktypes, 1);

	my $found;
	
	for my $jobs (@{$result->hashes}) {

		my $result = $self->adm->pg->db->query(
			$jobs->{lock} eq 'waiting' 
			? qq[
				select
					j.job_id as job_id,
					j.workflow_id as workflow_id,
					wf.name as workflow_name,
					to_char(j.job_created, 'yyyy-mm-dd HH24:MI:SS') as created,
					to_char(j.task_entered, 'yyyy-mm-dd HH24:MI:SS') as lock_wait
				from jobs as j 
				join actions as wf
				on j.workflow_id = wf.action_id
				join locks as l
				on j.task_state->>'waitforlocktype' = l.locktype 
					and j.task_state->>'waitforlockvalue' = l.lockvalue 
					and j.state = 'lockwait' 
				where l.locktype = ? and l.lockvalue = ?
				order by j.job_id desc, j.workflow_id
			]
			: qq[
				select
					j.job_id as job_id,
					j.workflow_id as workflow_id,
					wf.name as workflow_name,
					to_char(j.job_created, 'yyyy-mm-dd HH24:MI:SS') as created
				from jobs as j 
				join actions as wf
				on j.workflow_id = wf.action_id
				join locks as l
				on j.job_id = l.job_id
				where l.locktype = ? and l.lockvalue = ?
				order by j.job_id desc, j.workflow_id
			], @{$jobs}{qw/locktype lockvalue/});

		my @rows = ($result->columns, @{$result->arrays});

		if (@rows > 1) {
			$found = 1;
			$self->tablify(\@rows, "\njob locks ($jobs->{lock}): $jobs->{locktype}=$jobs->{lockvalue} ($jobs->{count})");
		}
	}

	say 'no job locks' unless $found;

	return 0;
}

sub _summary {
	my $self = shift;
	my $result = $self->_select_counts(@_);
	
	my @rows;
	push @rows, $result->columns();
	push @rows, @{$result->arrays()};

	if ($#rows) {
		$self->tablify(\@rows, 'job locks:');
	} else {
		say 'no job locks';
	}

	return 0;
}

1;


