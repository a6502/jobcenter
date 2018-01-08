package JobCenter::Adm::Jobs;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
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

