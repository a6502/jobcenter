package JobCenter::Adm::Clients;

use Mojo::Base 'JobCenter::Adm::Cmd';

#use Data::Dumper;

sub do_cmd {
	my $self = shift;
	
	my $client = $self->adm->client();
	
	my ($result) = $client->get_api_status('clients');

	#print Dumper($result);

	unless (ref $result eq 'ARRAY') {
		say 'no result from api?';
		return 1;
	}

	say 'connected clients:';
	for my $c (@$result) {
		say '=' x 64;
		say 'who : ', $c->{who} // '<unknown>', '(', $c->{from} // 'somewhere' ,')';
		say 'workername: ', $c->{workername} // 'none';
		my $wa = $c->{workeractions};
		if ($wa and %$wa) {
			my @keys = qw(slotgroup filter);
			my @rows = ['actionname', @keys];
			push @rows, [$_, @{$wa->{$_}}{@keys}] for keys %$wa;
			$self->tablify(\@rows, 'workeractions:');
		} else {
			say 'workeractions: none';
		}
		my $sg = $c->{slotgroups};
		if ($sg and %$sg) {
			my @keys = qw(slots used);
			my @rows = ['name', @keys];
			push @rows, [$_, @{$sg->{$_}}{@keys}] for keys %$sg;
			$self->tablify(\@rows, 'slotgroup:');
		} else {
			say 'slotgroups: none';
		}
		print "\n";
	}

	return 0;
}

1;

