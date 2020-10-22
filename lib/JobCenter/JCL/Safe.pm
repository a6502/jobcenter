package JobCenter::JCL::Safe;

# this is running in a PostgreSQL PL/Perl interpreter

use strict;
use warnings;
use 5.10.0; # more modern goodies

# stdperl
use Exporter qw(import);
use Safe;

# cpan
use JSON::MaybeXS qw(to_json from_json);

# us
use JobCenter::JCL::Functions;

# things to share (but not all of them always)
our (%a, %e, %i, %o, %t, %v);
our $TRUE = JSON::MaybeXS::true;
our $FALSE = JSON::MaybeXS::false;
our $JCL;

BEGIN {
	my $object;
	$JCL = bless \$object, "JobCenter::JCL::Functions";
}

my @standardshares = qw(%a %e %v %t $FALSE $JCL $TRUE);

# (re-)export some things to make things easier in the actual plperl functions
our @EXPORT = qw(%a %e %i %o %t %v from_json to_json);

# stuff that we allow the safe box to do..
my @permits = qw(
	gmtime localtime padany ref refgen rv2gv time
	:base_core :base_loop :base_math :base_mem
);

sub new {
	my ($class, @extrashares) = @_ ;
	my $safe = new Safe;
	$safe->permit_only(@permits);
	$safe->share_from('JobCenter::JCL::Safe', [@standardshares, (@extrashares ? @extrashares : ())]);
	my $self = bless {
		safe => $safe,
	}, $class;
	return $self;
}

sub reval {
	my ($self, $code, $jargs, $jenv, $jvars) = @_;
	%a = %{from_json($jargs // '{}')};
	%e = %{from_json($jenv  // '{}')};
	%v = %{from_json($jvars // '{}')};
	%t = ();

	my $ret = $self->{safe}->reval($code, 1); # 1 means 'strict'
	die "$@" if $@;
	return $ret;
}

1;
