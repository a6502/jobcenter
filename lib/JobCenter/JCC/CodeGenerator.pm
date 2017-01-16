package JobCenter::JCC::CodeGenerator;

# mojo
use Mojo::Base -base;
use Mojo::JSON qw(from_json to_json true false);
use Mojo::Util qw(quote);

# stdperl
use Carp qw(croak);
use Data::Dumper;
use List::Util qw( any );
#use Scalar::Util qw(blessed);

has [qw(db fixup labels locks oetid tags wfid)];

# perl block types
use constant {
	IMAP => 'imap',
	OMAP => 'omap',
	WFOMAP => 'wfomap',
	STRING => 'string',
	BOOL => 'bool',
};

# task types
use constant {
	T_START => 0,
	T_END => -1,
	T_NO_OP => -2,
	T_EVAL => -3,
	T_BRANCH => -4,
	T_SWITCH => -5,
	T_REAP_CHILD => -6,
	T_SUBSCRIBE => -7,
	T_UNSUBSCRIBE => -8,
	T_WAIT_FOR_EVENT => -9,
	T_RAISE_ERROR => -10,
	T_RAISE_EVENT => -11,
	T_WAIT_FOR_CHILDREN => -12,
	T_LOCK => -13,
	T_UNLOCK => -14,
};

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new();

	my $db = $args{db} or croak 'no db?';
	my $debug = $args{debug} // 1; # or 1?
	$self->{db} = $db;	# db connection to use
	$self->{debug} = $debug;

	return $self;
}

sub generate {
	my ($self, %args) = @_;

	croak 'no wfast?' unless $args{wfast};

	my ($what, $wf) = $self->get_type($args{wfast});
	croak "don't know how to generate $what" unless $what eq 'action' or $what eq 'workflow';
	if ($what eq 'workflow') {
		$self->generate_workflow(%args);
	} else {
		$self->generate_action(%args);
	}
}

sub generate_workflow {
	my ($self, %args) = @_;

	my $wf = $args{wfast}->{workflow};
	my $labels = $args{labels} // [];	
	my $tags = $args{tags};
	
	# reset codegenerator
	$self->{wfid} = undef;  # workflow_id
	$self->{tags} = $tags;	# version tags
	$self->{oetid} = undef; # current on_error_task_id
	$self->{locks} = {};	# locks declared in the locks section
	$self->{labels} = { map { $_ => undef } @$labels }; # labels to be filled with task_ids
	$self->{fixup} = [];	# list of tasks that need the next_task set
				# format: list of task_id, target label

	# add the magic end label
	$self->{labels}->{'!!the end!!'} = undef;

	say "\nbegin";
	my $tx  = $self->db->begin;

	my $version = 1;
	# find out if a version alreay exists, if so increase version
	# FIXME: race condition when multiples jcc's compile the same wf at the same time..
	{
		my $res = $self->db->dollar_only->query(
			q|select version from actions where name = $1 and type = 'workflow' order by version desc limit 1|, 
			$wf->{workflow_name}
		)->array;
		#print 'res: ', Dumper($res);
		if ( $res and @$res and @$res[0] >= 0 ) {
			$version = @$res[0] + 1;
		}
	}
	say 'version: ', $version;

	my $wfenv = to_json({ map { $$_[0] => $$_[1] } @{$wf->{limits}} });
	say 'wfenv ', $wfenv;
	$wfenv = undef if $wfenv and ($wfenv eq 'null' or $wfenv eq '{}');

	my $wfid = $self->qs(
		q|insert into actions (name, type, version, wfmapcode, wfenv) values ($1, 'workflow', $2, $3, $4) returning action_id|, 
		$wf->{workflow_name}, $version, $self->make_perl($wf->{wfomap}, WFOMAP), $wfenv
	);
	$self->{wfid} = $wfid;
	say "wfid: $wfid";

	# use a fake returning clause to we can reuse our qs function	
	for my $in (@{$wf->{in}}) {
		$self->qs(
			q|insert into action_inputs (action_id, name, type, optional, "default") values ($1, $2, $3, $4, $5) returning action_id|,
			$wfid, $$in[0], $$in[1], ($$in[2] ? 'true' : 'false'), make_literal($$in[2])
		);
	}

	for my $out (@{$wf->{out}}) {
		$self->qs(
			q|insert into action_outputs (action_id, name, type, optional) values ($1, $2, $3, $4) returning action_id|,
			$wfid, $$out[0], $$out[1], (($$out[2] && $$out[2] eq 'optional') ? 'true' : 'false')
		);
	}

	if ($self->{tags}) {
		for my $tag (split /:/, $self->{tags}) {
			$self->qs(
				q|insert into action_version_tags (action_id, tag) values ($1, $2) returning action_id|,
				$wfid, $tag
			);
		}
	}

	my ($lockfirst, $locklast) = $self->gen_locks($wf->{locks}); # first and last task_id of locks

	say 'calling get_do';
	my ($first, $last) = $self->gen_do($wf->{do}); # first and last task_id of block

	my $start = $self->instask(T_START, next_task_id => (($lockfirst) ? $lockfirst : $first)); # magic start task to first real task
	$self->set_next($locklast, $first) if $lockfirst; # lock tasks to other tasks
	my $end = $self->instask(T_END); # magic end task
	$self->set_next($last, $end) if $last; # block to end task
	# (if the last statement of a block is a goto, $last is undefined)
	$self->set_next($end, $end); # next_task_id may not be null

	# fixup the magic end label so that return works
	$self->{labels}->{'!!the end!!'} = $end;

	# fixup labels (of gotos)
	foreach my $fixup (@{$self->{fixup}}) {
		my ($tid, $label) = @$fixup;
		my $dst = $self->{labels}->{$label} or die "cannot find label $label";
		$self->set_next($tid, $dst);
	}

	# maybe move this to a deferred trigger on actions?
	$self->qs(q|select do_sanity_check_workflow($1)|, $wfid);

	say "commit";
	$tx->commit;
}

