package JobCenter::JCC::VersionChecker;

# mojo
use Mojo::Base -base;

# stdperl
use Carp qw(croak);

has [qw(db debug)];

sub new {
	my ($class, %args) = @_;
	my $self = $class->SUPER::new();

	$self->{db}    = $args{db} or croak 'no db?';
	$self->{debug} = $args{debug} // 1; # or 1?

	return $self;
}

# find any out of date actions / workflows in the actions table filter by 
# action (or workflow) that is out of date or workflow that contains it.
sub out_of_date {
	my ($self, %args) = @_;

	return $self->{db}->query($self->_select(@args{qw/workflows actions/}));
}

#########
# private
#########

sub _select {
	my ($self, $workflows, $actions) = @_;

	my ($wf, $ac) = map { 
		@$_ ? "and name in ('" . join("','", @$_) . "')" : ""
	} $workflows // [], $actions // [];

	return <<END;
select 
	workflow_name,
	workflow_id,
	active_actions.name as action_name, 
	active_actions.action_id, 
	active_actions.version, 
	active_actions.type,
	max(new_actions.action_id) as latest_action_id, 
	max(new_actions.version) as latest_version
from actions as new_actions
inner join 
(
	select a.action_id, a.name, type, version, workflow_id, workflow_name
	from actions as a 
	inner join (
		select t.action_id, t.workflow_id, workflow_name 
		from tasks as t 
		inner join ( 
			select action_id as workflow_id, name as workflow_name
			from actions as a 
			inner join ( 
				select name, max(version) as version 
				from actions 
				where type = 'workflow' $wf
				group by name
			) as latest_workflow_version 
			using (name, version)
		) as latest_workflow 
		using (workflow_id)
		group by t.action_id, t.workflow_id, workflow_name
	) as active_tasks
	using (action_id)
	where type in ('workflow', 'action') $ac
) as active_actions
using (name, type)
where new_actions.version > active_actions.version
group by workflow_name, workflow_id, active_actions.name, 
active_actions.action_id, active_actions.version, active_actions.type
END
}

1;
