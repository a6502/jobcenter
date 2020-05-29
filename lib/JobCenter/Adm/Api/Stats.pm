package JobCenter::Adm::Api::Stats;

use Mojo::Base 'JobCenter::Adm::Api::Cmd';

use Data::Printer;

sub do_cmd {
	my $self = shift;
	
	my $client = $self->adm->client();
	
	my $result = $client->get_api_status('stats');

	unless ($result) {
		say 'no result from api?';
		return 1;
	}

	p $result;
}

1;

