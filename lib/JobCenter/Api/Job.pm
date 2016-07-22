package JobCenter::Api::Job;
use Mojo::Base 'Mojo::EventEmitter';

has [qw(cb job_id inargs listenstring timeout tmr vtag wfname)];

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
