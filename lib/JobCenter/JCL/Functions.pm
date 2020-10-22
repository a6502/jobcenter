package JobCenter::JCL::Functions;

# This is the implementation of  the functions that the JobCenter Language
# has available. This is executed by a PostgreSQL PL/Perl interpreater

use strict;
use warnings;
use 5.10.0; # more modern goodies

# std perl
use Digest::MD5 qw();
use MIME::Base64 qw();

# cpan
use JSON::MaybeXS qw();

our $JSON = JSON::MaybeXS->new(utf8 => 0)->canonical;

sub encode_json {
	return $JSON->encode($_[1]);
}

sub decode_json {
	return $JSON->decode($_[1]);
}

sub decode_base64 {
	return MIME::Base64::decode_base64($_[1]);
}

sub encode_base64 {
	return MIME::Base64::encode_base64($_[1], '');
}

sub md5_base64 {
	return Digest::MD5::md5_base64($_[1]);
}

sub md5_hex {
	return Digest::MD5::md5_hex($_[1]);
}

sub list {
	my $r = $_[1];
	my $ref = ref $r;
	if ($ref eq 'ARRAY') {
		return @$r;
	} elsif ($ref eq 'HASH') {
		return %$r;
	} elsif ($ref eq 'SCALAR') {
		return $$r;
	} else {
		die "not a reference\n";
	}
}

sub keys {
	my $r = $_[1];
	if (ref $r eq 'HASH') {
		return [ keys %$r ];
	} else {
		die "not an object\n";
	}
}

sub values {
	my $r = $_[1];
	if (ref $r eq 'HASH') {
		return [ values %$r ];
	} else {
		die "not an object\n";
	}
}

# aliases

*to_json    = \&encode_json;
*from_json  = \&decode_json;
*tojson     = \&encode_json;
*fromjson   = \&decode_json;
*b64decode  = \&decode_base64;
*b64encode  = \&encode_base64;
*md5        = \&md5_hex;
*md5b64     = \&md5_base64;

1;
