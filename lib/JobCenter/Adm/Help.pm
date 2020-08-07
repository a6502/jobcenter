package JobCenter::Adm::Help;

use Mojo::Base 'JobCenter::Adm::Cmd';

sub do_cmd {
	my $self = shift;
	
	return $self->help() unless @_;
	
	my $more = shift;

	my $admcmd = $self->adm->load_cmd($more);

	unless ($admcmd) {
		say "no help available for $more";
		return 0;
	}
		
	my $help = $admcmd->can('help');
	
	unless ($help) {
		say "command $more has no help available";
		return 0;
	}

	return $help->(@_);
}


sub help {
	print <<'EOT';

Usage: jcadm [opts] <cmd> ...

Subcomands:

api-clients                     : prints connected api clients
api-clientsraw                  : dump of the clients hash
api-jobs                        : prints current api jobs
api-stats                       : prints current api tasks
api-tasks                       : prints current api tasks
jobs   [-vv?] [states]          : prints things about jobs
stale  [-vv?] [workflows]       : prints running jobs with stale workflows
errors [-vv?] [workflows]       : prints things about job errors
locks  [-vv?] [locktypes]       : prints things about job locks
help                            : this help
workers                         : prints worker status from the db

Use 'jcadm <cmd> help' for more information about a subcommand.

Supported options:
	--config=/path/to/cfg       : use alternate configfile
	--debug=1                   : set debug flag
	-h, -?,  --help             : prints "try jcadm help"
	-v, -vv, --verbose          : verbosity level

EOT
	return 0;
}

1;

