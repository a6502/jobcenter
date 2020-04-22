package JobCenter::Adm::Tasks;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	
	my $client = $self->adm->client();
	
	my ($result) = $client->get_api_status('tasks');
	
	unless ($result) {
		say 'no result from api?';
		return 1;
	}

	say $result;

	return 0;
}

1;

