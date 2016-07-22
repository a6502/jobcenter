package JobCenter::Api::Task;
use Mojo::Base 'Mojo::EventEmitter';

has [qw(actionname client cookie inargs job_id listenstring outargs tmr)];

sub update {
	my ($self, %attr) = @_;
	my ($k,$v);
	while (($k, $v) = each %attr) {
		$self->{$k} = $v;
	}
	return $self;
}

#sub DESTROY {
#	my $self = shift;
#	say 'destroying ', $self;
#}

1;
