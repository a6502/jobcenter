package JobCenter::Adm::Locks;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	my $verbose = 0;

	my @locktypes;
	while (@_) {
		local $_ = shift @_;
		/^--verbose$/ and do { $verbose++; next };
		/^-(v+)$/     and do { $verbose += length $1; next };
		/^-/ and die "unknown flag: $_\n";
		push @locktypes, $_;
	}

	# verbosity=0  - print summary
	# verbosity=1  - print delatiled summary
	# verbosity=2+ - print verbose

	return $verbose > 1 
		? $self->_verbose(\@locktypes) 
		: $self->_summary(\@locktypes, $verbose);
}

sub _select_counts {
	my ($self, $locktypes, $detailed) = @_;

	my @qs   = ("?")x@$locktypes;
	local $" = ', ';

	my $lockv = $detailed ? ', lockvalue' : '';

	my $sql = <<_SQL;
		WITH waiting AS (
			SELECT 
				j.job_id,
				'waiting'::text AS lock, 
				l.locktype, 
				l.lockvalue
			FROM 
				jobs j 
			JOIN 
				locks l 
			ON 
				j.task_state->>'waitforlocktype' = l.locktype AND
				j.task_state->>'waitforlockvalue' = l.lockvalue AND
				j.state = 'lockwait' 
		)
		SELECT 
			lock, 
			locktype 
			$lockv, 
			count(*) AS count, 
			CASE waiting
				WHEN 0 THEN ''
				ELSE waiting::text
			END AS waiting
		FROM 
			(
				SELECT 
					0 AS waiting,
					w1.lock,
					w1.locktype,
					w1.lockvalue
				FROM 
					waiting w1
				UNION ALL 
				SELECT 
					(
						SELECT count(*)
						FROM   waiting w
						WHERE  
							w.locktype = l.locktype AND 
							w.lockvalue = l.lockvalue AND
							w.job_id != j.job_id
					) AS waiting, 
					'held' AS lock, 
					l.locktype, 
					l.lockvalue
				FROM 
					jobs j 
				JOIN 
					locks l 
				ON 
					j.job_id = l.job_id
			) AS ja 
		WHERE 
			${\(@$locktypes ? "locktype IN (@qs)" : 'true')}
		GROUP BY 
			lock, 
			locktype 
			$lockv,
			waiting
		ORDER BY 
			lock, 
			locktype 
			$lockv
_SQL

	my $result = $self->adm->pg->db->query($sql, @$locktypes);

	return $result;
}

sub _verbose {
	my ($self, $locktypes) = @_;

	my $result = $self->_select_counts($locktypes, 1);

	my $found;
	
	for my $jobs (@{$result->hashes}) {

		my $result = $self->adm->pg->db->query(
			$jobs->{lock} eq 'waiting' 
			? qq[
				SELECT
					j.job_id AS job_id,
					j.workflow_id AS workflow_id,
					wf.name AS workflow_name,
					to_char(j.job_created, 'yyyy-mm-dd HH24:MI:SS') AS created,
					to_char(j.task_entered, 'yyyy-mm-dd HH24:MI:SS') AS lock_wait
				FROM 
					jobs AS j 
				JOIN 
					actions AS wf
				ON 
					j.workflow_id = wf.action_id
				JOIN 
					locks AS l
				ON 
					j.task_state->>'waitforlocktype' = l.locktype AND
					j.task_state->>'waitforlockvalue' = l.lockvalue AND
					j.state = 'lockwait' 
				WHERE 
					l.locktype = ? AND l.lockvalue = ?
				ORDER BY 
					j.job_id DESC, j.workflow_id
			]
			: qq[
				SELECT
					j.job_id AS job_id,
					j.workflow_id AS workflow_id,
					wf.name AS workflow_name,
					to_char(j.job_created, 'yyyy-mm-dd HH24:MI:SS') AS created
				FROM 
					jobs AS j 
				JOIN 
					actions AS wf
				ON 
					j.workflow_id = wf.action_id
				JOIN 
					locks AS l
				ON 
					j.job_id = l.job_id
				WHERE 
					l.locktype = ? AND l.lockvalue = ?
				ORDER BY 
					j.job_id DESC, j.workflow_id
			], @{$jobs}{qw/locktype lockvalue/});

		my @rows = ($result->columns, @{$result->arrays});

		if (@rows > 1) {
			$found = 1;
			my $waiting = $jobs->{waiting} ? "/$jobs->{waiting}" : '';
			$self->tablify(\@rows, 
				sprintf "\njob locks (%s): %s=%s (%s%s)" => 
				( @{$jobs}{qw/lock locktype lockvalue count/}, $waiting )
			);
		}
	}

	say 'no job locks' unless $found;

	return 0;
}

sub _summary {
	my $self = shift;
	my $result = $self->_select_counts(@_);
	
	my @rows;
	push @rows, $result->columns();
	push @rows, @{$result->arrays()};

	if ($#rows) {
		$self->tablify(\@rows, 'job locks:');
	} else {
		say 'no job locks';
	}

	return 0;
}

1;


