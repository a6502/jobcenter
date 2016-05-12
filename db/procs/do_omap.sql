CREATE OR REPLACE FUNCTION jobcenter.do_omap(code text, vars jsonb, oargs jsonb)
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

my ($code, $jvars, $joargs) = @_;

our %v = %{from_json($jvars // '{}')};
our %o = %{from_json($joargs // '{}')};

$safe->share(qw(%v %o &from_json &to_json));

$safe->reval($code, 1);

die "$@" if $@;

return to_json(\%v);

$function$
