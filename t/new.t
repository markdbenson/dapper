use strict;
use Test;

BEGIN { plan tests => 5 }

use Text::Dapper;

print "# I'm testing Text::Dapper->new()\n";

my $d = Text::Dapper->new();
ok($d->{source}, "_source");
ok($d->{layout}, "_layout");
ok($d->{output}, "_output");
ok($d->{config}, "_config");
ok(1);

