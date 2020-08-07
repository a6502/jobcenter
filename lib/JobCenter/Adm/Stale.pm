package JobCenter::Adm::Stale;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	my $verbose = 0;

	my @workflows;
	for (@_) {
		/^(?:-v|--verbose)$/ and do { $verbose++; next };
		/^-(v+)$/            and do { $verbose += length $1; next };
		/^-/                 and do { die "unknown flag: $_\n" };
		push @workflows, $_;
	}

	return $self->_show($verbose, \@workflows);
}

sub _select_outofdate {
	my ($self, $verbose, $workflows) = @_;

	my $qs = join ',', ('?')x(@$workflows);

	my $result = $self->adm->pg->db->query(qq[
		set intervalstyle = 'postgres_verbose';
		select 
			j.job_id,
			j.state,
			a1.name as workflow_name, 
			j.workflow_id as job_workflow_id, 
			a2.action_id as current_workflow_id
			${\($verbose ? ", now() - j.job_created running" : "" )}
		from 
			jobs j 
		join 
			actions a1 
		on 
			j.workflow_id = a1.action_id 
		join 
			actions a2 
		on 
			a1.name = a2.name and a2.action_id > j.workflow_id 
		where 
			j.job_finished is null
			${\($qs ? "and a1.name in ($qs)" : "")}
		order by 
			j.state, a1.name, j.job_id
	], @$workflows);

	return $result;
}



sub _show {
	my $self = shift;
	my $result = $self->_select_outofdate(@_);
	
	my @rows = ( 
		$result->columns(),
		@{$result->arrays()},
	);

	if ($#rows) {
		$self->tablify(\@rows, 'stale workflows for running jobs:');
	} else {
		say 'no stale workflows for jobs';
	}

	return 0;
}

1;


