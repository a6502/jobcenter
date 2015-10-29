CREATE OR REPLACE FUNCTION jobcenter.do_branchcasecode(code text, args jsonb, vars jsonb)
 RETURNS boolean
 LANGUAGE plperlu
AS $function$

use strict;
use warnings;
use lib '/home/wieger/src/jobcenter/lib';
use JSON::MaybeXS;
use JobCenter::Safe;

my $safe = new JobCenter::Safe;

my ($code, $jargs, $jvars) = @_;

our %a = %{decode_json($jargs // '{}')};
our %v = %{decode_json($jvars // '{}')};

$safe->share(qw(%a %v %i));

my $res = $safe->reval($code, 1);

die "$@" if $@;

#return !!$res; # force boolean context
return $res ? 1 : 0;

$function$
