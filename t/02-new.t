use 5.010;
use strict;
use warnings;
use Test::More;

use App::Dapper;

my $d = App::Dapper->new("t/_source", "t/_output", "t/_layout", "t/_config.yml");
is($d->{source}, "t/_source", "explicit source directory");
is($d->{layout}, "t/_layout", "explicit layout directory");
is($d->{output}, "t/_output", "explicit output directory");
is($d->{config}, "t/_config.yml", "explicit config file name");

my $defaults = App::Dapper->new();
is($defaults->{source}, "_source", "default source directory");
is($defaults->{layout}, "_layout", "default layout directory");
is($defaults->{output}, "_output", "default output directory");
is($defaults->{config}, "_config.yml", "default config file name");
isa_ok($defaults->{site}->{time}, 'DateTime', 'site.time');

done_testing();
