CREATE OR REPLACE FUNCTION jobcenter.do_omap(code text, vars jsonb, oargs jsonb)
 RETURNS jsonb
 LANGUAGE plperlu
AS $function$

use strict;
use warnings;
#use plperl.on_init instead
#use lib '/home/wieger/src/jobcenter/lib';
use JSON::MaybeXS;
use JobCenter::Safe;

my $safe = new JobCenter::Safe;

my ($code, $jvars, $joargs) = @_;

our %v = %{decode_json($jvars // '{}')};
our %o = %{decode_json($joargs // '{}')};

$safe->share(qw(%v %o &decode_json &encode_json));

$safe->reval($code, 1);

die "$@" if $@;

return encode_json(\%v);

$function$
