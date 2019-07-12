package JobCenter::Api::SlotGroup;
use Mojo::Base -base;

has [qw(name slots used)];

#sub DESTROY {
#	my $self = shift;
#	say 'destroying ', $self;
#}

1;
