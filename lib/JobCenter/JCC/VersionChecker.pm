package JobCenter::JCC::VersionChecker;

# mojo
use Mojo::Base -base;

# stdperl
use Carp qw(croak);

use constant CUTOFF => 80;

has [qw(db debug verbose no_names)];

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new();

	$self->{db}       = $args{db} or croak 'no db?';
	$self->{debug}    = $args{debug}    // 0;
	$self->{verbose}  = $args{verbose}  // 0;
	$self->{no_names} = $args{no_names} // 0;

	return $self;
}

sub workers {
	my ($self, %args) = @_;

	my $verbose  = $self->verbose;
	my $no_names = $self->no_names;
	my $cutoff = $args{cutoff} // CUTOFF;

	my $sql = <<_SQL;
WITH tagged_actions AS (
	SELECT 
		a.action_id,
		a.name,
		a.type,
		avt.tag
	FROM
		actions a
	LEFT JOIN
		action_version_tags avt
	ON
		avt.action_id = a.action_id
)
SELECT 
	wa.action_id,
	ta1.name action_name,
	wa.worker_id,
	w.name worker_name
FROM
	worker_actions wa
JOIN 
	workers w
ON
	w.worker_id = wa.worker_id
JOIN
	tagged_actions ta1
ON 
	ta1.action_id = wa.action_id
LEFT JOIN 
	tagged_actions ta2
ON
	ta2.type = ta1.type and 
	ta2.name = ta1.name and
	coalesce(ta2.tag, 'default') = coalesce(ta1.tag, 'default')
WHERE
	ta2.action_id > ta1.action_id
GROUP BY
	wa.worker_id,
	w.name,
	wa.action_id,
	ta1.name
_SQL

	my $res = $self->{db}->query($sql);
	my $col = $res->hashes;
	my @rows;
	push @rows, [
		$verbose >= 2 || $no_names ? (qw/
			action_id
		/) : (),
		$verbose >= 0 && !$no_names ? (qw/
			action_name
		/) : (),
		$verbose >= 1 || $no_names ? (qw/ 
			worker_id
		/) : (),
		$verbose >= 0 && !$no_names ? (qw/
			worker_name              
		/) : (),
	];

	$col->each(sub {
		my $r = shift;
		push @rows, [
			$verbose >= 2 || $no_names ? (
				$r->{action_id},
			) : (),
			$verbose >= 0 && !$no_names ? (
				_cutoff($r->{action_name}, $cutoff)
			) : (),
			$verbose >= 1 || $no_names ? (
				$r->{worker_id}
			) : (),
			$verbose >= 0 && !$no_names ? (
				_cutoff($r->{worker_name}, $cutoff)
			) : (),
		];
	});

	return \@rows;
}

# find any out of date actions / workflows in the actions table filter by 
# action (or workflow) that is out of date or workflow that contains it.
sub out_of_date {
	my ($self, %args) = @_;

	my %lookup;

	for my $type (qw/action_ids actions workflows workflow_ids/) {
		$lookup{$type} = {}; 
		$lookup{$type}{$_}++ for @{$args{$type}||[]};
	}

	my $verbose  = $self->verbose;
	my $no_names = $self->no_names;
	my $cutoff = $args{cutoff} // CUTOFF;

	my @rows;
	my %widths;

	my $res = $self->{db}->query('select * from get_stale_actions()');
	my $col = $res->hashes;

	if (
		%{$lookup{action_ids}} or 
		%{$lookup{actions}} or
		%{$lookup{workflow_ids}} or 
		%{$lookup{workflows}}
	) {
		$col = $col->grep(sub { 
			$lookup{action_ids}{$_[0]{action_id}} or
			$lookup{workflow_ids}{$_[0]{workflow_id}} or
			$lookup{actions}{$_[0]{name}} or
			$lookup{workflows}{$_[0]{workflow_name}}
		}); 
	}

	if ($verbose >= 3) {

		# expand top_level_ids 

		my $sql = <<_SQL;
SELECT 
	a.action_id top_level_id,
	a.version top_level_version,
	a.name top_level_name,
	avt.tag top_level_tag
FROM
	actions a
LEFT JOIN
	action_version_tags avt
ON
	avt.action_id = a.action_id
WHERE
	a.action_id = ?
_SQL

		$col = $col->map(sub {
			my $r = shift;
			my @expanded;
			for my $tl_id (@{$r->{top_level_ids}}) {
				my $res = $self->{db}->query($sql, $tl_id);
				my $col = $res->hashes;
				if ($col->size) {
					$col->each(sub {
						push @expanded, { %$r, %{$_[0]} };
					});
				} else {
					push @expanded, { %$r };
				}
			}
			return @expanded;
		});
	}

	$col->each(sub {
		my $r = shift;
		for (qw/
			top_level_id 
			top_level_version
			workflow_id
			workflow_version
			action_id
			version
			latest_action_id
			latest_version
		/) {
			$r->{$_} //= '';
			$widths{$_} = !defined $widths{$_} || length $r->{$_} > $widths{$_} 
				? length $r->{$_} 
				: $widths{$_};
		}
	});

	push @rows, [
		$verbose >= 3 && !$no_names ? (qw/
			top_level_name    
		/) : (),
		$verbose >= 3 ? (qw/
			top_level
		/) : (),
		$verbose >= 0 && !$no_names ? (qw/
			workflow_name     
		/) : (),
		$verbose >= 0 ? (qw/
			workflow
		/) : (),
		$verbose >= 0 && !$no_names ? (qw/
			action_name              
		/) : (),
		$verbose >= 0 ? (qw/
			stale
		/) : (),
		$verbose >= 1 ? (qw/
			current
		/) : (),
		$verbose >= 2 ? (qw/
			tag
		/) : (),
		$verbose >= 4 ? (qw/
			type
		/) : (),
	];

	$col->each(sub {
		my $r = shift;
		push @rows, [
			$verbose >= 3 && !$no_names ? (
				_cutoff($r->{top_level_name}, $cutoff)
			) : (),
			$verbose >= 3 ? (
				sprintf("%$widths{top_level_id}s v%s", @{$r}{qw/top_level_id top_level_version/}),
			) : (),
			$verbose >= 0 && !$no_names ? (
				_cutoff($r->{workflow_name}, $cutoff)
			) : (),
			$verbose >= 0 ? (
				sprintf("%$widths{workflow_id}s v%s", @{$r}{qw/workflow_id workflow_version/}),
			) : (),
			$verbose >= 0 && !$no_names ? (
				_cutoff($r->{name}, $cutoff)
			) : (),
			$verbose >= 0 ? (
				sprintf("%$widths{action_id}s v%s", @{$r}{qw/action_id version/}),
			) : (),
			$verbose >= 1 ? (
				sprintf("%$widths{latest_action_id}s v%s", @{$r}{qw/latest_action_id latest_version/}),
			) : (),
			$verbose >= 2 ? (
				_cutoff($r->{tag}, $cutoff)
			) : (),
			$verbose >= 4 ? (
				$r->{type},
			) : (),
		];
	});

	$res->finish;

	return \@rows;
}

sub _cutoff {
	my ($str, $cutoff) = @_;
	my $len = length $str;
	substr $str, $cutoff, $len - $cutoff, "\N{HORIZONTAL ELLIPSIS}" 
		if $cutoff and $len >= $cutoff;
	return $str;
}

1;
