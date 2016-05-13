package JobCenter::Util;

use strict;
use warnings;

our @EXPORT = qw(check_pid daemonize ensure_pid_file);

use parent qw(Exporter);

# copied from Mojo::Server
sub daemonize {
	# Fork and kill parent
	die "Can't fork: $!" unless defined(my $pid = fork);
	exit 0 if $pid;
	POSIX::setsid or die "Can't start a new session: $!";

	# Close filehandles
	open STDIN,  '</dev/null';
	open STDOUT, '>/dev/null';
	open STDERR, '>&STDOUT';
}

# copied from Mojo::Server::Prefork
sub check_pid {
	my $file = shift;
	return undef unless open my $handle, '<', $file;
	my $pid = <$handle>;
	chomp $pid;
	close $handle;

	# Running
	return $pid if $pid && kill 0, $pid;

	# Not running
	unlink $file if -w $file;
	return undef;
}

# copied from Mojo::Server::Prefork
sub ensure_pid_file {
	my ($file, $log) = @_;

	# Check if PID file already exists
	return if -e $file;

	# Create PID file
	$log->error(qq{Can't create process id file "$file": $!})
	and die qq{Can't create process id file "$file": $!}
	    	unless open my $handle, '>', $file;
	$log->info(qq{Creating process id file "$file"});
	chmod 0644, $handle;
	print $handle $$;
	close $handle;
}

1;