sub generate_action {
	my ($self, %args) = @_;

	my $wf = $args{wfast}->{action};
	my $what = $wf->{action_type};
	my $tags = $args{tags};
	
	say "\nbegin";
	my $tx  = $self->db->begin;

	my $version = 1;
	# find out if a version alreay exists, if so increase version
	# FIXME: race condition when multiples jcc's compile the same wf at the same time..
	{
		my $res = $self->db->dollar_only->query(
			q|select version from actions where name = $1 and type = $2 order by version desc limit 1|, 
			$wf->{workflow_name}, $what
		)->array;
		#print 'res: ', Dumper($res);
		if ( $res and @$res and @$res[0] >= 0 ) {
			$version = @$res[0] + 1;
		}
	}
	say 'version: ', $version;

	my $wfid = $self->qs(
		q|insert into actions (name, type, version) values ($1, $2, $3) returning action_id|, 
		$wf->{workflow_name}, $what,  $version
	);
	say "wfid: $wfid";

	# use a fake returning clause to we can reuse our qs function	
	for my $in (@{$wf->{in}}) {
		$self->qs(
			q|insert into action_inputs (action_id, name, type, optional, "default") values ($1, $2, $3, $4, $5) returning action_id|,
			$wfid, $$in[0], $$in[1], ($$in[2] ? 'true' : 'false'), make_literal($$in[2])
		);
	}

	for my $out (@{$wf->{out}}) {
		$self->qs(
			q|insert into action_outputs (action_id, name, type, optional) values ($1, $2, $3, $4) returning action_id|,
			$wfid, $$out[0], $$out[1], (($$out[2] && $$out[2] eq 'optional') ? 'true' : 'false')
		);
	}

	if ($self->{tags}) {
		for my $tag (split /:/, $self->{tags}) {
			$self->qs(
				q|insert into action_version_tags (action_id, tag) values ($1, $2) returning action_id|,
				$wfid, $tag
			);
		}
	}

	say "commit";
	$tx->commit;
}


### top level keyword generators ###

sub gen_do {
	my ($self, $todo) = @_;
	my ($first, $cur); # first tid of this block, last tid of this block
	for my $do (@$todo) {
		#next unless $do; # skip empty statements (comments?)
		my ($what, $subtree) = $self->get_type($do);
		$what = "gen_$what";
		my ($f, $l);
		if ($self->can($what)) {
			say 'calling ', $what;
			($f, $l) = $self->$what($subtree);
		} else {
			die "don't know what to do with " . Dumper($do);
		}
		die "no first tid?" unless $f;
		$first = $f unless $first;
		$self->set_next($cur, $f) if $cur;
		$cur = $l;
		# if $l is undef then the goto took care of the next_task_id of $l
		# so we must not touch it here
	}
	return ($first, $cur);
}

