package JobCenter::Api::Client;
use Mojo::Base 'Mojo::EventEmitter';
use Mojo::IOLoop;

use JSON::RPC2::TwoWay;
use MojoX::NetstringStream;

use Data::Dumper;

has [qw(actions api con from id ns ping reqauth rpc stream tmr who
	 workername worker_id)];

sub new {
	my $self = shift->SUPER::new();
	my ($api, $rpc, $stream, $id) = @_;
	#say 'new connection!';
	die 'no stream?' unless $stream and $stream->can('write');
	my $handle = $stream->handle;
	my $from = $handle->peerhost .':'. $handle->peerport;
	my $ns = MojoX::NetstringStream->new(
		stream => $stream,
		maxsize => 999999, # fixme: configurable?
	);
	my $con = $rpc->newconnection(
		owner => $self,
		write => sub { $ns->write(@_) },
	);
	$ns->on(chunk => sub {
		my ($ns, $chunk) = @_;
		# Process input chunk
		#print '    got chunk: ', Dumper(\$chunk);
		my @err = $con->handle($chunk);
		die join(' ', grep defined, @err) if @err;
		$ns->close if $err[0];
	});
	$ns->on(close => sub { $self->_on_close(@_) });
	$ns->on(nserr => sub {
		my ($ns, $msg) = @_;
		$api->log->error("$from ($self): $msg");
		# whut?
		#$self->rpc->_error($con, undef, -32010, $msg);
		$self->close;
	});

	$api->log->info("new connection $self from $from");

	$con->notify('greetings', {who =>'jcapi', version => '1.1'});
	
	$self->{actions} = {};
	$self->{con} = $con;
	$self->{from} = $from;
	$self->{id} = $id;
	$self->{ns} = $ns;
	$self->{ping} = 60; # fixme: configurable?
	$self->{rpc} = $rpc;
	$self->{stream} = $stream;
	return $self;
}

sub _on_close {
	my ($self, $ns) = @_;
	Mojo::IOLoop->remove($self->{tmr}) if $self->{tmr};
	$self->emit(close => $self);
	$self->con->close if $self->con;
	%$self = ();
}

sub close {
	my ($self) = @_;
	$self->stream->close_gracefully;
}

#sub DESTROY {
#	my $self = shift;
#	say 'destroying ', $self;
#}

1;
