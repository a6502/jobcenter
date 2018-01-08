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
		say "who : $c->{who} ($c->{from})";
		say 'workername: ', $c->{workername} // 'none';
		my $a = $c->{actions};
		if ($a and %$a) {
			my @keys = qw(slots used filter);
			my @rows = ['actionname', @keys];
			push @rows, [$_, @{$a->{$_}}{@keys}] for keys %$a;
			$self->tablify(\@rows, 'actions:');
		} else {
			say 'actions: none';
		}
		print "\n";
	}

	return 0;
}

1;

