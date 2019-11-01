package JobCenter::JCC::Receiver;
use 5.10.0;
use Pegex::Base;
extends 'Pegex::Receiver';

use Data::Dumper;
use List::Util qw( none );

has labels => ();

#
# if the [perl[ syntax is used we get 2 matches, discard the first one 
# (which contains the delimiting string) and always wrap
#
sub got_perl_block {
	my ($self, $got) = @_;
	shift @$got if scalar @$got > 1;
	return {$self->{parser}{rule} => $$got[0]};
}

#
# store found labels in a central place
#
sub got_label {
	my ($self, $got) = @_;
	push @{$self->{labels}}, $$got[0];
	return {$self->{parser}{rule} => $$got[0]};
}

#
# unnest and wrap
#
sub got_to_unnest {
	my ($self, $got) = @_;
	return $got unless defined $got;

	$got = $$got[0]
		while ref $got eq 'ARRAY' and scalar @$got == 1;

	return {
		$self->{parser}{rule} => $got,
		} if $self->{parser}{parent}{-wrap};
	return $got;
}

*got_action_type = \&got_to_unnest;
*got_goto = \&got_to_unnest;

#
# flatten to a single level
# wrap if wanted
#
sub got_to_flatten {
	my ($self, $got) = @_;
	#print 'got_to_flatten ', $self->{parser}{rule}, ' ', Dumper($got);
	$self->flatten($got) if ref $got eq 'ARRAY';
	return {
		$self->{parser}{rule} => $got,
		} if $self->{parser}{parent}{-wrap};
	return $got;
}

*got_block = \&got_to_flatten;
*got_case_label = \&got_to_flatten;
*got_config = \&got_to_flatten;
*got_condition = \&got_to_flatten;
*got_do = \&got_to_flatten;
*got_env = \&got_to_flatten;
*got_else = \&got_to_flatten;
*got_elses = \&got_to_flatten;
*got_eval = \&got_to_flatten;
*got_funcarg = \&got_to_flatten;
*got_funcname = \&got_to_flatten;
*got_imap = \&got_to_flatten;
*got_in = \&got_to_flatten;
*got_interface_namelist = \&got_to_flatten;
*got_iospec = \&got_to_flatten;
*got_let = \&got_to_flatten;
*got_lhs = \&got_to_flatten;
*got_locks = \&got_to_flatten;
*got_lockspec = \&got_to_flatten;
*got_magic_assignment = \&got_to_flatten;
*got_map_using = \&got_to_flatten;
*got_omap = \&got_to_flatten;
*got_out = \&got_to_flatten;
*got_parented = \&got_to_flatten;
*got_raise_error = \&got_to_flatten;
*got_raise_event = \&got_to_flatten;
*got_rhs = \&got_to_flatten;
*got_rhs_body = \&got_to_flatten;
*got_role = \&got_to_flatten;
*got_sleep = \&got_to_flatten;
*got_split = \&got_to_flatten;
*got_subscribe = \&got_to_flatten;
*got_then = \&got_to_flatten;
*got_unsubscribe = \&got_to_flatten;
*got_variable = \&got_to_flatten;
*got_varpart_array = \&got_to_flatten;
*got_wfenv = \&got_to_flatten;
*got_wfomap = \&got_to_flatten;

#
# flatten, hashify and maybe wrap
#
sub got_to_hashify {
	my ($self, $got) = @_;
	return () unless defined $got;
	#print 'gotrule ', $self->{parser}{rule}, ' ', Dumper($got);
	$self->flatten($got) if ref $got eq 'ARRAY';

	$got = $self->hashify($got)
		if ref $got eq 'ARRAY';

	return {$self->{parser}{rule} => $got}
		if $self->{parser}{parent}{-wrap};
	return $got;
}

*got_action = \&got_to_hashify;
*got_assignment = \&got_to_hashify;
*got_assert = \&got_to_hashify;
*got_call = \&got_to_hashify;
*got_callflow = \&got_to_hashify;
*got_case = \&got_to_hashify;
*got_detachflow = \&got_to_hashify;
*got_elsif = \&got_to_hashify;
*got_event = \&got_to_hashify;
*got_functioncall = \&got_to_hashify;
*got_if = \&got_to_hashify;
*got_interface = \&got_to_hashify;
*got_interface_call = \&got_to_hashify;
*got_lock = \&got_to_hashify;
*got_map = \&got_to_hashify;
*got_repeat = \&got_to_hashify;
*got_try = \&got_to_hashify;
*got_unlock = \&got_to_hashify;
*got_wait_for_event = \&got_to_hashify;
*got_wait_for_lock = \&got_to_hashify;
*got_when = \&got_to_hashify;
*got_while = \&got_to_hashify;
*got_workflow = \&got_to_hashify;

#
# only wrap if wanted
#
sub gotrule {
	my ($self, $got) = @_;
	return () unless defined $got;
	#print 'gotrule ', $self->{parser}{rule}, ' ', Dumper($got);

	return {$self->{parser}{rule} => $got}
		if $self->{parser}{parent}{-wrap};
	return $got;
}

sub final {
	my $self = shift;
	return(shift) if @_;
	#return [];
	die 'nothing parsed?';
}

# group wrapped matches together
sub hashify {
	my ($self, $got) = @_;
	# checks if all array elements are 1 element hashes
	return $got if none { ref $_ eq 'HASH' } @$got;
	#print 'hashify: ', Dumper($got);
	for my $g (@$got) {
		$g = $self->hashify($g) if ref $g eq 'ARRAY';
		return $got if ref $g ne 'HASH';
	}
	my %newgot;
	for (@$got) {
		while (my ($k, $v) = each %$_) {
			if ($newgot{$k}) {
				if (ref $newgot{$k} eq 'ARRAY') {
					push @{$newgot{$k}}, $v;
				} else {
					$newgot{$k} = [ $newgot{$k}, $v ];
				}
			} else {
				$newgot{$k} = $v;
			}
		}
	}
	#print 'after hashify: ', Dumper(\%newgot);
	return \%newgot;
}


1;