sub gen_locks {
	my ($self, $locks) = @_;
	my ($first, $cur); # first tid of this block, last tid of this block
	for my $lock (@$locks) {
		my ($locktype, $lockvalue, @lockopts) = @$lock;
		# check all locktypes first
		unless ($self->qs(q|select exists (select 1 from locktypes where locktype=$1)|, $locktype)) {
			die "no locktype $locktype?";
		}
		$self->{locks}->{$locktype}->{value} = $lockvalue;
		my $manual = (any { $_ eq 'manual' } @lockopts) ? true : false;
		my $inherit = (any { $_ eq 'inherit' } @lockopts) ? true : false;
		$self->{locks}->{$locktype}->{manual} = $manual;
		$self->{locks}->{$locktype}->{inherit} = $inherit;
		next if $manual;
		my $tid = $self->instask(T_LOCK, attributes =>
			to_json({
				locktype => $locktype,
				lockvalue => $lockvalue,
				lockinherit => $inherit,
			}));
		$first = $tid unless $first;
                $self->set_next($cur, $tid) if $cur;
                $cur = $tid;
	}
	return ($first, $cur);
}

sub gen_call {
	# only get_split calls us with a third argument for some extra magic
	my ($self, $call, $magic) = @_;

	$magic = ($magic) ? 1 : 0;
	# in magic mode gen_call can only call workflows (aka start childflows)
	# and does so without waiting

	my $types = '{action,procedure,workflow}';
	$types = '{workflow}' if $magic;

	# resolve calls to actions and workflows with the same tags we are compiling with
	my $tags = '{default}';
	# FIXME: would there be any logical reason to have default in the search path
	#        and not have it at the last position?
	if ($self->{tags} and $self->{tags} ne 'default') {
		my @tags = split /:/, $self->{tags};
		push @tags, 'default';
		$tags = '{' . join(',', @tags) . '}';
	}

	my $aid = $self->qs( <<'EOF', $call->{call_name}, $types, $tags);
SELECT
	action_id
FROM
	actions
	LEFT JOIN action_version_tags USING (action_id)
WHERE
	name = $1
	AND type = ANY($2)
	AND (tag = ANY($3) OR tag IS NULL)
	ORDER BY array_position($3, tag), version DESC LIMIT 1;
EOF

	die "action $call->{call_name} not found?" unless $aid;

	my $imap = $self->make_perl($call->{imap}, IMAP);
	my $omap = $self->make_perl($call->{omap}, OMAP);
	my $tid = $self->instask($aid, attributes =>
			to_json({
				imapcode => $imap,
				omapcode => $omap,
			}),
			wait => ($magic) ? 0 : 1); # bleh.. !magic is undef, not 0
	return ($tid, $tid);
}

sub gen_case {
	my ($self, $case) = @_;

	my $casetid = $self->instask(T_SWITCH, attributes => # case
			to_json({
				stringcode => $self->make_perl($case->{case_expression}, STRING)
			}));
	my $endcasetid = $self->instask(T_NO_OP); # dummy task to tie things together

	for my $when (@{$case->{when}}) {
		my ($whenf, $whenl) = $self->gen_do($when->{block});
		for my $match (@{$when->{case_label}}) {
			$self->qs(q|insert into next_tasks values($1, $2, $3) returning from_task_id|, $casetid, $whenf, $match);
		}
		$self->set_next($whenl, $endcasetid); # when block to end case
	}
	if ($case->{else}) {
		my ($ef, $el) = $self->gen_do($case->{else});
		# we store the else branch in the next_task_id field
		$self->set_next($casetid, $ef); # case to else block
		$self->set_next($el, $endcasetid); # else block to end case
	} else {
		$self->set_next($casetid, $endcasetid); # straight to the exit
	}
	return ($casetid, $endcasetid);
}	

