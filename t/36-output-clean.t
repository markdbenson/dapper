use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Utils;
use Cwd qw(abs_path);
use JSON ();

binmode(Test::More->builder->$_, ':encoding(UTF-8)') for qw(output failure_output todo_output);

sub capture {
    my ($code) = @_;
    my $out = '';
    open(my $fh, '>', \$out) or die;
    my $old = select $fh;
    my $ok = eval { $code->(); 1 };
    my $err = $@;
    select $old;
    die $err unless $ok;
    utf8::decode($out);
    return $out;
}

sub files_under {
    my ($dir) = @_;
    my @files;
    require File::Find;
    File::Find::find({ no_chdir => 1, wanted => sub { push @files, $File::Find::name if -f $_ } }, $dir);
    return [sort map { App::Dapper::Utils::name_chars($_) } @files];
}

sub manifest { JSON->new->decode(slurp('.dapper/manifest.json')) }

subtest 'static files in the source directory' => sub {
    my $binary = join('', map { chr } reverse 0 .. 255) x 3;
    make_site({
        '_source/index.md'          => "---\ntitle: Home\n---\nhi\n",
        '_source/robots.txt'        => "User-agent: *\n",
        '_source/img/deep/logo.svg' => "<svg/>",
        '_source/Zoë café.txt'      => "accent\n",
        '_source/empty.txt'         => '',
        '_source/dashes.txt'        => "----\nnot front matter\n",
        '_source/.hidden.txt'       => "hidden\n",
        '_source/.git/HEAD'         => "ref\n",
        '_source/bom.md'            => "\x{FEFF}---\ntitle: BOM\n---\nbom page\n",
    });
    spew('_source/img/photo.jpg', $binary, ':raw');
    my $d = quiet_build();
    is(slurp('_output/robots.txt'), "User-agent: *\n", 'text file copied');
    is(slurp('_output/img/deep/logo.svg'), '<svg/>', 'nested file copied');
    is(slurp('_output/img/photo.jpg', ':raw'), $binary, 'binary file byte for byte');
    is(slurp(App::Dapper::Utils::name_bytes('_output/Zoë café.txt')), "accent\n", 'Unicode name with a space');
    ok(-f '_output/empty.txt' && -z '_output/empty.txt', 'empty file copied');
    is(slurp('_output/dashes.txt'), "----\nnot front matter\n", 'four dashes is not front matter');
    ok(!-e '_output/.hidden.txt', 'dot files in the source are skipped');
    ok(!-e '_output/.git', 'and dot directories');
    like(slurp('_output/bom.html'), qr{<p>bom page</p>}, 'a byte order mark before front matter makes a page');

    is_deeply([sort map { $_->{source} } @{ $d->{static_files} }],
        [sort '_source/Zoë café.txt', '_source/dashes.txt', '_source/empty.txt', '_source/img/deep/logo.svg',
              '_source/img/photo.jpg', '_source/robots.txt'],
        'static files recorded');
    my %out = map { $_->{source} => $_->{output} } @{ $d->{static_files} };
    is($out{'_source/img/photo.jpg'}, '_output/img/photo.jpg', 'with their output path');
    ok($d->{written}->{'img/photo.jpg'}, 'and remembered as written');

    my $log = capture(sub { App::Dapper->new()->build() });
    like($log, qr{^Copied _source/robots\.txt$}m, 'copies are logged');
};

subtest 'a static file and a page with one output' => sub {
    make_site({
        '_source/a.md'   => "---\ntitle: A\n---\npage\n",
        '_source/a.html' => "static\n",
        '_source/b.md'   => "---\ntitle: B\n---\npage b\n",
        'b.html'         => "top level\n",
        '_layout/index.html' => '[% page.content %]',
    });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    eval { quiet_build() };
    ok($@ || @warnings, 'the clash is reported');
    is(slurp('_output/a.html'), "<p>page</p>\n", 'or at least the page is not replaced by a static file');
    is(slurp('_output/b.html'), "<p>page b</p>\n", 'nor by a top-level file');
};

