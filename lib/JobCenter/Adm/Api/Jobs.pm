package JobCenter::Adm::Api::Jobs;

use Mojo::Base 'JobCenter::Adm::Api::Cmd';

sub do_cmd {
	return $_[0]->do_simple_api_cmd('jobs');
}

1;

