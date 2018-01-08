package JobCenter::Adm::Cmd;

use Mojo::Base -base;

use Text::Table::Tiny 0.04;

has [qw(adm)];

sub do_cmd {
	die "not implemented\n";
}

sub tablify {
	my ($self, $rows, $title) = @_;
	say $title if $title;
	say Text::Table::Tiny::generate_table(rows => $rows, header_row => 1);
}

1;


