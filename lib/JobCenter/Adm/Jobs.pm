package JobCenter::Adm::Jobs;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	my $verbose;

	for (@_) {
		/^-v$/ and $verbose = 1;
	}
	
	return $verbose ? $self->_verbose : $self->_summary;
}

sub _verbose {
	my $self = shift;
	my $pg = $self->adm->pg;
	
	my $result = $pg->db->dollar_only->query(q[
		select
			state,
			count(*) as count
		from
			jobs
		where
			job_finished is null
		group by
			state
		order by
			count desc
	]);

	my $found;
	
	for my $jobs (@{$result->hashes}) {

		my $result = $pg->db->query(q[
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

	say 'no unfinshed jobs' unless $found;

	return 0;
}

sub _summary {
	my $self = shift;
	my $pg = $self->adm->pg;
	
	my $result = $pg->db->dollar_only->query(q[
		select
			state,
			count(*) as count
		from
			jobs
		where
			job_finished is null
		group by
			state
		order by
			count desc
	]);
	
	my @rows;
	push @rows, $result->columns();
	push @rows, @{$result->arrays()};

	if ($#rows) {
		$self->tablify(\@rows, 'unfished jobs:');
	} else {
		say 'no unfinshed jobs';
	}

	return 0;
}

1;

