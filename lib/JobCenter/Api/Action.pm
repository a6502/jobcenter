package JobCenter::Api::Action;
use Mojo::Base -base;

#
# an action as announced at the low level postgresql api
#

has [qw(actionname listenstring workeractions)];

sub find_worker {
	my ($self, $workers) = @_;
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
