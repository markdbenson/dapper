use 5.14.0;
use strict;
use Test;

BEGIN { plan tests => 5 }

use App::Dapper;

print "# I'm testing App::Dapper->new()\n";

my $d = App::Dapper->new("t/_source", "t/_output", "t/_layout", "t/_config.yml");
ok($d->{source}, "t/_source", "Test default source directory");
ok($d->{layout}, "t/_layout", "Test default layout directory");
ok($d->{output}, "t/_output", "Test default output director");
ok($d->{config}, "t/_config.yml", "Test defult config file name");
ok(1);

#$d->init();

