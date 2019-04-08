#
# include all modules that our plperl function may use here
#

# you might need the local::lib of your jobcenter user
#use lib '/home/jobcenter/perl5/lib/perl5';

use Safe;
# older versions do not have the required from_json to_json
use JSON::MaybeXS 1.003_000;

# you do need this:
use lib "/home/jobcenter/jobcenter/lib";

use JobCenter::Safe;

1;
