package JobCenter::Adm::Tasks;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	
	my $client = $self->adm->client();
	
	my ($result) = $client->get_api_status('tasks');
	
	unless (ref $result eq 'ARRAY') {
		say 'no result from api?';
		return 1;
	}

	my @rows = [qw(tasks)];
	push @rows, [ $_] for @$result;
	$self->tablify(\@rows, 'queued tasks in the api');

	return 0;
}

1;

