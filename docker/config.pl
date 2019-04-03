$cfg = {
	# methods configuration file to load
	methods => 'methods.pl',
	listen => [
		{
			# dislay name for this local endpoint
			name => 'default port',
			# default values:
			#address => '127.0.0.1',
			#port => 6551,
			# auth => ['all'],
		},
	],
	auth => {
		# authentication methods supported
		password => 'RPC::Switch::Auth::Passwd',
	},
	# per authentication method configuration
	'auth|password' => {
		pwfile => 'switch.passwd'
	},
};

