package JobCenter::MojoClient::Job;
use Mojo::Base -base;

has [qw(cb job_id inargs listenstring tmr vtag wfname)];

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

sub _done {
	my ($self, $what) = @_;
	say "JobCenter::MojoClient::Job::_done got $what";
}

1;
