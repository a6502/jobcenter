package JobCenter::JCC::CodeGenerator;

# mojo
use Mojo::Base -base;
use Mojo::JSON qw(from_json to_json true false);
use Mojo::Util qw(quote);

# stdperl
use Carp qw(croak);
use Data::Dumper;
use DDP { output => 'stdout' };
use Digest::MD5 qw(md5_hex);
use List::Util qw( any );
#use Scalar::Util qw(blessed);
use Ref::Util qw(is_arrayref is_hashref);

# jobcenter
use JobCenter::JCL::Functions;

has [qw(db debug dry_run fixup force_recompile labels locks oetid
	replace tags wfid)];

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
	T_SLEEP => -15,
};

# configuration of allowed configuration for actions and workflows
our %cfgcfg = (
	action => {
		archive => 'duration',
		filter => 'array',
		retry => 'object',
		timeout => 'duration',
		retryable  => 'boolean',
	},
	workflow => {
		max_depth => 'number',
		max_steps => 'number',
	}
);

our $debug; # cheating a lot..

# code
sub new {
	my $class = shift;
	my $self = $class->SUPER::new(@_);
	$debug = $self->debug;
	return $self;
}

sub generate {
	my ($self, %args) = @_;

	croak 'no wfast?' unless $args{wfast};

	my ($what, $wf) = get_type($args{wfast});
	croak "don't know how to generate $what" unless $what =~ /^(action|workflow)$/;
	if ($what eq 'workflow') {
		$self->generate_workflow(%args);
	} else {
		$self->generate_action(%args);
	}
}

sub generate_workflow {
	my ($self, %args) = @_;

	my $wfsrc = $args{wfsrc};
	my $wf = $args{wfast}->{workflow};
	my $labels = $args{labels} // [];	
	
	# reset codegenerator
	$self->{wfid} = undef;       # workflow_id
	$self->{tags} = $args{tags}; # version tags
	$self->{oetid} = undef;      # current on_error_task_id
	$self->{locks} = {};	     # locks declared in the locks section
	$self->{labels} = { map { $_ => undef } @$labels }; # labels to be filled with task_ids
	$self->{fixup} = [];	     # list of tasks that need the next_task set
				     # format: list of task_id, target label

	# add the magic end label
	$self->{labels}->{'!!the end!!'} = undef;

	my $wfid; # for staleness check
	my $version = 1;
	my $oldsrcmd5;
	# find out if a version alreay exists, if so increase version
	# FIXME: race condition when multiples jcc's compile the same wf at the same time..
	{
		my $res = $self->db->dollar_only->query(
			q|select action_id, version, srcmd5 from actions
				where name = $1 and type = 'workflow'
				order by version desc limit 1|,
			$wf->{workflow_name}
		)->array;
		print 'res: ', Dumper($res) if $debug;
		if ($res and @$res) {
			($wfid, $version, $oldsrcmd5) = @$res;
			$version++;
		}
	}

	$oldsrcmd5 //= '<null>';

	my $newsrcmd5 = md5_hex($$wfsrc);
	# convert to postgresql uuid format
	$newsrcmd5 =~ s/^(\w{8})(\w{4})(\w{4})(\w{4})(\w{12})$/$1-$2-$3-$4-$5/;

	say "version: $version oldsrcmd5: $oldsrcmd5 newsrcmd5: $newsrcmd5";

	if (($oldsrcmd5 eq $newsrcmd5) and not ($self->{dry_run} or $self->{force_recompile})) {
		my $res = $self->db->query('select * from get_stale_actions()')->hashes;
		#print 'stale check: ', Dumper($res) if $debug;
		my @res = grep {$_->{workflow_id} = $wfid and $_->{workflow_name} eq $wf->{workflow_name}} @$res;
		#print 'stale check2: ', Dumper(\@res) if $debug;
		die "workflow $wf->{workflow_name} hasn't changed and isn't stale?\n" unless @res;
	}

	my $role;
	if ($wf->{role}) {
		my @roles = @{$wf->{role}};
		die "multiple roles not supported (yet?)" if $#roles > 0;
		$role = $roles[0];
	}

	my $config = $self->gen_config($wf->{config}, 'workflow');

	my $wfenv = $self->gen_wfenv($wf->{wfenv});

	$wfid = $self->qs(
		q|insert into actions (name, type, version, wfenv, rolename, config, src, srcmd5)
		  values ($1, 'workflow', $2, $3, $4, $5, $6, $7) returning action_id|,
		$wf->{workflow_name}, $version, $wfenv, $role, $config, $$wfsrc, md5_hex($$wfsrc)
	);
	$self->{wfid} = $wfid;
	say "wfid: $wfid";

	if ($wf->{interface}) {
		die "interface conlicts with in/out/env"
			if $wf->{in} or $wf->{out} or $wf->{env};
		my $iname = $wf->{interface}->{workflow_name};
		my $res = $self->db->dollar_only->query(
			q|select action_id, version from actions
				where name = $1 order by version desc limit 1|,
			$iname,
		)->array;
		#print 'res: ', Dumper($res);
		die "interface $iname not found?" unless $res and @$res;
		my $iid = @$res[0]; # fixme: multiple results?

		$self->qs(
			q|insert into action_inputs (action_id, name, type, optional, "default", destination)
				select $1, name, type, optional, "default", destination
					from action_inputs where action_id = $2
			  returning action_id|,	$wfid, $iid
		);

		$self->qs(
			q|insert into action_outputs (action_id, name, type, optional)
				select $1, name, type, optional
					from action_outputs where action_id = $2
			  returning action_id|,	$wfid, $iid
		);
	} else {
		die "either interface or in/out required"
			unless $wf->{in} or $wf->{out};
			# fixme: check env?

		# use a fake returning clause to we can reuse our qs function
		for my $in (@{$wf->{in}}) {
			$in = $in->{iospec} or die 'not an iospec';
			$self->qs(
				q|insert into action_inputs (action_id, name, type, optional, "default")
					values ($1, $2, $3, $4, $5) returning action_id|,
				$wfid, $$in[0], $$in[1], ($$in[2] ? 'true' : 'false'), make_literal($$in[2])
			);
		}

		for my $out (@{$wf->{out}}) {
			$out = $out->{iospec} or die 'not an iospec';;
			$self->qs(
				q|insert into action_outputs (action_id, name, type, optional)
					values ($1, $2, $3, $4) returning action_id|,
				$wfid, $$out[0], $$out[1], (($$out[2] && $$out[2] eq 'optional') ? 'true' : 'false')
			);
		}

	}

	if ($self->{tags}) {
		for my $tag (split /:/, $self->{tags}) {
			$self->qs(
				q|insert into action_version_tags (action_id, tag)
					values ($1, $2) returning action_id|,
				$wfid, $tag
			);
		}
	}

	my ($lockfirst, $locklast) = $self->gen_locks($wf->{locks}); # first and last task_id of locks

	say 'calling get_do' if $debug;
	my ($first, $last) = $self->gen_do($wf->{do}); # first and last task_id of block

	my $start = $self->instask(T_START, next_task_id => (($lockfirst) ? $lockfirst : $first)); # magic start task to first real task
	$self->set_next($locklast, $first) if $lockfirst; # lock tasks to other tasks
	my $end = $self->instask(T_END, attributes => # magic end task
		to_json({
			wfmapcode => make_perl($wf->{wfomap}, WFOMAP)
		}));
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
}

