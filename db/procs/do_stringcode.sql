CREATE OR REPLACE FUNCTION jobcenter.do_stringcode(code text, args jsonb, env jsonb, vars jsonb, OUT switch text, OUT newvars jsonb)
 RETURNS record
 LANGUAGE plperl
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$

use strict;
use warnings;
use feature 'state';

use JobCenter::JCL::Safe;

state $safe = new JobCenter::JCL::Safe();

my $res = $safe->reval(@_);

return {switch => "$res", newvars => to_json(\%v)};

$function$
