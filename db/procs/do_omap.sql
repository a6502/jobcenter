CREATE OR REPLACE FUNCTION jobcenter.do_omap(code text, args jsonb, env jsonb, vars jsonb, oargs jsonb)
 RETURNS jsonb
 LANGUAGE plperlu
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$

use strict;
use warnings;
#use plperl.on_init instead
#use lib '/home/wieger/src/jobcenter/lib';
use JSON::MaybeXS qw(from_json to_json);
use JobCenter::Safe;

my $safe = new JobCenter::Safe;

my ($code, $jargs, $jenv, $jvars, $joargs) = @_;

our %a = %{from_json($jargs // '{}')};
our %e = %{from_json($jenv // '{}')};
our %v = %{from_json($jvars // '{}')};
our %o = %{from_json($joargs // '{}')};

$safe->share(qw(%a %e %v %o &from_json &to_json));

$safe->reval($code, 1);

die "$@" if $@;

return to_json(\%v);

$function$
