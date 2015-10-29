CREATE OR REPLACE FUNCTION jobcenter.dingsbums(args jsonb, vars jsonb)
 RETURNS jsonb
 LANGUAGE plperlu
AS $function$

use JSON::MaybeXS;
use Safe;
my ($jargs, $jvars) = @_;

my $calc = new Safe;
$calc->permit_only(qw(gmtime localtime padany rv2gv time :base_core :base_loop :base_math :base_mem));

our %a = %{decode_json($jargs)};
our %v = %{decode_json($jvars)};
our %o = ();
$calc->share(qw(%a %v %o));

$calc->reval(q|
	$o{foo} = $a{bar} + $v{baz};
	$o{bla} = "bloep";
|, 1);

elog(NOTICE, '$@: ' . $@) if $@;
#elog(NOTICE, 'v: ' . encode_json(\%v));
elog(NOTICE, 'o: ' . encode_json(\%o));

return encode_json(\%o);

$function$
