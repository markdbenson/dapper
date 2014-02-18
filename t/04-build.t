use strict;
use Test;

BEGIN { plan tests => 7 }

chdir ("t");
mkdir("_tmp");
chdir ("_tmp");
system("../../bin/dapper init");

ok(-f "_config.yml");
ok(-d "_source");
ok(-f "_source/index.md");
ok(-d "_layout");
ok(-f "_layout/index.html");

system("../../bin/dapper build");

ok(-d "_output");
ok(-f "_output/index.html");

system("rm _config.yml");
system("rm -rf _source");
system("rm -rf _layout");
system("rm -rf _output");
chdir("..");
system("rm -rf _tmp");

