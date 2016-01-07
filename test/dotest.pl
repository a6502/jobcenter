#!/usr/bin/perl

use strict;
use warnings;
use 5.10.0;

use FindBin;
use Test::More;
#use Time::Piece;

# JobCenter
use lib "$FindBin::Bin/../lib";
#use JobCenter::SimpleClient;
use_ok('JobCenter::SimpleClient');

our $vtag = 'unittest';
our $jcc = "$FindBin::Bin/../bin/jcc";
our $client;

exit main(@ARGV);

sub main {
	$client = JobCenter::SimpleClient->new(
		cfgpath => "$FindBin::Bin/../etc/jobcenter.conf",
		json => 0,
		debug => 1,
	);
	isa_ok($client, 'JobCenter::SimpleClient');

	ok(-x $jcc, 'found jcc and it is executable');

	my $test;
	#goto frop;

	$test='calltest';
	compile($test);
	call($test, { input => 1 }, { output => 4 });	

	$test='evaltest';
	compile($test);
	call($test, { i1 => 1, i2 => 2 }, { out => "1 + 2" });

	$test='iftest';
	compile($test);
	call($test, { input => 1   }, { output => 2  , whut => 'less than 10' });
	call($test, { input => 11  }, { output => 12 });
	call($test, { input => 111 }, { output => 112, whut => 'greater than 100' });

	$test='whiletest';
	compile($test);
	call($test, { input => 5 }, { output => 10 });

	$test='repeattest';
	compile($test);
	call($test, { input => 5 }, { output => 11 });

	$test='gototest';
	compile($test);
	call($test, { input => 5 }, { output => ' foo bar baz' });

	$test='casetest';
	compile($test);
	call($test, { input => 'foo' }, { output => 'got foo' });
	call($test, { input => 'bar' }, { output => 'got bar or baz' });
	call($test, { input => 'tla' }, { output => 'dunno what i got' });

	$test='trytest';
	compile($test);
	call($test, { i1 => 1, i2 => 2 }, { out => 0.5 });
	call($test, { i1 => 1, i2 => 0 }, { out => 0.123456789, whut => 'division by zero' });

	$test='raise_errortest2';
	compile($test);
	call($test, { in => 'foo' }, { error => { msg => "let's raise an error", class => 'normal' } });

	$test='raise_errortest';
	compile($test);
	call($test, { in => 'foo' }, { out => 'caught error!' });

	$test='sleeptest';
	compile($test);
	call($test, { in => 'foo' }, { out => 'got timeout' });

	$test='eventtest';
	compile($test);
	call($test, { in => 'foo' }, { out => 'got my1stevent' });

	$test='childjobtest';
	# we assume that we have 'calltest' available here
	compile($test);
	call($test, { input => 1 }, { output => 4 });	

	$test='childjoberrortest';
	# we assume that we have 'raise_errortest2' available here
	compile($test);
	call($test, { input => 1 }, { output => 'got childerror' });	

	#frop:
	$test='splittest';
	# we assume that we have 'calltest' available here
	compile($test);
	call($test, { input => 1 }, { output => '13 23 33' });	

	done_testing();
	return 0;
}

sub compile {
	my ($test) = @_;

	ok(my $res = `$jcc --tags $vtag $test.wf`, "compiled $test");
}

sub call {
	my ($test, $in, $out) = @_;

	local $@;
	my $res;
	eval { $res = $client->call($test, $in, $vtag) }; 
	if ($@) {
		fail("called $test");
		diag($@);
		return;
	}
	pass("called $test");
	ok($res && %$res, 'got a hashref');
	is_deeply($res, $out, 'with the expected result');
}


