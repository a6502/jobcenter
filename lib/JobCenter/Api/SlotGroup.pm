package JobCenter::Api::SlotGroup;
use Mojo::Base -base;

has [qw(name slots pending)];

# let's assume things get initialized properly from JsonRPC.pm

sub free {
	$_[0]->{used} -= $_[1] if defined $_[1] and $_[0]->{used} > 0;
	return ($_[0]->{slots} - $_[0]->{used});
}

sub used {
	$_[0]->{used} += $_[1] if defined $_[1] and $_[0]->{used} >= 0;
	return $_[0]->{used};
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
