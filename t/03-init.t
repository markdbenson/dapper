use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

make_site({}, bare => 1);

my $d = App::Dapper->new();
$d->{quiet} = 1;
{
    local *STDOUT;
    open(STDOUT, '>', \my $ignored);
    $d->init();
}

ok(-f "_config.yml", "init creates _config.yml");
ok(-f "_source/index.md", "init creates _source/index.md");
ok(-f "_layout/index.html", "init creates _layout/index.html");
like(slurp("_layout/index.html"), qr/<meta charset="utf-8">/, "starter layout declares UTF-8");

my $before = slurp("_config.yml");
eval {
    local *STDOUT;
    open(STDOUT, '>', \my $ignored);
    App::Dapper->new()->init();
};
like($@, qr/already exist/, "init refuses to overwrite an existing project");
is(slurp("_config.yml"), $before, "existing config file is untouched");

quiet_build();
my $index = slurp("_output/index.html");
like($index, qr{<title>Welcome</title>}, "built page has the title");
like($index, qr{<p>Hello world.</p>}, "built page has the rendered markdown");

done_testing();