sub gen_if {
	my ($self, $if) = @_;

	my $iftid = $self->instask(T_BRANCH, attributes => # if
			to_json({
				boolcode => $self->make_perl($if->{condition}, BOOL)
			}));
	my $endiftid = $self->instask(T_NO_OP); # dummy task to tie things together

	my ($tf, $tl) = $self->gen_do($if->{then});
	$self->qs(q|insert into next_tasks values($1, $2, 'true') returning from_task_id|, $iftid, $tf);
	$self->set_next($tl, $endiftid); # then block to end if

	if ($if->{elsif}) {
		my ($ef, $el) = $self->gen_if($if->{elsif});
		$self->set_next($iftid, $ef); # if to elsif
		$self->set_next($el, $endiftid); # elsif to end if
	} elsif ($if->{else}) {
		my ($ef, $el) = $self->gen_do($if->{else});
		$self->set_next($iftid, $ef); # if to else block
		$self->set_next($el, $endiftid); # else block to end if
	} else {
		$self->set_next($iftid, $endiftid); # no else, straigth to end if
	}
	return ($iftid, $endiftid);
}	

sub gen_eval {
	my ($self, $eval) = @_;
	my $evaltid = $self->instask(T_EVAL, attributes =>
			to_json({
				evalcode => $self->make_perl($eval, OMAP),
			}));
	return ($evaltid, $evaltid);
}

sub gen_goto {
	my ($self, $goto) = @_;
	my $gototid = $self->instask(T_NO_OP); # use a no_op to set the next_task_id of
	die "goto: unknown label $goto" unless exists $self->{labels}->{$goto};
	push @{$self->{fixup}}, [ $gototid, $goto ];
	# return undef so gen_do does not meddle with the next_task_id
	return ($gototid, undef);
}

sub gen_label {
	my ($self, $label) = @_;
	my $labeltid = $self->instask(T_NO_OP); # use a no_op as destination
	# all valid labels are initialized to undef, so the key should exist:
	die "unknown label $label" unless (exists $self->{labels}->{$label});
	# but if it already has a true value:
	die "duplicate label $label" if $self->{labels}->{$label};
	$self->{labels}->{$label} = $labeltid;
	return ($labeltid, $labeltid);	
}

sub gen_lock {
	my ($self, $lock) = @_;
	my $tid;
	my ($type, $value) = @$lock;	
	die "unkown lock $type" unless $self->{locks}->{$type};
	die "lock type $type not declared manual" unless $self->{locks}->{$type}->{manual};
	$value = $self->make_perl($value, STRING);
	if ( $self->{locks}->{$type}->{value} ne '_' ) {
		warn "overriding locks value $self->{locks}->{$type}->{value} with $value";
	}
	$tid = $self->instask(T_LOCK, attributes =>
		to_json({
			locktype => $type,
			stringcode => $value,
			lockinherit => $self->{locks}->{$type}->{inherit},
		})
	);
	#	$tid = $self->instask(T_LOCK, attributes =>
	#		to_json({
	#			locktype => $type,
	#			lockvalue => $self->{locks}->{$type}->{value},
	#			lockinherit => self->{locks}->{$type}->{inherit},
	#		})
	#	);
	return ($tid, $tid);
}

sub gen_raise_error {
	my ($self, $raise) = @_;
	my $raisetid = $self->instask(T_RAISE_ERROR, attributes =>
			to_json({
				imapcode => $self->make_perl($raise, IMAP),
			}));
	return ($raisetid, $raisetid);
}

sub gen_raise_event {
	my ($self, $raise) = @_;
	my $raisetid = $self->instask(T_RAISE_EVENT, attributes =>
			to_json({
				imapcode => $self->make_perl($raise, IMAP),
			}));
	return ($raisetid, $raisetid);
}

sub gen_repeat {
	my ($self, $repeat) = @_;
	my ($bf, $bl) = $self->gen_do($repeat->{block}); # repeat <block> until ...
	my $untiltid = $self->instask(T_BRANCH, attributes => # until with repeat block as default (else) next_task_id
			to_json({
				boolcode => $self->make_perl($repeat->{condition}, BOOL),
			}), next_task_id => $bf);
	$self->set_next($bl, $untiltid); # repeat block to until
	my $endtid = $self->instask(T_NO_OP); # dummy task to tie things together
	$self->qs(q|insert into next_tasks values($1, $2, 'true') returning from_task_id|, $untiltid, $endtid); # until to end
	return ($bf, $endtid);
}

