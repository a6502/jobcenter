package JobCenter::Adm;

use Mojo::Base -base;

# mojo
use Mojo::Loader qw(load_class);
use Mojo::Log;
use Mojo::Pg;
use Mojo::Util qw(camelize);

# standard perl
#use Data::Dumper;
use File::Basename;

# cpan
use Config::Tiny;
use JobCenter::Client::Mojo 0.31; # for get_api_status


has [qw(cfg cfgpath client debug log)];

has client => sub {
	my ($self) = @_;

	my %args = (
		who => $self->{cfg}{admin}{apiuser},
		token => $self->{cfg}{admin}{apitoken},
		debug => $self->debug,
		log => $self->log,
		( $self->{cfg}{admin}{apimethod} ? (method => $self->{cfg}{admin}{apimethod}) : ()),
		( $self->{cfg}{admin}{apiaddress} ? (address => $self->{cfg}{admin}{apiaddress}) : ()),
		( $self->{cfg}{admin}{apiport} ? (port => $self->{cfg}{admin}{apiport}) : ()),
	) or die 'no jobcenter api client?';

	if ($self->{cfg}{admin}{apiclient_key}) {
		$args{tls} = 1;
		$args{tls_key} = $self->{cfg}{admin}{apiclient_key};
		$args{tls_cert} = $self->{cfg}{admin}{apiclient_cert};
		$args{tls_ca} = $self->{cfg}{admin}{apiclient_ca} if $self->{cfg}{admin}{apiclient_ca};
	}

	#print 'using args ', Dumper(\%args);

	my $client = JobCenter::Client::Mojo->new(%args)
		or die 'no jobcenter api client?';

	return $client;
};

has pg => sub { 
	my ($self) = @_;
	
	$ENV{'PGAPPNAME'} = fileparse($0) . " [$$]";
	my $cfg = $self->cfg;
	my $pg = Mojo::Pg->new(
		'postgresql://'
		. $cfg->{admin}->{user}
		. ':' . $cfg->{admin}->{pass}
		. '@' . ( $cfg->{pg}->{host} // '' )
		. ( ($cfg->{pg}->{port}) ? ':' . $cfg->{pg}->{port} : '' )
		. '/' . $cfg->{pg}->{db}
	);
	#$pg->max_connections(5); # how much? configurable?
	$pg->on(connection => sub { 
		my ($e, $dbh) = @_;
		$self->log->debug("pg: new connection: $dbh");
	});

	return $pg;
};


sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new();

	$self->{cfgpath} = $args{cfgpath} or die 'no cfgpath?';
	my $cfg = Config::Tiny->read($self->cfgpath);
	die 'failed to read config ' . $self->cfgpath . ': ' . Config::Tiny->errstr unless $cfg;
	$self->{cfg} = $cfg;

	my $debug = $self->{debug} = $args{debug} // 0; # or 1?
	$self->{log} = $args{log} // Mojo::Log->new(level => ($debug) ? 'debug' : 'info');

	return $self;
}

sub do_cmd {
	my ($self, $cmd) = (shift, shift);

	$cmd = 'help' unless $cmd;

	my $admcmd = $self->load_cmd($cmd);
	
	unless ($admcmd) {
		say "no such command $cmd, try 'jcadm help'";
		return 0;
	}
		
	return $admcmd->do_cmd(@_);
}

sub load_cmd {
	my ($self, $cmd) = @_;

	my $class = 'JobCenter::Adm::' . camelize($cmd);

	if (my $e = load_class($class)) {
		die "Exception: $e" if ref $e;
		return;
	}

	my $admcmd = $class->new(adm => $self)
		or die "Could not instantiate $class";

	return $admcmd;
}

1;
