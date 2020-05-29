package JobCenter::Adm::Api::Cmd;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_simple_api_cmd {
	my ($self, $cmd) = @_;
	
	my $client = $self->adm->client();
	
	my ($result) = $client->get_api_status($cmd);
	
	unless ($result) {
		say 'no result from api?';
		return 1;
	}

	say $result;

	return 0;
}


1;