sub gen_return {
	return shift->gen_goto('!!the end!!'); # just a goto to the magic end label
}

sub gen_split {
	my ($self, $split) = @_;
	my (@childtids, $firsttid, $lasttid);
	# first start all childflows in order, with wait = false
	for my $flow (@$split) {
		say 'flow: ', Dumper($flow);
		my $tid = $self->gen_call($flow, 1); # give gen_call some extra magic
		push @childtids, $tid;
		$firsttid = $tid unless $firsttid;
		$self->set_next($lasttid, $tid) if $lasttid;
		$lasttid = $tid;
	}
	# now wait for all chilflows
	my $wfctid = my $tid = $self->instask(T_WAIT_FOR_CHILDREN);
	$self->set_next($lasttid, $wfctid);
	$lasttid = $wfctid;
	# now reap all childflows, in order
	for my $ct (@childtids) {
		my $tid = $self->instask(T_REAP_CHILD, reapfromtask_id => $ct);
		$self->set_next($lasttid, $tid); # $lasttid should be set
		$lasttid = $tid;
	}
	return ($firsttid, $lasttid);
}

sub gen_subscribe {
	my ($self, $sub) = @_;
	my $tid = $self->instask(T_SUBSCRIBE, attributes =>
		to_json({
			imapcode => $self->make_perl($sub, IMAP),
		}));
	return ($tid, $tid);
}

sub gen_try {
	my ($self, $try) = @_;
	my $endtid = $self->instask(T_NO_OP); # dummy task to tie things together
	my ($cbf, $cbl) = $self->gen_do($try->{catch_block}); # catch block
	$self->set_next($cbl, $endtid); # catch block to end
	my $oetid = $self->{oetid};
	$self->{oetid} = $cbf;
	my ($tbf, $tbl) = $self->gen_do($try->{try_block}); # try block
	$self->set_next($tbl, $endtid); # try block to end
	$self->{oetid} = $oetid; # ? $oetid : undef; # prevent undef warnings
	return ($tbf, $endtid);
}

sub gen_unlock {
	my ($self, $unlock) = @_;
	# we don't need to check locktype against the db because gen_locks did that
	# and parse_unlocks checked that the locktype of the unlock is in the
	# declared list of locks from the workflow
	my ($type, $value) = @$unlock;	
	die "unkown lock $type" unless $self->{locks}->{$type};
	die "lock type $type not declared manual" unless $self->{locks}->{$type}->{manual};
	$value = $self->make_perl($value, STRING);
	if ( $self->{locks}->{$type}->{value} ne '_' ) {
		warn "overriding locks value $self->{locks}->{$type}->{value} with $value";
	}
	my $tid;
	$tid = $self->instask(T_UNLOCK, attributes =>
		to_json({
			locktype => $type,
			stringcode => $value,
		})
	);
	#	$tid = $self->instask(T_UNLOCK, attributes =>
	#		to_json({
	#			locktype => $unlock->{type},
	#			lockvalue => $unlock->{value},
	#		}));
	return ($tid, $tid);
}

sub gen_unsubscribe {
	my ($self, $unsub) = @_;
	my $tid = $self->instask(T_UNSUBSCRIBE, attributes =>
		to_json({
			imapcode => $self->make_perl($unsub, IMAP),
		}));
	return ($tid, $tid);
}

sub gen_wait_for_event {
	my ($self, $wait) = @_;
	my $tid = $self->instask(T_WAIT_FOR_EVENT, attributes =>
		to_json({
			imapcode => $self->make_perl($wait->{imap}, IMAP),
			omapcode => $self->make_perl($wait->{omap}, OMAP),
		}));
	return ($tid, $tid);
}

sub gen_while {
	my ($self, $while) = @_;
	my $whiletid = $self->instask(T_BRANCH, attributes => # while test
		to_json({
			boolcode => $self->make_perl($while->{condition}, BOOL),
		}));
	my $endwhiletid = $self->instask(T_NO_OP); # dummy task to tie things together
	my ($bf, $bl) = $self->gen_do($while->{block});
	# while test do <block>
	$self->qs(q|insert into next_tasks values($1, $2, 'true') returning from_task_id|, $whiletid, $bf);
	$self->set_next($bl, $whiletid); # while block back to while test
	$self->set_next($whiletid, $endwhiletid); # false, while test to end while
	return ($whiletid, $endwhiletid);
}

