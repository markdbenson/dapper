use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

subtest 'files left over from earlier builds are removed' => sub {
    make_site({
        '_source/keep.md'      => "---\ntitle: Keep\n---\nx\n",
        '_source/old/gone.md'  => "---\ntitle: Gone\n---\nx\n",
        'assets/old.css'       => "old\n",
    });
    quiet_build();
    ok(-f '_output/old/gone.html', 'written by the first build');
    spew('_output/CNAME', "example.com\n");
    mkdir '_output/.git';
    spew('_output/.git/HEAD', "ref\n");

    unlink '_source/old/gone.md', 'assets/old.css';
    rmdir '_source/old';
    quiet_build();
    ok(!-e '_output/old/gone.html', 'output of a deleted page removed');
    ok(!-e '_output/old', 'and its now-empty directory');
    ok(!-e '_output/assets/old.css', 'a deleted copied file removed');
    ok(-f '_output/keep.html', 'current output kept');
    ok(-f '_output/CNAME', 'files Dapper did not write are never removed');
    ok(-f '_output/.git/HEAD', 'nor directories');
    ok(-f '.dapper/manifest.json', 'manifest kept in the project, not the output');
};

subtest 'clean: false' => sub {
    make_site({ '_config.yml' => "---\nname: x\nclean: false\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    quiet_build();
    rename '_source/a.md', '_source/b.md';
    quiet_build();
    ok(-f '_output/a.html', 'old output stays');
};

subtest 'live reload' => sub {
    make_site({
        '_source/a.md' => "---\ntitle: A\n---\nx\n",
        '_source/feed.xml' => "---\nlayout: raw\nextension: .xml\n---\n<feed/>\n",
        '_layout/index.html' => "<html><body>[% page.content %]</body></html>",
        '_layout/raw.html' => "[% page.content %]",
    });
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{live_reload} = 1;
    $d->build();
    like(slurp('_output/a.html'), qr{/\.dapper-reload.*</script>\n</body>}s, 'script added before </body>');
    unlike(slurp('_output/feed.xml'), qr/dapper-reload/, 'not in non-HTML files');
    ok(-f '_output/.dapper-reload', 'marker written');
    my $first = slurp('_output/.dapper-reload');

    quiet_build();
    unlike(slurp('_output/a.html'), qr/dapper-reload/, 'not added by a normal build');
    ok(!-e '_output/.dapper-reload', 'and the marker is cleaned up');
};

subtest 'two pages cannot write one file' => sub {
    make_site({
        '_source/a.md' => "---\ntitle: A\nurlpattern: /same.html\n---\nx\n",
        '_source/b.md' => "---\ntitle: B\nurlpattern: /same.html\n---\nx\n",
    });
    eval { quiet_build() };
    like($@, qr{_source/b\.md and _source/a\.md both write _output/same\.html}, 'clear error');
};

done_testing();