sub generate_action {
	my ($self, %args) = @_;

	my $wfsrc = $args{wfsrc};
	my $wf = $args{wfast}->{action};
	my $what = $wf->{action_type};
	my $tags = $args{tags};
	
	my $wfid; # for replace
	my $version = 1;
	my $oldsrcmd5;
	# find out if a version alreay exists, if so increase version
	# FIXME: race condition when multiples jcc's compile the same wf at the same time..
	{
		my $res = $self->db->dollar_only->query(
			q|select action_id, version, srcmd5 from actions
				where name = $1 and type = $2
				order by version desc limit 1|,
			$wf->{workflow_name}, $what
		)->array;
		print 'res: ', Dumper($res) if $debug;
		if ($res and @$res) {
			($wfid, $version, $oldsrcmd5) = @$res;
		}
	}

	$oldsrcmd5 //= '<null>';

	my $newsrcmd5 = md5_hex($$wfsrc);
	# convert to postgresql uuid format
	$newsrcmd5 =~ s/^(\w{8})(\w{4})(\w{4})(\w{4})(\w{12})$/$1-$2-$3-$4-$5/;

	say "(existing) version: $version oldsrcmd5: $oldsrcmd5 newsrcmd5: $newsrcmd5";

	if (($oldsrcmd5 eq $newsrcmd5) and not ($self->{dry_run} or $self->{force_recompile})) {
		die "action $wf->{workflow_name} hasn't changed?\n";
	}

	my $role;
	if ($wf->{role}) {
		my @roles = @{$wf->{role}};
		die "multiple roles not supported (yet?)" if $#roles > 0;
		$role = $roles[0];
	}

	my $config = $self->gen_config($wf->{config}, $what);

	my $wfenv;

	if ($self->{replace}) {
		die "nothing to replace?" unless $wfid;
		my $dummy = $self->qs(q|
			update actions set
				rolename = $1,
				config = $2,
				src = $3,
				srcmd5 = $4
			where 
			 	action_id = $5
			returning
				 type
			|, $role, $config, $$wfsrc, $newsrcmd5, $wfid
		);
		die 'uh?' unless $dummy eq $what;		
		$self->qdo(q|delete from action_inputs where action_id=$1|, $wfid);
		$self->qdo(q|delete from action_outputs where action_id=$1|, $wfid);
		$self->qdo(q|delete from action_version_tags where action_id=$1|, $wfid);
		say "replacing action_id $wfid";
	} else {
		$version++;
		$wfid = $self->qs(
			q|insert into actions (name, type, version, wfenv, rolename, config, src, srcmd5)
			  values ($1, $2, $3, $4, $5, $6, $7, $8) returning action_id|,
			$wf->{workflow_name}, $what,  $version, $wfenv, $role, $config, $$wfsrc, md5_hex($$wfsrc)
		);
		say "new action_id: $wfid with version $version";
	}

	if ($self->{tags}) {
		for my $tag (split /:/, $self->{tags}) {
			$self->qs(
				q|insert into action_version_tags (action_id, tag) values ($1, $2) returning action_id|,
				$wfid, $tag
			);
		}
	}

	if ($wf->{interface}) {
		die "interface conlicts with in/out/env"
			if $wf->{in} or $wf->{out} or $wf->{env};
		my $iname = $wf->{interface}->{workflow_name};
		my $res = $self->db->dollar_only->query(
			q|select action_id, version from actions where name = $1 order by version desc limit 1|,
			$iname,
		)->array;
		#print 'res: ', Dumper($res);
		die "interface $iname not found?" unless $res and @$res;
		my $iid = @$res[0]; # fixme: multiple results?

		$self->qs(
			q|insert into action_inputs (action_id, name, type, optional, "default", destination)
				select $1, name, type, optional, "default", destination
					from action_inputs where action_id = $2
			  returning action_id|,	$wfid, $iid
		);

		$self->qs(
			q|insert into action_outputs (action_id, name, type, optional)
				select $1, name, type, optional
					from action_outputs where action_id = $2
			  returning action_id|,	$wfid, $iid
		);
	} else {
		die "either interface or in/out required"
			unless $wf->{in} or $wf->{out};
			# fixme: check env?

		# use a fake returning clause to we can reuse our qs function
		for my $in (@{$wf->{in}}) {
			$in = $in->{iospec} or die 'not an iospec';
			$self->qs(
				q|insert into action_inputs (action_id, name, type, optional, "default")
					values ($1, $2, $3, $4, $5) returning action_id|,
				$wfid, $$in[0], $$in[1], ($$in[2] ? 'true' : 'false'), make_literal($$in[2])
			);
		}

		for my $env (@{$wf->{env}}) {
			$env = $env->{iospec} or die 'not an iospec';
			$self->qs(
				q|insert into action_inputs
					(action_id, name, type, optional, "default", destination)
				 values
					($1, $2, $3, $4, $5, 'environment')
				 returning action_id|,
				$wfid, $$env[0], $$env[1], ($$env[2] ? 'true' : 'false'), make_literal($$env[2])
			);
		}

		for my $out (@{$wf->{out}}) {
			$out = $out->{iospec} or die 'not an iospec';
			$self->qs(
				q|insert into action_outputs (action_id, name, type, optional)
					values ($1, $2, $3, $4) returning action_id|,
				$wfid, $$out[0], $$out[1], (($$out[2] && $$out[2] eq 'optional') ? 'true' : 'false')
			);
		}

	}
}


