# jobcenter requirements
# install with something like:
# cpanm --from http://your.pinto:3111/stacks/jobcenter --installdeps .

requires 'Config::Tiny', '2.02';

requires 'DBD::Pg';
requires 'DBI';

requires 'JSON::MaybeXS', '1.003008';
requires 'JSON::RPC2::TwoWay';

requires 'List::Util', '1.33';

requires 'Mojolicious', '6.66';
requires 'Mojo::Pg', '2.30';

requires 'MojoX::NetstringStream', '0.04';

requires 'Pegex', '0.60';

recommends 'Cpanel::JSON::XS', '2.3310';
recommends 'IO::Socket::SSL', '1.94';
recommends 'Net::DNS::Native';
recommends 'JobCenter::Client::Mojo', '0.16';
