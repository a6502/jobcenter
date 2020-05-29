package JobCenter::Adm::Api::Clients;

use Mojo::Base 'JobCenter::Adm::Api::Cmd';

sub do_cmd {
	return $_[0]->do_simple_api_cmd('clients');
}

1;

