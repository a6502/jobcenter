CREATE OR REPLACE FUNCTION jobcenter.do_eval(code text, args jsonb, vars jsonb)
 RETURNS jsonb
 LANGUAGE plperlu
AS $function$

use strict;
use warnings;

# put this in the plperl.on_init instead
#use lib '/home/wieger/src/jobcenter/lib';
use JSON::MaybeXS;
use JobCenter::Safe;

my $safe = new JobCenter::Safe;

my ($code, $jargs, $jvars) = @_;

our %a = %{decode_json($jargs // '{}')};
our %v = %{decode_json($jvars // '{}')};

$safe->share(qw(%a %v &decode_json &encode_json));

$safe->reval($code, 1);

die "$@" if $@;

return encode_json(\%v);

$function$
