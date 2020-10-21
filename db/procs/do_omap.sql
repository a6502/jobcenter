CREATE OR REPLACE FUNCTION jobcenter.do_omap(code text, args jsonb, env jsonb, vars jsonb, oargs jsonb)
 RETURNS jsonb
 LANGUAGE plperl
 SECURITY DEFINER
 SET search_path TO jobcenter, pg_catalog, pg_temp
AS $function$

use strict;
use warnings;
use feature 'state';

use JobCenter::JCL::Safe;

state $safe = new JobCenter::JCL::Safe('%o');

%o = %{from_json(pop() // '{}')};

$safe->reval(@_);

return to_json(\%v);

$function$
