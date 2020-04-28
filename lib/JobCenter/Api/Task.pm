package JobCenter::Api::Task;
use Mojo::Base -base;

has [qw(action client cookie inargs job_id outargs tmr
	workers workeraction)];

sub update {
	my ($self, %attr) = @_;
	my ($k,$v);
	while (($k, $v) = each %attr) {
		$self->{$k} = $v;
	}
	return $self;
}

# clean up all (circular) references so that perl can do
# the real destroying
sub delete {
	%{$_[0]} = ();
}

#sub DESTROY {
#	say 'destroying ', $_[0];
#}

1;
