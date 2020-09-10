package JobCenter::Safe;

use strict;
use warnings;

use Safe;

our @permits = qw(
	gmtime localtime padany ref refgen rv2gv time
	:base_core :base_loop :base_math :base_mem
);

sub new {
	my $class = shift;
	my $safe = new Safe;
	$safe->permit_only(@permits);
	$safe->share_from('JobCenter::Safe', ['&Dumper']);
	my $self = bless {
		safe => $safe,
	}, $class;
	return $self;
}

sub reval {
	my ($self, $code) = @_;
	my $ret = $self->{safe}->reval($code, 1);
	die "$@" if $@;
	return $ret;
}

sub share {
	my ($self, @vars) = @_;
	$self->{safe}->share_from(scalar(caller), \@vars);
}

1;
