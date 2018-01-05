package JobCenter::Adm::Jobs;

use Mojo::Base 'JobCenter::Adm::Cmd';

use Data::Dumper;

sub do_cmd {
	my $self = shift;
	
	my $pg = $self->adm->pg;
	
	my $result = $pg->db->dollar_only->query(
		q[select state, count(*) from jobs where job_finished is null group by state]
	)->hashes();
	
	print Dumper($result);

	return 0;
}

1;

