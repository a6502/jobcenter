package JobCenter::Adm::Pending;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	
	my $client = $self->adm->client();
	
	my ($result) = $client->get_api_status('pending');
	
	unless (ref $result eq 'HASH') {
		say 'no result from api?';
		return 1;
	}

	my @rows = [qw(action pending)];
	push @rows, [$_, $result->{$_}] for keys %$result;
	$self->tablify(\@rows, 'jobs pending flags in the api');


	return 0;
}

1;