### top level keyword generators ###

sub gen_config {
	my ($self, $config, $what) = @_;
	return unless $config and @$config;
	die "no type?" unless $what;
	my $cc = $cfgcfg{$what};
	die "no configuration configuration for $what" unless $cc;
	my %cfg;

	for (@$config) {
		#print 'config: ', Dumper($_);
		my ($at, $av) = get_type($_);
		die 'not an assignment' unless $at eq 'assignment';
		#die "assignment_operator $av->{assignment_operator} does not make sense here"
		#	unless $av->{assignment_operator} eq '=';
		my ($k, $a, $v) = @{$av}{qw(lhs assignment_operator rhs)};
		unless (ref $k eq 'ARRAY' and $#$k == 0
			 and $a eq '='
			 and ref $v eq 'ARRAY' and $#$v == 0) {
			die "invalid config " . Dumper($_);
		}
		$k = $k->[0];
		my $t = $cc->{$k};
		die "$k is not allowed as config for $what" unless $t;
		$v = $v->[0];
		my ($key, $val) = get_type($v);
		if ($t eq 'array' or $t eq 'object') {
			$cfg{$k} = from_json($val);
		} elsif ($t eq 'duration') {
			# check duration
			my $dummy = $self->qs(
				q|select now() + ($1)::interval;|,
				$val
			);
			$cfg{$k} = $val;
		} else {
			$cfg{$k} = $val;
		}
	}

	return to_json(\%cfg) if %cfg;
	return;
}

