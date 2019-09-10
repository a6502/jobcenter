package JobCenter::Api::Server;
use Mojo::Base -base;

use Data::Dumper;
use Scalar::Util qw(refaddr);
use JobCenter::Api::Client;

has [qw(api authmethods localname server)];

sub new {
	my $self = shift->SUPER::new();
	my ($api, $name, $lc) = @_;

	my $serveropts = { port => ( $lc->{port} // 6522 ) };
	$serveropts->{address} = $lc->{address} if $lc->{address};
	if ($lc->{tls_key}) {
		$serveropts->{tls} = 1;
		$serveropts->{tls_key} = $lc->{tls_key};
		$serveropts->{tls_cert} = $lc->{tls_cert};
	}
	if ($lc->{tls_ca}) {
		$serveropts->{tls_ca} = $lc->{tls_ca};
	}
	if ($lc->{tls_verify}) {
		$serveropts->{tls_verify} = 0x03;
	}

	my $am = $api->auth->methods;
	if ($lc->{auth}) {
		my %authmethods;
		for (split /,/, $lc->{auth}) {
			die "Unkown auth method $_" unless $authmethods{$_} = $am->{$_};
		}
		$self->{authmethods} = \%authmethods;
	} else {
		$self->{authmethods} = $am;
	}

	#$api->log->debug("$name serveropts " . Dumper($serveropts));

	my $server = Mojo::IOLoop->server(
		$serveropts => sub {
			my ($loop, $stream, $id) = @_;
			my $client = JobCenter::Api::Client->new($self, $stream, $id);
			$client->on(close => sub { $api->_disconnect($client) });
			$api->clients->{refaddr($client)} = $client;
		}
	) or die 'no server?';

	$self->{localname} = $name;
	$self->{server} = $server;
	$self->{api} = $api;

	return $self;
}


#sub DESTROY {
#	my $self = shift;
#	say 'destroying ', $self;
#}

1;
