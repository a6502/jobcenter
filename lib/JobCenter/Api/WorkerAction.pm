package JobCenter::Api::WorkerAction;
use Mojo::Base -base;

use JobCenter::Util qw(rm_ref_from_arrayref);
use List::Util qw(any);
use Scalar::Util qw(refaddr);

#
# an action that a worker (aka client) announced to us
#

has [qw(action client filter slotgroup)];

sub reset_pending {
	rm_ref_from_arrayref($_[0]->{slotgroup}->{pending}, $_[0]);
        return $_[0];
}

sub set_pending {
	my ($self) = @_;
	my $l = $self->{slotgroup}->{pending} //= [];
	my $addr = refaddr $self;
	unless (@$l and any { refaddr $_ == $addr } @$l) {
		push @$l, $self;
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
