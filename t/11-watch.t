use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

make_site({
    '_source/index.md' => "---\ntitle: x\n---\nHi\n",
    'css/site.css'     => "body {}\n",
    '.git/HEAD'        => "ref\n",
});

my $d = quiet_build();
my $snapshot = $d->snapshot();

ok(exists $snapshot->{'./_config.yml'}, 'the config file is watched');
ok(exists $snapshot->{'./_source/index.md'}, 'source files are watched');
ok(exists $snapshot->{'./_layout/index.html'}, 'layout files are watched');
ok(exists $snapshot->{'./css/site.css'}, 'copied files are watched');
ok(!grep({ m{^\./_output/} } keys %$snapshot), 'the output directory is not watched');
ok(!grep({ m{^\./\.git/} } keys %$snapshot), 'dot directories are not watched');

spew('_source/new.md', "---\ntitle: new\n---\nNew\n");
ok(!App::Dapper::_same_snapshot($snapshot, $d->snapshot()), 'a new file is a change');

done_testing();