### helpers ###

sub get_type {
	my ($self, $ast) = @_;
	print 'get_type ', Dumper($ast);
	die 'expected a hashref' unless $ast and ref $ast eq 'HASH';
	die 'more than 1 key in hashref' unless scalar keys %$ast == 1;
	# the keys above conveniently resets the each iterator
	#my (k, v) = each(%$ast);
	return each(%$ast);
}

# note: not a method
sub make_rhs {
	my ($ast, $default) = @_;
	say "rhs: ", Dumper(\$ast);
	die 'expected a array' unless $ast and ref $ast eq 'ARRAY';
	my @rhs = @$ast; # a copy to consume
	my $perl = '';
	while (@rhs) {
		my ($term, $op) = splice(@rhs, 0, 2);
		$perl .= make_term($term);
		last unless $op;
		die "cannot do op $op yet" unless
			any { $op eq $_ }
				qw( ** * / % x + - . && || // and or < <= == >= > != lt le eq ge gt ne);
		$perl .= " $op ";
	}			
	return $perl;
}

# note: not a method
sub make_term {
	my ($ast, $default) = @_;
	say "term: ", Dumper(\$ast);
	die 'expected a hashref with 1 key' unless $ast and ref $ast eq 'HASH' and keys %$ast == 1;
	my ($key, $val) = each(%$ast);
	if ($key eq 'unop_term') {
		my ($op, $term) = @$val;
		return $op . make_term($term);
	} elsif ($key eq 'parented') {
		return '(' . make_rhs($val) . ')';
	} elsif ($key eq 'variable') {
		return make_variable($val);
	} elsif ($key eq 'number' ){
		return $val;
	} elsif ($key eq 'boolean' ){
		return ($val =~ /true/i) ? '$TRUE' : '$FALSE';
	} elsif ($key eq 'single_quoted_string' or $key eq 'double_quoted_string'  ){
		$val =~ s/'/\\'/g;
		return "'" . $val . "'";
	} elsif ($key eq 'functioncall') {
		my ($name, $arg) = @$val;
		return make_func($name, $arg);
	} else {
		die "dunno how to make perl from $key";
	}
}

# note: not a method
# used for the default values in a imap
sub make_literal {
	my ($ast) = @_;
	return undef unless $ast;
	say "literal: ", Dumper(\$ast);
	die 'expected a hashref with 1 key' unless ref $ast eq 'HASH' and keys %$ast == 1;
	my ($key, $val) = each(%$ast);
	if ($key eq 'number'
	    or $key eq 'single_quoted_string'
	    or $key eq 'double_quoted_string'
	    or $key eq 'null'){
		return $val;
	} else {
		die "dunno how to make a literal from $key";
	}
}

# note: not a method
sub make_variable {
	my ($ast, $what) = @_;
	say "variable: ", Dumper(\$ast);
	my $default;
	my $toplevel = qr/^[aeiovt]$/;
	if ($what) {
		$default = {imap => 'i', omap => 'v', wfomap => 'o'}->{$what};
		$toplevel = {imap => qr/^[it]$/, omap => qr/^[vt]$/, wfomap => qr/^[ot]$/}->{$what};
		die "dunno $what" unless $default and $toplevel;
	} else {
		$what = 'right hand side'; # for use in a error message
	}
	if (ref $ast eq 'ARRAY') {
		my @a = @$ast; # a copy
		die 'empty term?' unless @a;
		unshift @a, $default if $default and length($a[0]) > 1;
		die "invalid top level $a[0] for $what" unless $a[0] =~ $toplevel; # /^[aeiov]$/;
		my $perl = '$' . shift @a;
		$perl .= "{$_}" for @a;
		return $perl;
	} else {
		die "huh?";
	}
}


# note: not a method
sub make_func {
	my ($name, $arg) = @_;
	if ($name eq 'concat') {
		return '(( ' . join(' ) . ( ', (map { make_rhs([$_]) } @$arg)) . ' ))';
	} elsif	($name eq 'ifdef') {
		$arg = make_rhs($arg);
		return "$arg if defined($arg)";
	} elsif	($name eq 'tostring') {
		$arg = make_rhs($arg);
		return "('' . $arg)";
	} elsif ($name eq 'tonumber') {
		$arg = make_rhs($arg);
		return "(0 + $arg)";
	} elsif ($name eq 'tojson') {
		$arg = make_rhs($arg);
		return "to_json($arg)";
	} elsif ($name eq 'fromjson') {
		$arg = make_rhs($arg);
		return "from_json($arg)";
	} elsif ($name eq 'array') {
		return '[ ' . join(', ', (map { make_rhs([$_]) } @$arg)) . ' ]';
	} elsif ($name eq 'object') {
		my @a = @$arg; # consumable copy
		my @b;
		while (@a) {
			my ($k, $v) = splice(@a, 0, 2);
			die "need key and value" unless $k and $v;
			push @b, make_term($k) . ' => ' . make_term($v);
		}			
		return '{ ' . join(', ', @b) . ' }';
	}
	die "unknown function $name";
}

sub make_perl {
	my ($self, $ast, $what) = @_;
	return '' unless $ast and ref $ast;
	say "make_perl $what: ", Dumper($ast);
	if (ref $ast eq 'HASH' and $ast->{perl_block}) {
		# the easy way
		my $perl = $ast->{perl_block};
		$perl =~ s/^\s+|\s+$//g;
		return $perl;
	}
	die "don't know what perl to make" unless $what;
	#$default = '' unless $default;
	if (any { $what eq $_ } qw( imap omap wfomap )) {
		die 'no arrayref' unless ref $ast eq 'ARRAY';
		my @perl;
		for my $a (@$ast) {
			say 'assignment: ', Dumper($a);
			if (not ref $a) {
				# hack for the magic assignment
				my $t = {imap => 'i', omap => 'v', wfomap => 'o'}->{$what};
				my $f = {imap => 'v', omap => 'o', wfomap => 'v'}->{$what};
				push @perl,  '$' . $t . '{' . $a . '} = $' . $f . '{' . $a . '};';
				next;
			}
			die 'no assignemnt?' unless ref $a eq 'ARRAY' and scalar @$a == 3;
			my ($lhs, $op, $rhs) = @$a;
			die "cannot do op $op yet" unless any { $op eq $_ } qw( = .= += -= );
			push @perl, make_variable($lhs, $what) . " $op " . make_rhs($rhs) . ';';
		}
		return '' . join("\n", @perl);
	#} elsif ($what eq BOOL) {
	#	die 'no bool' unless ref $ast eq 'ARRAY' and scalar @$ast == 3;
	#	my ($lhs, $op, $rhs) = @$ast;
	#	die "cannot do op $op yet" unless any { $op eq $_ } qw( < <= == >= > != lt le eq ge gt ne );
	#	return (make_term($lhs) . " $op " . make_term($rhs) . ';');
	} elsif (any { $what eq $_ } qw( bool string )) {
		return make_rhs($ast) . ';';
	}
	die "making $what perl not implemented";
}

sub instask {
	my ($self, $aid, %args) = @_;
	die "no workflow_id" unless $self->{wfid};
	die "no action_id" unless defined $aid; # action_id 0 is valid ;)
	my ($f, $v);
	my @f = qw( workflow_id action_id on_error_task_id );
	my @v = ($self->{wfid}, $aid, $self->{oetid});
	while (my ($f,$v) = each %args) {
		push @f, $f;
		push @v, $v;
	}
	my $n = 1;
	my $q = 'insert into tasks (' . join(',', @f) . ') values (' . join(',', map { '$' . $n++ } 1 .. scalar @v) . ') returning task_id';
	return $self->qs($q, @v);
}

# query with single return value
sub qs {
	my ($self, $q, @a) = @_;
	my $as = join(',', map { $_ // '' } @a);
	print "query: $q [$as]";
	my $res = $self->{db}->dollar_only->query($q, @a)->array;
	die "query $q [$as] failed" unless $res and @$res and @$res[0];
	say " => @$res[0]";
	return @$res[0];
}

sub set_next {
	my ($self, $f, $t) = @_;
	say "update tasks set next_task_id = $t where task_id = $f";
	my $res = $self->{db}->dollar_only->query(q|update tasks set next_task_id = $1 where task_id = $2|, $t, $f);
	die "update next_task_id of task_id $f failed" unless $res;
}

1;
