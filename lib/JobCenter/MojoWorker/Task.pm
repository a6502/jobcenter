package JobCenter::MojoWorker::Task;
use Mojo::Base -base;

has [qw(actionname cookie job_id inarg workername)];

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
	say "JobCenter::ClientTask::_done got $what";
}

1;
