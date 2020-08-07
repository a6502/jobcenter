package JobCenter::Adm::Errors;

use Mojo::Base 'JobCenter::Adm::Cmd';

use List::Util 'first';
use FindBin ();

use constant MAX_ERR_MSG_LEN => 100;
use constant CONF_FILE => "$FindBin::Bin/../etc/jcadm/errors/fields.conf";

sub do_cmd {
	my $self = shift;
	my $verbose = 0;
	my $cutoff;

	$self->_read_conf;

	my @names;
	while (@_) {
		local $_ = shift @_;
		/^--verbose$/ and do { $verbose++; next };
		/^-(v+)$/     and do { $verbose += length $1; next };
		/^(?:-c|--cutoff)(?:(=)(.*))?$/ and do { 
			$cutoff = $1 ? $2 : shift @_;
			next;
		};
		/^-/ and die "unknown flag: $_\n";
		push @names, $_;
	}

	return $verbose > 1 ? $self->_verbose($cutoff, \@names) : $self->_summary($cutoff, \@names, $verbose);
}

sub _select_counts {
	my ($self, $cutoff, $names, $details) = @_;

	my $msg = $self->_msg_field(qw/out_args task_state/);
	my @det = $details ? (", $msg as msg", ", $msg") : ('', '');

	my @qs   = ("?")x@$names;
	local $" = ', ';

	my $cond = '';
	$cond .= 'and coalesce(job_finished, task_completed, task_started, job_created) >= ? ' if $cutoff;
	$cond .= "and a.name in (@qs) " if @$names;

	my $result = eval { $self->adm->pg->db->query(qq[
		select count(*) as count, a.name as workflow_name $det[0]
		from jobs j
		join actions a 
		on j.workflow_id = a.action_id
		where j.state = 'error' and j.job_state->'error_seen' is null
		$cond
		group by a.name $det[1]
		order by a.name $det[1]
	], ($cutoff ? $cutoff : ()), @$names)};

	if (my $e = $@) {
		die $e =~ /invalid input syntax for type timestamp with time zone: "([^"]+)"/
			? "invalid cutoff: $1\n"
			: $e;
	}

	return $result;
}

sub _verbose {
	my ($self, $cutoff, $names) = @_;
	my $result = $self->_select_counts($cutoff, $names, 0);

	my $found;
	my $cond = $cutoff
		? 'and coalesce(job_finished, task_completed, task_started, job_created) >= ? '
		: '';
	
	for my $jobs (@{$result->hashes}) {

		my $result = $self->adm->pg->db->query(qq[
			select
				j.job_id as job_id,
				j.workflow_id as workflow_id,
				wf.name as workflow_name,
				to_char(j.job_created, 'yyyy-mm-dd HH24:MI:SS') as created,
				to_char(coalesce(job_finished, task_completed, task_started, job_created), 
					'yyyy-mm-dd HH24:MI:SS') as last_change
			from
				jobs as j join actions as wf
			on 
				j.workflow_id = wf.action_id
			where j.state = 'error' and j.job_state->'error_seen' is null and wf.name = ?
				$cond
			order by
				j.job_id desc, j.workflow_id
		], $jobs->{workflow_name}, ($cutoff ? $cutoff : ()));

		my @rows = ($result->columns, @{$result->arrays});

		if (@rows > 1) {
			$found = 1;
			$self->tablify(\@rows, "\njob errors: - $jobs->{workflow_name} ($jobs->{count})");
		}
	}

	say 'no job errors' unless $found;

	return 0;
}

sub _summary {
	my $self = shift;
	my $result = $self->_select_counts(@_);
	
	my $cols = $result->columns(); 
	my $col  = first { $cols->[$_] eq 'msg' } 0..$#$cols;
	my @rows = ( $cols, map { _trim_msg($col, $_) } @{$result->arrays} );

	if ($#rows) {
		$self->tablify(\@rows, 'job errors:');
	} else {
		say 'no job errors';
	}

	return 0;
}

sub _trim_msg {
	my ($col, $row) = @_;

	return $row unless defined $col;

	my $msg = $row->[$col];

	if (defined $msg) {
		$msg =~ s/(?:\n|\r|\s)+/ /g;
		if (length $msg > MAX_ERR_MSG_LEN) {
			$msg = substr($msg, 0, (MAX_ERR_MSG_LEN - 1)) . "\N{HORIZONTAL ELLIPSIS}";
		}
	}

	$row->[$col] = $msg;

	return $row;
}

sub _read_conf {
	my $self = shift;
	my @fields;
	if (open my $fh, "<", CONF_FILE) {
		while (<$fh>) {
			chomp;
			if (/^\s*((?:\w+\.)*\w+)\s*$/) {
				push @fields, [ split /\./, $1 ];
			} else {
				warn "bad field format: $_\n" if $_;
			}
		}
	}
	$self->{fields} = @fields ? \@fields : [[ 'error' ]];
}

sub _msg_field {
	my $self = shift;
	my $msg  = "coalesce(";
	for my $fields (@{$self->{fields}}) {
		my @start = map { "'$_'" } @$fields;
		my $last  = pop @start;
		$msg .= join("->", $_, @start)."->>$last, " for @_;
	}
	$msg .= "'unknown error')";
	return $msg;
}

1;