subtest 'copying the project directory' => sub {
    make_site({
        '_source/index.md'     => "---\ntitle: x\n---\nx\n",
        'css/site.css'         => "body {}\n",
        'css/_partial.css'     => "partial\n",
        'css/.map'             => "map\n",
        'top.txt'              => "top\n",
        '_private/secret.txt'  => "secret\n",
        '.env'                 => "SECRET=1\n",
        'dapper'               => "binary\n",
        'dapper.txt'           => "not the binary\n",
        'my dapper'            => "spaces\n",
        '_data/x.yml'          => "a: 1\n",
    });
    my $d = quiet_build();
    is(slurp('_output/css/site.css'), "body {}\n", 'a directory is copied');
    is(slurp('_output/css/_partial.css'), "partial\n", 'ignore patterns apply only to top-level names');
    is(slurp('_output/css/.map'), "map\n", 'even for dot files below the top');
    is(slurp('_output/top.txt'), "top\n", 'a top-level file');
    ok(!-e '_output/_private', 'names starting with _ are ignored');
    ok(!-e '_output/.env', 'dot files are ignored');
    ok(!-e '_output/dapper', 'a file called dapper is ignored');
    is(slurp('_output/dapper.txt'), "not the binary\n", 'but not dapper.txt');
    is(slurp('_output/my dapper'), "spaces\n", 'nor "my dapper"');
    ok(!-e '_output/_config.yml', 'the project file is not copied');
    ok(!-e '_output/_source' && !-e '_output/_layout' && !-e '_output/_data', 'nor the special directories');
    ok(!-e '_output/_output', 'nor the output directory');
    ok($d->{written}->{'css/site.css'}, 'copied files are remembered');
};

subtest 'custom ignore patterns and directory names' => sub {
    make_site({
        '_config.yml'         => "---\nname: x\nsource: src\nlayout: layouts\noutput: public\ndata_dir: data\nignore: ['^skip', 'tmp']\n",
        'src/index.md'        => "---\ntitle: x\n---\nx\n",
        'layouts/index.html'  => '[% page.content %]',
        'data/a.yml'          => "a: 1\n",
        'skip.txt'            => "s\n",
        'notskip.txt'         => "n\n",
        'mytmpfile'           => "t\n",
        '_private/x.txt'      => "now copied\n",
        '.dotfile'            => "now copied\n",
    });
    quiet_build();
    ok(!-e 'public/skip.txt', 'a custom pattern');
    is(slurp('public/notskip.txt'), "n\n", 'patterns are regular expressions (anchored here)');
    ok(!-e 'public/mytmpfile', 'unanchored patterns match anywhere in the name');
    is(slurp('public/_private/x.txt'), "now copied\n", 'custom patterns replace the defaults');
    is(slurp('public/.dotfile'), "now copied\n", 'including the one for dot files');
    ok(!-e 'public/src' && !-e 'public/layouts' && !-e 'public/data' && !-e 'public/_config.yml',
        'the project directories and file are never copied, whatever they are called');
    ok(!-e 'public/public', 'nor the output directory');

    make_site({
        '_config.yml'   => "---\nname: x\nignore: []\n",
        '_source/a.md'  => "---\n---\nx\n",
        '_extra/x.txt'  => "x\n",
    });
    quiet_build();
    is(slurp('_output/_extra/x.txt'), "x\n", 'an empty ignore list copies everything else');

    make_site({
        '_config.yml'   => "---\nname: x\nignore: ~\n",
        '_source/a.md'  => "---\n---\nx\n",
        '_extra/x.txt'  => "x\n",
    });
    quiet_build();
    is(slurp('_output/_extra/x.txt'), "x\n", 'a null ignore list too');
};

