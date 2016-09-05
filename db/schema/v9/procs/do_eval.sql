CREATE OR REPLACE FUNCTION jobcenter.do_eval(code text, args jsonb, env jsonb, vars jsonb)
 RETURNS jsonb
 LANGUAGE plperl
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$

use strict;
use warnings;

# put this in the plperl.on_init instead
#use lib '/home/wieger/src/jobcenter/lib';
use JSON::MaybeXS qw(from_json to_json);
use JobCenter::Safe;

my $safe = new JobCenter::Safe;

my ($code, $jargs, $jenv, $jvars) = @_;

our %a = %{from_json($jargs // '{}')};
our %e = %{from_json($jenv // '{}')};
our %v = %{from_json($jvars // '{}')};
our %t = ();

$safe->share(qw(%a %e %v %t &from_json &to_json));

$safe->reval($code, 1);

die "$@" if $@;

return to_json(\%v);

$function$
