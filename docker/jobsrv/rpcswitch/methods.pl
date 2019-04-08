# method configuration
# this gets reloaded on a sighup

# single level namespace mapping
$methods = {
	#namespace
	'foo' => {
		# call bar.square for foo.power
		'power' => 'bar.square',
		# call bar.add for foo.add
		'add' => 'bar.',
		'div' => { # more elaborate method details
			# backend
			b => 'bar.',
			# contact
			c => 'you@example.com',
			# description
			d => 'divides dividend by divisor',
		},
	},
};

$acl = {
	# acl => [+otheracl, user]
	'addbar' => ['+bar', 'deArbeider'],
	'bar' => [qw( theEmployee derArbeitnehmer )],
	'klant' => [qw( deKlant theCustomer )],
	'prov' => [qw( prov )],
	# everyone is in acl public
	'public' => '*',
};

# which acls are allowed to call which methods
$method2acl = {
	# namespace.method => acl
	'foo.div' => ['klant','prov'],
	'foo.*'  => 'public',
};

# which acls are allowed to announce which methods
$backend2acl = {
	# namespace.method => acl
	'bar.add' => 'addbar',
	'bar.*' => 'bar',
};

# which backend methods require filtering of which field
$backendfilter = {
	#'bar.square' => 'foo',
};
