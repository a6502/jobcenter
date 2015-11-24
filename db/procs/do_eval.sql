CREATE OR REPLACE FUNCTION jobcenter.do_eval(code text, args jsonb, env jsonb, vars jsonb)
 RETURNS jsonb
 LANGUAGE plperlu
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$

use strict;
use warnings;

# put this in the plperl.on_init instead
#use lib '/home/wieger/src/jobcenter/lib';
use JSON::MaybeXS;
use JobCenter::Safe;

my $safe = new JobCenter::Safe;

my ($code, $jargs, $jenv, $jvars) = @_;

our %a = %{decode_json($jargs // '{}')};
our %e = %{decode_json($jenv // '{}')};
our %v = %{decode_json($jvars // '{}')};

$safe->share(qw(%a %e %v &decode_json &encode_json));

$safe->reval($code, 1);

die "$@" if $@;

return encode_json(\%v);

$function$
