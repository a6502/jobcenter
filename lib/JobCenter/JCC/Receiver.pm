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
# flatten down to 1 array
#
sub got_to_unwrap {
	my ($self, $got) = @_;

	$self->flatten($got) if ref $got eq 'ARRAY';
	$got = [ $got ] unless ref $got eq 'ARRAY';

	return {$self->{parser}{rule} => $got}
		if $self->{parser}{parent}{-wrap};
	return $got;
}

*got_block = \&got_to_unwrap;
*got_catch_block = \&got_to_unwrap;
*got_do = \&got_to_unwrap;
*got_else = \&got_to_unwrap;
*got_split = \&got_to_unwrap;
*got_then = \&got_to_unwrap;
*got_try_block = \&got_to_unwrap;

#
# don't mangle
#
sub got_to_keep_order {
	my ($self, $got) = @_;
	#print 'got_to_keep_order1 ', $self->{parser}{rule}, ' ', Dumper($got);
	return {$self->{parser}{rule} => $got}
		if $self->{parser}{parent}{-wrap};
	return $got;
}

*got_imap = \&got_to_keep_order;
*got_omap = \&got_to_keep_order;
*got_native_assignments = \&got_to_keep_order;
*got_inout = \&got_to_keep_order;
*got_case_expression = \&got_to_keep_order;

#
# flatten lhs,, iospec. etc. to a single level
#
sub got_to_flatten {
	my ($self, $got) = @_;
	#print 'got_to_flatten ', $self->{parser}{rule}, ' ', Dumper($got);
	$self->flatten($got) if ref $got eq 'ARRAY';
	return {$self->{parser}{rule} => $got}
		if $self->{parser}{parent}{-wrap};
	return $got;
}

*got_case_label = \&got_to_flatten;
*got_filter =\&got_to_flatten;
*got_iospec =\&got_to_flatten;
*got_lockspec =\&got_to_flatten;
*got_parented = \&got_to_flatten;
*got_lhs = \&got_to_flatten;
*got_rhs = \&got_to_flatten;
*got_funcarg = \&got_to_flatten;
*got_role = \&got_to_flatten;
*got_term = \&got_to_flatten;
*got_variable = \&got_to_flatten;

#
# default behaviour: flatten with care, hashify when possible
#
sub gotrule {
	my ($self, $got) = @_;
	return () unless $got;
	#print 'gotrule ', $self->{parser}{rule}, ' ', Dumper($got);
	$got = $$got[0]
		if ref $got eq 'ARRAY' and scalar @$got == 1;

	$got = $self->hashify($got)
		if ref $got eq 'ARRAY';
	return {$self->{parser}{rule} => $got}
		if $self->{parser}{parent}{-wrap};
	return $got;
}

sub final {
	my $self = shift;
	return(shift) if @_;
	return [];
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

