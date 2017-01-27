package JobCenter::Api::Auth;
use Mojo::Base 'Mojo::EventEmitter';

use Module::Load;

has [qw(methods)];

sub new {
	my $self = shift->SUPER::new();

	my ($cfg, $section) = @_;

	my $methods = $cfg->{$section};
	
	for my $m (keys %$methods) {
		my $mod = $methods->{$m};
		load $mod;
		my $a = $mod->new($cfg->{"$section|$m"});
		die "could not create authentication module object $mod" unless $a;
		$methods->{$m} = $a;
	}

	$self->{methods} = $methods;
	return $self;
}


sub authenticate {
	my ($self, $method, $client, $who, $token, $cb) = @_;

	$cb->(0, 'undef argument(s)') unless $who and $method and $token;
	
	my $adapter = $self->{methods}->{$method};
	unless ($adapter) {
		$cb->(0, "no such authentication method $method");
		return;
	}

	my ($res, $msg) = $adapter->authenticate($client, $who, $token, $cb);
	
	$cb->($res, $msg) if defined $res;
}

1;
