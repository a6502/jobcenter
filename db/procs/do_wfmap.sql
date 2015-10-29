CREATE OR REPLACE FUNCTION jobcenter.do_wfmap(code text, vars jsonb)
 RETURNS jsonb
 LANGUAGE plperlu
AS $function$

use strict;
use warnings;
use lib '/home/wieger/src/jobcenter/lib';
use JSON::MaybeXS;
use JobCenter::Safe;

my $safe = new JobCenter::Safe;

my ($code, $jvars) = @_;

our %v = %{decode_json($jvars // '{}')};
our %o = ();

$safe->share(qw(%v %o &decode_json &encode_json));

$safe->reval($code, 1);

die "$@" if $@;

return encode_json(\%o);

$function$
