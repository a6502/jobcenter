package JobCenter::Api::Auth::ClientCert;
use Mojo::Base 'JobCenter::Api::Auth::Base';

use List::Util qw(any);

has [qw(cnfile)];

sub new {
	my $self = shift->SUPER::new();

	my ($cfg) = @_;

	my $cnfile = $cfg->{cnfile} or die "no cnfile";

	die "cnfile $cnfile does not exist" unless -r $cnfile;

	$self->{cnfile} = $cnfile;
	return $self;
}


sub authenticate {
	my ($self, $client, $who) = @_; # ignore token

	return (0, 'undef argument(s)') unless $client and $who;

	my $h = $client->stream->handle;

	return (0, 'no handle?') unless $h;

	my $cn = $h->peer_certificate('cn');

	return (0, 'no peer cn?') unless $cn;

	my @u;
	open my $fh, '<', $self->cnfile or return (0, 'cannot open cnfile');
	while (<$fh>) {
		chomp;
		my ($a, $b) = split /:/;
		if ($a eq $cn) {
			@u = split /,/, $b;
			last;
		}
	}
	close $fh;

	return (0, "cn $cn not found") unless @u;

	return (0, "user $who not allowed for cn $cn") unless any { $who eq $_ } @u;

        return (1, 'whoohoo');
}

1;
