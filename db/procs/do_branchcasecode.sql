CREATE OR REPLACE FUNCTION jobcenter.do_branchcasecode(code text, args jsonb, env jsonb, vars jsonb)
 RETURNS boolean
 LANGUAGE plperlu
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$

use strict;
use warnings;
#use plperl.on_init instead
#use lib '/home/wieger/src/jobcenter/lib';
use JSON::MaybeXS;
use JobCenter::Safe;

my $safe = new JobCenter::Safe;

my ($code, $jargs, $jenv, $jvars) = @_;

our %a = %{decode_json($jargs // '{}')};
our %e = %{decode_json($jenv // '{}')};
our %v = %{decode_json($jvars // '{}')};

$safe->share(qw(%a %e %v));

my $res = $safe->reval($code, 1);

die "$@" if $@;

#return !!$res; # force boolean context
return $res ? 1 : 0;

$function$