subtest 'copy called directly' => sub {
    make_site({
        '_source/a.md'    => "---\n---\nx\n",
        'assets/one.txt'  => "1\n",
        'assets/sub/two.txt' => "2\n",
        'assets/_three.txt' => "3\n",
    });
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->read_project();
    $d->{written} = {};
    $d->copy('assets', 'elsewhere');
    is_deeply(files_under('elsewhere'), ['elsewhere/one.txt', 'elsewhere/sub/two.txt'], 'ignore patterns apply to the directory given');
    is_deeply([sort keys %{ $d->{written} }], ['../elsewhere/one.txt', '../elsewhere/sub/two.txt'],
        'files outside the output directory are recorded relative to it');
};

subtest 'clean_output and the manifest' => sub {
    make_site({
        '_source/keep.md'          => "---\ntitle: Keep\n---\nx\n",
        '_source/a/b/c/gone.md'    => "---\ntitle: Gone\n---\nx\n",
        '_source/a/stay.txt'       => "stay\n",
        '_source/one.md'           => "---\ntitle: One\n---\nx\n",
    });
    my $out = capture(sub { App::Dapper->new()->build() });
    unlike($out, qr/Removed/, 'nothing removed on the first build');
    my $output = abs_path('_output');
    my $m = manifest();
    is_deeply([keys %$m], [$output], 'the manifest is keyed by the absolute output directory');
    is_deeply($m->{$output}, [sort qw(a/b/c/gone.html a/b/c/gone.md a/stay.txt keep.html keep.md
        llms-full.txt llms.txt one.html one.md)], 'every file written, sorted, relative to the output');
    like(slurp('.dapper/manifest.json'), qr/^\{\n   "/, 'pretty printed');

    unlink '_source/a/b/c/gone.md', '_source/one.md';
    spew('_output/a/b/c/mine.txt', "mine\n");
    $out = capture(sub { App::Dapper->new()->build() });
    like($out, qr/^Removed 4 files left over from an earlier build$/m, 'the count of removed files');
    ok(!-e '_output/a/b/c/gone.html' && !-e '_output/one.html', 'removed');
    ok(-f '_output/a/b/c/mine.txt', 'a file Dapper did not write stays');
    ok(-d '_output/a/b/c', 'so its directory stays');

    unlink '_output/a/b/c/mine.txt';
    spew('_source/a/b/c/gone.md', "---\ntitle: Back\n---\nx\n");
    quiet_build();
    unlink '_source/a/b/c/gone.md';
    $out = capture(sub { App::Dapper->new()->build() });
    like($out, qr/^Removed 2 files left over/m, 'plural');
    ok(!-e '_output/a/b', 'empty directories removed, deepest first');
    ok(-d '_output/a', 'but not one that still has files');

    unlink '_source/a/stay.txt';
    $out = capture(sub { App::Dapper->new()->build() });
    like($out, qr/^Removed 1 file left over from an earlier build$/m, 'singular');
    ok(!-e '_output/a', 'the last directory goes too');
};

subtest 'the manifest is only trusted so far' => sub {
    make_site({ '_source/a.md' => "---\ntitle: A\n---\nx\n", '_keep/outside.txt' => "precious\n" });
    quiet_build();
    my $output = abs_path('_output');
    my $outside = abs_path('_keep/outside.txt');
    mkdir '_output/somedir';
    my $m = manifest();
    push @{ $m->{$output} }, '../_keep/outside.txt', 'x/../../_keep/outside.txt', $outside, 'missing.txt', 'somedir';
    $m->{'/some/other/output'} = ['other.html'];
    App::Dapper::Utils::write_file('.dapper/manifest.json', JSON->new->encode($m));
    quiet_build();
    is(slurp('_keep/outside.txt'), "precious\n", 'paths outside the output directory are never removed');
    ok(-d '_output/somedir', 'directories are never removed directly');
    is_deeply(manifest()->{'/some/other/output'}, ['other.html'], 'entries for other output directories are kept');
    is_deeply(manifest()->{$output}, [qw(a.html a.md llms-full.txt llms.txt)], 'and this one is replaced');

    App::Dapper::Utils::write_file('.dapper/manifest.json', '{not json');
    eval { quiet_build() };
    is($@, '', 'a broken manifest is not an error');
    is_deeply([keys %{ manifest() }], [$output], 'and is replaced');

    App::Dapper::Utils::write_file('.dapper/manifest.json', '["a.html"]');
    quiet_build();
    is(ref manifest(), 'HASH', 'a manifest that is not a hash is replaced');

    App::Dapper::Utils::write_file('.dapper/manifest.json', JSON->new->encode({ $output => 'not a list' }));
    quiet_build();
    ok(-f '_output/a.html', 'an entry that is not a list removes nothing');
    is(ref manifest()->{$output}, 'ARRAY', 'and is replaced');
};

subtest 'clean: false and collect mode' => sub {
    make_site({ '_config.yml' => "---\nname: x\nclean: false\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    quiet_build();
    ok(!-e '.dapper/manifest.json', 'no manifest with clean: false');
    rename '_source/a.md', '_source/b.md';
    quiet_build();
    ok(-f '_output/a.html' && -f '_output/b.html', 'nothing removed');

    make_site({ '_config.yml' => "---\nname: x\nclean: 'no'\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    quiet_build();
    ok(!-e '.dapper/manifest.json', 'clean: no');

    make_site({ '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    quiet_build();
    rename '_source/a.md', '_source/b.md';
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{collect} = 1;
    $d->build();
    ok(-f '_output/a.html', 'nothing removed when collecting problems');
    is_deeply(manifest()->{abs_path('_output')}, [qw(a.html a.md llms-full.txt llms.txt)], 'and the manifest is untouched');
};

subtest 'live reload' => sub {
    make_site({
        '_source/a.md'      => "---\ntitle: A\n---\nx\n",
        '_source/upper.md'  => "---\nlayout: upper\n---\nx\n",
        '_source/twice.md'  => "---\nlayout: twice\n---\nx\n",
        '_source/nobody.md' => "---\nlayout: bare\n---\nx\n",
        '_source/old.md'    => "---\nlayout: bare\nextension: .htm\n---\nx\n",
        '_source/data.json' => "---\nlayout: bare\nextension: .json\n---\n{}\n",
        '_layout/index.html' => "<html><body>[% page.content %]</body></html>",
        '_layout/upper.html' => "<HTML><BODY>B</BODY></HTML>",
        '_layout/twice.html' => "<body>1</body><body>2</body>",
        '_layout/bare.html'  => "[% page.content %]",
    });
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{live_reload} = 1;
    $d->build();
    my $script = App::Dapper::live_reload_script();
    like($script, qr{^<script>\n.*fetch\('/\.dapper-reload\?' \+ Date\.now\(\).*location\.reload\(\).*setTimeout\(poll, 1000\).*</script>\n\z}s,
        'the script polls /.dapper-reload every second');
    is(slurp('_output/a.html'), "<html><body><p>x</p>\n${script}</body></html>", 'inserted right before </body>');
    is(slurp('_output/upper.html'), "<HTML><BODY>B${script}</BODY></HTML>", 'case-insensitive');
    is(slurp('_output/twice.html'), "<body>1${script}</body><body>2</body>", 'only once');
    is(slurp('_output/nobody.html'), "<p>x</p>\n${script}", 'appended without a </body>');
    is(slurp('_output/old.htm'), "<p>x</p>\n${script}", '.htm is HTML too');
    is(slurp('_output/data.json'), "{}\n", 'other files are left alone');
    like(slurp('_output/.dapper-reload'), qr/^\d+-\d+\n\z/, 'the marker');
    ok($d->{written}->{'.dapper-reload'}, 'is remembered as written');
    ok(!-e '_output/a.md' || slurp('_output/a.md') !~ /dapper-reload/, 'not in the Markdown copy');
};

subtest 'generated files and pages that write the same file' => sub {
    make_site({
        '_config.yml'         => "---\nname: x\nurl: https://example.com\nfeed: true\nredirects:\n  /old/: /a.html\n  /a.html: /b/\n",
        '_source/a.md'        => "---\ntitle: A\ndate: 2014-01-01\n---\nx",
        '_source/sitemap.xml' => "---\nextension: .xml\nlayout: raw\n---\nmine",
        '_source/llms.txt'    => "---\nextension: .txt\nlayout: raw\n---\nmy llms",
        '_layout/raw.html'    => "[% page.content %]",
    });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my $d = quiet_build();
    is_deeply([sort @warnings], [
        "warning: a page in the source directory already writes _output/llms.txt, so Dapper did not generate one\n",
        "warning: a page in the source directory already writes _output/sitemap.xml, so Dapper did not generate one\n",
        "warning: a page is still at /a.html, so the redirect from it to /b/ was not written\n",
    ], 'a warning for each clash');
    is(slurp('_output/sitemap.xml'), 'mine', 'the page wins over the sitemap');
    is(slurp('_output/llms.txt'), 'my llms', 'and over llms.txt');
    ok(-f '_output/llms-full.txt', 'llms-full.txt is still generated');
    ok(-f '_output/feed.xml', 'the feed is generated');
    like(slurp('_output/old/index.html'), qr{/a\.html}, 'the redirect that does not clash is written');
    is($d->{page_owner}->{'_output/old/index.html'}, 'the redirect from /old/', 'and owns its file');
    is($d->{page_owner}->{'_output/sitemap.xml'}, '_source/sitemap.xml', 'pages own theirs');

    @warnings = ();
    $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{collect} = 1;
    $d->build();
    is_deeply([sort map { "$_->{severity}: $_->{file}" } @{ $d->{problems} }],
        ['warning: _output/a.html', 'warning: _output/llms.txt', 'warning: _output/sitemap.xml'], 'collected as warnings');
    is_deeply(\@warnings, [], 'not printed when collecting');
};

subtest 'generated files that need the site address' => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    make_site({ '_config.yml' => "---\nname: x\nsitemap: true\n", '_source/a.md' => "---\n---\nx" });
    quiet_build();
    is_deeply(\@warnings, ["warning: the sitemap needs the site's address; set url in _config.yml\n"], 'a sitemap asked for');
    ok(!-e '_output/sitemap.xml', 'is not written without url');

    @warnings = ();
    make_site({ '_source/a.md' => "---\n---\nx" });
    quiet_build();
    is_deeply(\@warnings, [], 'the default sitemap setting stays quiet');

    @warnings = ();
    make_site({ '_config.yml' => "---\nname: x\nurl: ''\nfeed: true\n", '_source/a.md' => "---\n---\nx" });
    quiet_build();
    is_deeply(\@warnings, ["warning: the feed needs the site's address; set url in _config.yml\n"], 'a feed with an empty url');

    @warnings = ();
    make_site({ 'site.yml' => "---\nname: x\nfeed: true\n", '_source/a.md' => "---\n---\nx" });
    quiet_build(undef, undef, undef, 'site.yml');
    is_deeply(\@warnings, ["warning: the feed needs the site's address; set url in site.yml\n"], 'names the project file');
};

subtest 'two pages writing one file' => sub {
    make_site({
        '_source/a.md'   => "---\ntitle: A\n---\nx",
        '_source/a.html' => "---\ntitle: A2\n---\nx",
    });
    eval { quiet_build() };
    is($@, "error: _source/a.md and _source/a.html both write _output/a.html\n", 'source files with different extensions');

    make_site({
        '_source/x/index.md' => "---\ntitle: X\n---\nx",
        '_source/y.md'       => "---\ntitle: Y\nurlpattern: /x/\n---\nx",
    });
    eval { quiet_build() };
    is($@, "error: _source/y.md and _source/x/index.md both write _output/x/index.html\n", 'a urlpattern and a path');

    make_site({
        '_source/a.md'   => "---\ntitle: A\n---\nx",
        '_source/a.html' => "---\ntitle: A2\n---\nx",
    });
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{collect} = 1;
    $d->build();
    is_deeply($d->{problems}, [{ severity => 'error', file => '_source/a.md',
        message => '_source/a.md and _source/a.html both write _output/a.html' }], 'collected');
};

subtest 'write_output and record_written' => sub {
    make_site({ '_source/a.md' => "---\n---\nx" });
    my $d = App::Dapper->new();
    $d->read_project();
    $d->{written} = {};
    $d->write_output('_output/deep/dir/file.txt', "Zoë\n");
    is(slurp('_output/deep/dir/file.txt'), "Zoë\n", 'written');
    $d->record_written('_output/x.txt', '_output/./y/z.txt', 'elsewhere/w.txt');
    is_deeply([sort keys %{ $d->{written} }], [sort 'deep/dir/file.txt', 'x.txt', 'y/z.txt', '../elsewhere/w.txt'],
        'relative to the output directory, with / separators');
};

subtest 'snapshot and _same_snapshot' => sub {
    make_site({
        '_config.yml'      => "---\nname: x\noutput: public\n",
        '_source/index.md' => "---\ntitle: x\n---\nHi\n",
        '.hidden'          => "x\n",
        'dir/.dotfile'     => "x\n",
        'dir/file.txt'     => "12345",
        '_output/stale.txt' => "not the output any more\n",
    });
    my $d = quiet_build();
    my $snap = $d->snapshot();
    ok(!grep({ m{^\./public/} } keys %$snap), 'the configured output directory is not watched');
    ok(exists $snap->{'./_output/stale.txt'}, 'an old output directory is just a directory');
    ok(!exists $snap->{'./.hidden'} && !exists $snap->{'./dir/.dotfile'}, 'dot files are not watched');
    my @stat = stat 'dir/file.txt';
    is($snap->{'./dir/file.txt'}, "$stat[9]:5", 'mtime and size');
    ok(!exists $snap->{'./dir'}, 'directories are not listed');

    ok(App::Dapper::_same_snapshot($snap, $d->snapshot()), 'unchanged');
    ok(App::Dapper::_same_snapshot({}, {}), 'two empty snapshots');
    ok(!App::Dapper::_same_snapshot({ a => '1:1' }, { a => '1:2' }), 'a changed size');
    ok(!App::Dapper::_same_snapshot({ a => '1:1' }, { a => '2:1' }), 'a changed time');
    ok(!App::Dapper::_same_snapshot({ a => '1:1' }, { b => '1:1' }), 'a renamed file');
    ok(!App::Dapper::_same_snapshot({ a => '1:1' }, {}), 'a removed file');
    ok(!App::Dapper::_same_snapshot({}, { a => '1:1' }), 'an added file');
    ok(!App::Dapper::_same_snapshot({ a => '1:1', b => '1:1' }, { a => '1:1', c => '1:1' }), 'same count, different files');

    spew('dir/file.txt', '1234567');
    ok(!App::Dapper::_same_snapshot($snap, $d->snapshot()), 'an edited file is a change');
    unlink 'dir/file.txt';
    ok(!App::Dapper::_same_snapshot($snap, $d->snapshot()), 'a deleted file is a change');

    my $fresh = App::Dapper->new();
    ok(!exists $fresh->snapshot()->{'./_output/stale.txt'}, 'before a build the default output directory is skipped');
    ok(exists $fresh->snapshot()->{'./public/index.html'}, 'and the configured one is not known yet');
};

done_testing();
