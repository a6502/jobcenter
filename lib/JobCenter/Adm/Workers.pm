package JobCenter::Adm::Workers;

use Mojo::Base 'JobCenter::Adm::Cmd';

use Text::Table::Tiny 0.04 qw(generate_table);

sub do_cmd {
	my $self = shift;
	
	my $pg = $self->adm->pg;
	
	my $result = $pg->db->dollar_only->query(q[
		select
			worker_id,
			w.name as workername,
			a.action_id,
			a.name as actionname,
			wa.filter,
			w.started
		from
			workers w 
			join worker_actions wa using (worker_id)
			join actions a using (action_id)
		where
			1=1
		order by w.started, filter
	]);
	
	my @rows;
	push @rows, $result->columns();
	push @rows, @{$result->arrays()->sort(sub {
		$a->[0] <=> $b->[0] or
		$a->[3] cmp $b->[3]
	})};
	
	$self->tablify(\@rows, 'active workers according to the database:');

	return 0;
}

1;

