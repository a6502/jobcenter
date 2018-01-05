package JobCenter::Adm::Pending;

use Mojo::Base 'JobCenter::Adm::Cmd';

use Data::Dumper;

sub do_cmd {
	my $self = shift;
	
	my $client = $self->adm->client();
	
	my ($result) = $client->get_api_status('pending');
	
	print Dumper($result);

	return 0;
}

1;

