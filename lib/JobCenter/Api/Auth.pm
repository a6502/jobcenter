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
		$methods->{$m} = $a;
	}

	$self->{methods} = $methods;
	return $self;
}


sub authenticate {
	my ($self, $who, $method, $token, $cb) = @_;

	$cb->(0, 'undef argument(s)') unless $who and $method and $token;
	
	my $adapter = $self->{methods}->{$method} or $cb->(0, 'no such method');

	my ($res, $msg) = $adapter->authenticate($who, $token, $cb);
	
	$cb->($res, $msg) if (defined $res);
}

1;
