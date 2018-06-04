package JobCenter::MojoClient::Job;
use Mojo::Base -base;

has [qw(cb job_id inargs lcb listenstring tmr vtag wfname)];

sub new {
	my $self = shift->SUPER::new(@_);
	return $self;
	$self->on(done => \&_done);
}

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
	my $self = shift;
	%$self = ();
}


sub _done {
	my ($self, $what) = @_;
	say "JobCenter::MojoClient::Job::_done got $what";
}

1;
