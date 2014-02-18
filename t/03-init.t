use strict;
use Test;

BEGIN { plan tests => 5 }

chdir ("t");
mkdir("_tmp");
chdir ("_tmp");
system("../../bin/dapper init");

ok(-f "_config.yml");
ok(-d "_source");
ok(-f "_source/index.md");
ok(-d "_layout");
ok(-f "_layout/index.html");

system("rm _config.yml");
system("rm -rf _source");
system("rm -rf _layout");
chdir("..");
system("rm -rf _tmp");

