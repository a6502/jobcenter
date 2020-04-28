package JobCenter::Util;

use strict;
use warnings;

our @EXPORT_OK = qw(
	check_pid daemonize ensure_pid_file hdiff rm_ref_from_arrayref
	slurp
);
our %EXPORT_TAGS = ('daemon' => [qw(check_pid daemonize ensure_pid_file)]);

use parent qw(Exporter);
use Carp qw(croak);
use POSIX qw();
use Scalar::Util qw(refaddr);

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

# copied from Mojo::Util v6.66 because newer Mojo's deprecate this function
sub slurp {
	my $path = shift;

	open my $file, '<', $path or croak qq{Can't open file "$path": $!};
	my $ret = my $content = '';
	while ($ret = $file->sysread(my $buffer, 131072, 0)) { $content .= $buffer }
	croak qq{Can't read from file "$path": $!} unless defined $ret;

	return $content;
}

sub hdiff {
	my ($old, $new) = @_;
	my %add;
	my %rem;

	for (keys %$old) {
		$rem{$_} = $old->{$_} unless
			exists $new->{$_} and $old->{$_} eq $new->{$_};
	}

	for (keys %$new) {
		$add{$_} = $new->{$_} unless
			exists $old->{$_} and $old->{$_} eq $new->{$_};
	}

	return (\%add, \%rem);
}

sub rm_ref_from_arrayref {
	# arrayref, item to remove
	my ($l, $i) = @_;
	my $addr = refaddr $i;
	splice @$l, $_, 1 for grep(refaddr $$l[$_] == $addr, 0..$#$l);
}

1;