# meh.. looks too much like gen_config
sub gen_wfenv {
	my ($self, $wfenv) = @_;
	return unless $wfenv and @$wfenv;
	my %w;

	for (@$wfenv) {
		#print 'wfenv: ', Dumper($_);
		my ($at, $av) = get_type($_);
		die 'not an assignment' unless $at eq 'assignment';
		my ($k, $a, $v) = @{$av}{qw(lhs assignment_operator rhs)};
		unless (ref $k eq 'ARRAY' and $#$k == 0
			 and $a eq '='
			 and ref $v eq 'ARRAY' and $#$v == 0) {
			die "invalid wfenv " . Dumper($_);
		}
		$k = $k->[0];
		$v = $v->[0];
		my ($key, $val) = get_type($v);
		$w{$k} = $val;
	}

	return to_json(\%w) if %w;
	return;
}

sub gen_do {
	my ($self, $todo) = @_;
	my ($first, $cur); # first tid of this block, last tid of this block
	for my $do (@$todo) {
		#next unless $do; # skip empty statements (comments?)
		my ($what, $subtree) = get_type($do);
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
		$lock = $lock->{lockspec} or die 'not a lockspec';
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

sub gen_assert {
	my ($self, $assert) = @_;
	# generate a ast for a if with a raise_error
	my $if = {
                    'then' => [
                                {
                                   'raise_error' => $assert->{'rhs_body'},
                                }
                              ],
                    'condition' => [
					{
					   'unop_term' => [
							      'not ',
							      {
								  'parented' => $assert->{'condition'},
							      }
							  ],
					},
				   ],
        };

	# and generate that..
	return $self->gen_if($if);
}

sub gen_call {
	my ($self, $call, $magic) = @_;

	# gen_detach, gen_map and gen_split are special cases of
	# gen_call with a bit of added magic

	# determine kind of magic
	my %magtab = (
			# $flowonly, $wait, $detach, $map
		none => [0, 1, 0, 0],
		callflow => [1, 0, 0, 0],
		detach => [1, 0, 1, 0],
		map => [1, 0, 0, 1],
	);
	$magic //= 'none';
	my ($flowonly, $wait, $detach, $map) = @{$magtab{$magic}}
		or die "unknown kind of magic $magic";

	# in magic mode gen_call can only call workflows (aka start childflows)
	# and does so without waiting (magic=1) and possibly detaching (magic=2)

	my $types = '{action,procedure,workflow}';
	$types = '{workflow}' if $flowonly;

	# resolve calls to actions and workflows with the same tags we are compiling with
	my $tags = '{default}';
	# FIXME: would there be any logical reason to have default in the search path
	#        and not have it at the last position?
	if ($self->{tags} and $self->{tags} ne 'default') {
		my @tags = split /:/, $self->{tags};
		push @tags, 'default';
		$tags = '{' . join(',', @tags) . '}';
	}

	my $call_name = $call->{call_name}
		 or die 'no call_name?';

	if ($map) {
		die 'no using clause in map?' unless $map = $call->{map_using};
		die 'invalid using clause in map' unless is_arrayref $map;
		$map = join('.', @$map);
		die "invalid using clause $map in map" unless $map =~ /^(\w+|\w\.\w+)$/;
	}

	my ($aid, $config) = $self->qs( <<'EOF', $call_name, $types, $tags);
SELECT
	action_id, config
FROM
	actions
	LEFT JOIN action_version_tags USING (action_id)
WHERE
	name = $1
	AND type = ANY($2)
	AND (tag = ANY($3) OR tag IS NULL)
	ORDER BY array_position($3, tag), version DESC LIMIT 1;
EOF

	die "action $call_name not found?" unless $aid;

	$config = from_json($config) if $config;

	print 'config: ', Dumper($config) if $config;

	die "action $call_name is disabled" if
		is_hashref($config) and $config->{disabled};

	my $imap = make_perl($call->{imap}, IMAP);
	my $omap = make_perl($call->{omap}, OMAP);
	my $tid = $self->instask($aid, attributes =>
			to_json({
				imapcode => $imap,
				omapcode => $omap,
				($wait ? () : (wait => false)),
				($detach ? (detach => true) : ()),
				($map ? (map => $map) : ()),
				#_line => $call->{_line},
			}));
	return ($tid, $tid);
}

sub gen_case {
	my ($self, $case) = @_;

	my $casetid = $self->instask(T_SWITCH, attributes => # case
			to_json({
				stringcode => make_perl($case->{case_expression}, STRING),
				#_line => $case->{_line},
			}));
	my $endcasetid = $self->instask(T_NO_OP); # dummy task to tie things together

	my $whens = $case->{when};
	# workaround for single when cases
	$whens = [$whens] unless ref $whens eq 'ARRAY';
	for my $when (@$whens) {
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

sub gen_detachflow {
	my $self = shift;
	return $self->gen_call(@_, 'detach'); # more magic for gen_call
}

sub gen_eval {
	my ($self, $eval) = @_;
	my $evaltid = $self->instask(T_EVAL, attributes =>
			to_json({
				evalcode => make_perl($eval, OMAP),
				#_line => $eval->{_line},
			}));
	return ($evaltid, $evaltid);
}

sub gen_if {
	my ($self, $if) = @_;

	my $iftid = $self->instask(T_BRANCH, attributes => # if
			to_json({
				boolcode => make_perl($if->{condition}, BOOL),
				#_line => $if->{_line},
				_stmt => 'if',
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

sub gen_interface_call {
	my ($self, $ic) = @_;

	my $iname = $ic->{call_name};
	my $res = $self->db->dollar_only->query(
		q|select action_id, version from actions
			where name = $1 order by version desc limit 1|,
		$iname,
	)->array;
	#print 'res: ', Dumper($res);
	die "interface $iname not found?" unless $res and @$res;
	my $iid = @$res[0];

	my $stringcode = make_perl($ic->{case_expression}, STRING);

	my $casetid = $self->instask(T_SWITCH, attributes => # case
			to_json({
				stringcode => $stringcode
				#_line => $case->{_line},
			}));
	my $endcasetid = $self->instask(T_NO_OP); # dummy task to tie things together

	my %case;

	for my $dname (@{$ic->{interface_namelist}}) {
		die "dupicate destination $dname?"
			if $case{$dname};

		my $res = $self->db->dollar_only->query(
			q|select action_id, version from actions
				where name = $1 order by version desc limit 1|,
			$dname,
		)->array;
		#print 'res: ', Dumper($res);
		die "destination $dname not found?" unless $res and @$res;
		my $did = @$res[0];

		$res = $self->db->dollar_only->query(
			q|select name, type, optional, "default", destination
				from action_inputs where action_id = $1
			  except select name, type, optional, "default", destination
				from action_inputs where action_id = $2|,
			$iid, $did
		)->array;
		die "interfaces for $iname and $dname do not match? " . Dumper($res)
			if $res;

		my $tid;
		($tid, $tid) = $self->gen_call({
				call_name => $dname,
				imap => $ic->{imap},
				omap => $ic->{omap},
				});
		$case{$dname} = $tid;

		$self->qs(q|insert into next_tasks values($1, $2, $3) returning from_task_id|, $casetid, $tid, $dname);
		$self->set_next($tid, $endcasetid); # when block to end case
	}

	# create a raise_error as the else branch
	my $raisetid;
	($raisetid, $raisetid) = $self->gen_raise_error([
			     {
			       'perl_block' => "'interface call destination ' .("
					. substr($stringcode, 0, -1) . ") .' does not exist?'"
			     },
			   ]);

	# we store the else branch in the next_task_id field
	$self->set_next($casetid, $raisetid); # case to else block
	$self->set_next($raisetid, $endcasetid); # else block to end case
	return ($casetid, $endcasetid);
}

sub gen_goto {
	my ($self, $goto) = @_;
	my $gototid = $self->instask(T_NO_OP, attributes =>
			to_json({
				#_line => $goto->{_line},
				_stmt => 'goto',
			})); # use a no_op to set the next_task_id of
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

# let is just a alias for eval
*gen_let = \&gen_eval;

sub gen_lock {
	my ($self, $lock) = @_;
	my $tid;
	my ($type, $value, $assignment) = @{$lock}{qw(locktype lockvalue assignment)};
	die "unkown lock $type" unless $self->{locks}->{$type};
	die "lock type $type not declared manual" unless $self->{locks}->{$type}->{manual};
	my $wait;
	if ($value) {
		$value = make_perl($value, STRING);
	} else {
		die "no assignments for wait_for_lock $value?" unless ref $assignment eq 'ARRAY';
		my $h = assignments_to_hashref($assignment);
		$value = $h->{value} or die 'missing lock value in wait_for_lock';
		$wait = (eval $h->{wait}) or die 'missing wait spec in wait_for_lock';
		# todo: check for valid timeout?
		die "invalid wait spec '$wait'" unless $wait =~ /^((yes|no)$|(\d+))/;
	}
	if ( $self->{locks}->{$type}->{value} ne '_' ) {
		warn "overriding locks value $self->{locks}->{$type}->{value} with $value";
	}
	$tid = $self->instask(T_LOCK, attributes =>
		to_json({
			locktype => $type,
			stringcode => $value,
			lockinherit => $self->{locks}->{$type}->{inherit},
			($wait ? (lockwait => $wait) : ()),
			#_line => $lock->{_line},
		})
	);
	return ($tid, $tid);
}

sub gen_map {
	my ($self, $map) = @_;
	# a 'loose' map is just a implicit split-join
	say "\tcalling gen_split" if $debug;
	return $self->gen_split([{map => $map}]);
}

sub gen_raise_error {
	my ($self, $raise) = @_;
	my $raisetid = $self->instask(T_RAISE_ERROR, attributes =>
			to_json({
				imapcode => '$i{\'msg\'} = ' . make_rhs($raise) . ';',
				#_line => $raise->{_line},
			}));
	return ($raisetid, $raisetid);
}

sub gen_raise_event {
	my ($self, $raise) = @_;
	my $raisetid = $self->instask(T_RAISE_EVENT, attributes =>
			to_json({
				imapcode => make_perl($raise, IMAP),
				#_line => $raise->{_line},
			}));
	return ($raisetid, $raisetid);
}

sub gen_repeat {
	my ($self, $repeat) = @_;
	my ($bf, $bl) = $self->gen_do($repeat->{block}); # repeat <block> until ...
	my $untiltid = $self->instask(T_BRANCH, attributes => # until with repeat block as default (else) next_task_id
			to_json({
				boolcode => make_perl($repeat->{condition}, BOOL),
				#_line => $repeat->{_line},
				_stmt => 'repeat',
			}), next_task_id => $bf);
	$self->set_next($bl, $untiltid); # repeat block to until
	my $endtid = $self->instask(T_NO_OP); # dummy task to tie things together
	$self->qs(q|insert into next_tasks values($1, $2, 'true') returning from_task_id|, $untiltid, $endtid); # until to end
	return ($bf, $endtid);
}

sub gen_return {
	return shift->gen_goto('!!the end!!'); # just a goto to the magic end label
}

sub gen_sleep {
	my ($self, $sleep) = @_;
	my $tid = $self->instask(T_SLEEP, attributes =>
		to_json({
			imapcode => '$i{\'timeout\'} = \'\' .' . make_rhs($sleep) . ';',
			#_line => $sleep->{_line},
		}));
	return ($tid, $tid);
}

sub gen_split {
	my ($self, $split) = @_;
	my (@childtids, $firsttid, $lasttid);
	# first start all childflows in order, with wait = false
	for my $se (@$split) {
		my $t;
		($t, $se) = get_type($se);
		say "se $t: ", Dumper($se) if $debug;
		my $tid = $self->gen_call($se, $t); # give gen_call some extra magic
		push @childtids, { tid => $tid, type => $t };
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
		my $tid = $self->instask(T_REAP_CHILD, attributes =>
			to_json({
				reapfromtask_id => $ct->{tid},
				(($ct->{type} eq 'map') ? (map => true) : ()),
				# _line => $split->{_line},
			}));
		$self->set_next($lasttid, $tid); # $lasttid should be set
		$lasttid = $tid;
	}
	return ($firsttid, $lasttid);
}

sub gen_subscribe {
	my ($self, $sub) = @_;
	my $tid = $self->instask(T_SUBSCRIBE, attributes =>
		to_json({
			imapcode => make_perl($sub, IMAP),
			 #_line => $sub->{_line},
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
	my ($type, $value) = @{$unlock}{qw(locktype lockvalue)};
	die "unkown lock $type" unless $self->{locks}->{$type};
	die "lock type $type not declared manual" unless $self->{locks}->{$type}->{manual};
	$value = make_perl($value, STRING);
	if ( $self->{locks}->{$type}->{value} ne '_' ) {
		warn "overriding locks value $self->{locks}->{$type}->{value} with $value";
	}
	my $tid;
	$tid = $self->instask(T_UNLOCK, attributes =>
		to_json({
			locktype => $type,
			stringcode => $value,
			#_line => $unlock->{_line},
		})
	);
	return ($tid, $tid);
}

sub gen_unsubscribe {
	my ($self, $unsub) = @_;
	my $tid = $self->instask(T_UNSUBSCRIBE, attributes =>
		to_json({
			imapcode => make_perl($unsub, IMAP),
			#_line => $unsub->{_line},
		}));
	return ($tid, $tid);
}

sub gen_wait_for_event {
	my ($self, $wait) = @_;
	my $tid = $self->instask(T_WAIT_FOR_EVENT, attributes =>
		to_json({
			imapcode => make_perl($wait->{imap}, IMAP),
			omapcode => make_perl($wait->{omap}, OMAP),
			#_line => $wait->{_line},
		}));
	return ($tid, $tid);
}

# wait_for_lock is a special case handled in gen_lock
*gen_wait_for_lock = \&gen_lock;

sub gen_while {
	my ($self, $while) = @_;
	my $whiletid = $self->instask(T_BRANCH, attributes => # while test
		to_json({
			boolcode => make_perl($while->{condition}, BOOL),
			#_line => $while->{_line},
			_stmt => 'while',
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

# note: not a method
sub get_type {
	my ($ast) = @_;
	print 'get_type ', Dumper($ast) if $debug;
	die 'expected a hashref' unless $ast and ref $ast eq 'HASH';
	die 'more than 1 key in hashref' unless scalar keys %$ast == 1;
	# the keys above conveniently resets the each iterator
	#my (k, v) = each(%$ast);
	return each(%$ast);
}

# note: not a method
sub assignments_to_hashref {
	my ($ast) = @_;

	print 'assignments_to_hashref: ', Dumper($ast) if $debug;

	my %h;

	for my $a (@$ast) {
		my ($lhs, $op, $rhs) = @{$a}{qw(lhs assignment_operator rhs)};
		die "cannot do op $op yet" unless $op eq '=';
		$lhs = $lhs->[0];
		my $val = make_perl($rhs, STRING);
		$h{$lhs} = $val;
	}

	print 'assignments_to_hashref: ', Dumper(\%h) if $debug;

	return \%h;
}


# note: not a method
sub make_rhs {
	my ($ast, $default) = @_;
	$ast = [ $ast ] if $ast and ref $ast eq 'HASH';
	say "rhs: ", Dumper(\$ast) if $debug;
	die 'expected a array' unless $ast and ref $ast eq 'ARRAY';
	my @rhs = @$ast; # a copy to consume
	my $perl = '';
	while (@rhs) {
		my ($term, $op) = splice(@rhs, 0, 2);
		$perl .= make_term($term);
		last unless $op;
		if (defined $op->{regexmatch}) {
			$op = $op->{regexmatch};
			$perl .= " =~ /$op/ ";
			$op = shift(@rhs);
			last unless $op;
		}
		$op = $op->{rhs_operator} or die 'not a rhs_operator?';
		die "cannot do op $op yet" unless
			any { $op eq $_ }
				qw( ** * / % x + - . && || // and or xor < <= == >= > != lt le eq ge gt ne);
		$perl .= " $op ";
	}			
	return $perl;
}

# note: not a method
sub make_term {
	my ($ast, $default) = @_;
	say "term: ", Dumper(\$ast) if $debug;
	die 'expected a hashref with 1 key' unless $ast and ref $ast eq 'HASH' and keys %$ast == 1;
	my ($key, $val) = each(%$ast);
	if ($key eq 'unop_term') {
		my ($op, $term) = @$val;
		return $op . make_term($term);
	} elsif ($key eq 'parented') {
		return '(' . make_rhs($val) . ')';
	} elsif ($key eq 'variable') {
		return make_variable($val);
	} elsif ($key eq 'number' ) {
		return $val;
	} elsif ($key eq 'boolean' ) {
		return ($val =~ /true/i) ? '$TRUE' : '$FALSE';
	} elsif ($key eq 'null' ) {
		return 'undef';
	} elsif ($key eq 'single_quoted_string' or $key eq 'double_quoted_string'  ) {
		$val =~ s/'/\\'/g;
		return "'" . $val . "'";
	} elsif ($key eq 'functioncall') {
		my ($name, $arg) = @{$val}{qw(funcname funcarg)};
		return make_func($name, $arg);
	} elsif ($key eq 'perl_block' ){
		return $val;
	} else {
		die "dunno how to make perl from $key";
	}
}

# note: not a method
# used for the default values in a imap, so this generates json and not perl like the
# sub above
sub make_literal {
	my ($ast) = @_;
	return undef unless $ast;
	say "literal: ", Dumper(\$ast) if $debug;
	my ($key, $val) = get_type($ast);
	if ($key eq 'number'
	    or $key eq 'boolean'
	    or $key eq 'null') {
		return $val;
	} elsif ($key eq 'single_quoted_string'
	    or $key eq 'double_quoted_string') {
		$val =~ s/"/\\"/g;
		return '"' . $val . '"';
	} else {
		die "dunno how to make a literal from $key";
	}
}

# note: not a method
sub make_variable {
	my ($ast, $what) = @_;
	say "variable: ", Dumper(\$ast) if $debug;
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
		unshift @a, $default if $default and (length($a[0]) > 1 or $#a == 0);
		die "invalid top level $a[0] for $what" unless $a[0] =~ $toplevel; # /^[aeiov]$/;
		my $perl = '$' . shift @a;
		for (@a) {
			# uglyness to handle array indexes
			if (ref $_ eq 'HASH') {
				my ($v, $i) = @{$_->{varpart_array} // []} or die 'not varpart_array?';
				$perl .= "{'$v'}->[$i]";
			} else {
				$perl .= "{'$_'}";
			}
		}
		say "make_variable: $perl" if $debug;
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
	} elsif	($name eq 'defined') {
		$arg = make_rhs($arg);
		return "defined( $arg )";
	} elsif	($name eq 'ifdef') {
		$arg = make_rhs($arg);
		return "$arg if defined $arg";
	} elsif	($name eq 'tostring') {
		$arg = make_rhs($arg);
		return "('' . ($arg))";
	} elsif ($name eq 'tonumber') {
		$arg = make_rhs($arg);
		return "(0 + ($arg))";
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
	} elsif (UNIVERSAL::can('JobCenter::JCL::Functions', $name)) {
		$arg = make_rhs($arg);
		return "(\$JCL->$name($arg))";
	}
	die "unknown function $name";
}

# note: not a method
sub make_perl {
	my ($ast, $what) = @_;
	return '' unless $ast and ref $ast;
	say "make_perl $what: ", Dumper($ast) if $debug;
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
		#die 'not (magic_)assignment' unless ref $ast eq 'HASH'
		#	and ( $ast->{assignment} or $ast->{magic_assignment} );
		my @perl;

		for my $a (@$ast) {
			#say 'assignment: ', Dumper($a);
			my ($at, $av) = get_type($a);
			if ($at eq 'perl_block') {
				# force a copy of $av
				push @perl, make_perl($a, $what);
				next;
			} elsif ($at eq 'magic_assignment') {
				# hack for the magic assignment
				my $t = {imap => 'i', omap => 'v', wfomap => 'o'}->{$what};
				my $f = {imap => 'v', omap => 'o', wfomap => 'v'}->{$what};
				if ($av->[0] eq '*') {
					push @perl,  '%' . $t . ' = %' . $f . ';';
				} else {
					push @perl,  '$' . $t . '{' . $_ . '} = $' . $f . '{' . $_ . '};' for @$av;
				}
				next;
			}
			die 'not assigment?' unless $at eq 'assignment';
			my ($lhs, $op, $rhs) = @{$av}{qw(lhs assignment_operator rhs)};
			no warnings 'qw'; # ugh
			die "cannot do op $op yet" unless any { $op eq $_ } qw( = .= ,= += -= *= /= //= ||= );
			if ($op eq ',=') {
				push @perl, 'push( @{' . make_variable($lhs, $what) . '}, ' . make_rhs($rhs) . ' );';
			} else {
				push @perl, make_variable($lhs, $what) . " $op " . make_rhs($rhs) . ';';
			}
		}
		say "perl for $what: ", join(' ', @perl) if $debug;
		return '' . join("\n", @perl);
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

# 'do' query
sub qdo {
	my ($self, $q, @a) = @_;
	my $as = join(',', map { $_ // '' } @a);
	print "query: $q [$as]" if $debug;
	my $res = $self->{db}->dollar_only->query($q, @a);
	say ' => ok' if $debug;
}

# query with single return value
sub qs {
	my ($self, $q, @a) = @_;
	my $as = join(',', map { $_ // '' } @a);
	print "query: $q [$as]" if $debug;
	my $res = $self->{db}->dollar_only->query($q, @a)->array;
	die "query $q [$as] failed\n" unless is_arrayref($res) and defined @$res[0];
	say " => @$res[0]" if $debug;
	return wantarray ? @$res : @$res[0];
}

sub set_next {
	my ($self, $f, $t) = @_;
	say "update tasks set next_task_id = $t where task_id = $f" if $debug;
	my $res = $self->{db}->dollar_only->query(q|update tasks set next_task_id = $1 where task_id = $2|, $t, $f);
	die "update next_task_id of task_id $f failed" unless $res;
}

1;
