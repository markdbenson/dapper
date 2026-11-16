use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Publish;

# Redirects: where they come from, the file each is written to, the page
# itself, and the errors.

sub redirects {
    my $r = eval { App::Dapper::Publish::redirects($_[0]) };
    return ($r, $@);
}

subtest 'redirects: sources' => sub {
    my ($r, $e) = redirects({});
    is_deeply($r, {}, 'none');
    ($r) = redirects({ redirects => { '/a/' => '/b/' } });
    is_deeply($r, { '/a/' => '/b/' }, 'from _config.yml');
    ($r) = redirects({ data => { redirects => { '/c/' => '/d/' } } });
    is_deeply($r, { '/c/' => '/d/' }, 'from _data/redirects.yml');
    ($r) = redirects({ redirects => { '/a/' => '/config/', '/x/' => '/y/' }, data => { redirects => { '/a/' => '/data/' } } });
    is_deeply($r, { '/a/' => '/data/', '/x/' => '/y/' }, 'both, and the data file wins');
    ($r) = redirects({ data => 'not a hash', redirects => { '/a/' => '/b/' } });
    is_deeply($r, { '/a/' => '/b/' }, 'site.data that is not a hash is ignored');
    ($r, $e) = redirects({ redirects => {} });
    is_deeply($r, {}, 'an empty map');
    ($r) = redirects({ redirects => { '/a/' => 'https://elsewhere.example/' } });
    is_deeply($r, { '/a/' => 'https://elsewhere.example/' }, 'to another site');
    ($r) = redirects({ redirects => { '/a/' => 'b.html' } });
    is_deeply($r, { '/a/' => 'b.html' }, 'the new URL may be relative');
};

subtest 'redirects: errors' => sub {
    my $pairs = "error: redirects must be pairs of an old URL and a new one, e.g. /old/: /new/\n";
    my (undef, $e) = redirects({ redirects => ['/a/', '/b/'] });
    is($e, $pairs, 'a list in _config.yml');
    (undef, $e) = redirects({ redirects => '/a/ /b/' });
    is($e, $pairs, 'a string in _config.yml');
    (undef, $e) = redirects({ data => { redirects => ['/a/'] } });
    is($e, $pairs, 'a list in the data file');
    (undef, $e) = redirects({ redirects => { '/a/' => undef } });
    is($e, "error: the redirect from /a/ must go to a URL\n", 'no new URL');
    (undef, $e) = redirects({ redirects => { '/a/' => '' } });
    is($e, "error: the redirect from /a/ must go to a URL\n", 'an empty new URL');
    (undef, $e) = redirects({ redirects => { '/a/' => ['/b/'] } });
    is($e, "error: the redirect from /a/ must go to a URL\n", 'a list as the new URL');
    (undef, $e) = redirects({ redirects => { 'old.html' => '/new.html' } });
    is($e, "error: the redirect from old.html must start with /\n", 'the old URL must start with /');
    (undef, $e) = redirects({ redirects => { 'https://e.example/old' => '/new.html' } });
    is($e, "error: the redirect from https://e.example/old must start with /\n", 'even a full URL');
};

subtest 'redirect_path' => sub {
    my $p = \&App::Dapper::Publish::redirect_path;
    is($p->('/old/'), 'old/index.html', 'directory');
    is($p->('/old'), 'old/index.html', 'no slash');
    is($p->('/old.html'), 'old.html', 'a file');
    is($p->('/old.php'), 'old.php', 'any extension');
    is($p->('/a/b/c/'), 'a/b/c/index.html', 'nested');
    is($p->('/v1.2/page'), 'v1.2/page/index.html', 'a dot in a directory is not an extension');
    is($p->('/'), 'index.html', 'the home page');
    is($p->('//double/'), 'double/index.html', 'leading slashes removed');
    is($p->('/.hidden'), '.hidden', 'a dot file counts as having an extension');
};

subtest 'redirect_page' => sub {
    is(App::Dapper::Publish::redirect_page({ url => 'https://example.com/' }, '/new/'), <<'HTML', 'exact page');
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>This page has moved</title>
  <link rel="canonical" href="https://example.com/new/">
  <meta name="robots" content="noindex">
  <meta http-equiv="refresh" content="0; url=/new/">
</head>
<body>
  <p>This page has moved to <a href="/new/">/new/</a>.</p>
</body>
</html>
HTML
    my $page = App::Dapper::Publish::redirect_page({}, '/a?x=1&y="2"');
    like($page, qr{<link rel="canonical" href="/a\?x=1&amp;y=&quot;2&quot;">}, 'relative canonical without url, escaped');
    like($page, qr{content="0; url=/a\?x=1&amp;y=&quot;2&quot;"}, 'refresh escaped');
    like($page, qr{<a href="/a\?x=1&amp;y=&quot;2&quot;">/a\?x=1&amp;y=&quot;2&quot;</a>}, 'link escaped');
    like(App::Dapper::Publish::redirect_page({ url => 'https://example.com' }, 'https://other.example/'),
        qr{<link rel="canonical" href="https://other\.example/">}, 'another site stays as it is');
};

subtest 'redirects in a build' => sub {
    make_site({
        '_config.yml'         => "---\nname: x\nurl: https://example.com\nredirects:\n  /a/: /new.html\n  /b.html: /new.html\n  /c: /new.html\n",
        '_data/redirects.yml' => "/a/: /from-data.html\n/d/e/: /new.html\n",
        '_source/new.md'      => "---\ntitle: New\n---\nx\n",
        '_source/from-data.md' => "---\ntitle: From data\n---\nx\n",
    });
    my $d = quiet_build();
    is(slurp('_output/a/index.html'), App::Dapper::Publish::redirect_page($d->{site}, '/from-data.html'), 'data file wins');
    is(slurp('_output/b.html'), App::Dapper::Publish::redirect_page($d->{site}, '/new.html'), 'a file');
    ok(-f '_output/c/index.html', 'no slash');
    ok(-f '_output/d/e/index.html', 'nested');
    my $sitemap = slurp('_output/sitemap.xml');
    unlike($sitemap, qr{/a/|/b\.html|/c/|/d/e/}, 'not in the sitemap');
    ok(!-e '_output/a/index.md', 'no twin');
};

subtest 'build errors' => sub {
    make_site({ '_config.yml' => "---\nname: x\nredirects: [/a/, /b/]\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    eval { quiet_build() };
    is($@, "error: redirects must be pairs of an old URL and a new one, e.g. /old/: /new/\n", 'not pairs');

    make_site({ '_config.yml' => "---\nname: x\nredirects:\n  /a/:\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    eval { quiet_build() };
    is($@, "error: the redirect from /a/ must go to a URL\n", 'no target');
};

subtest 'check: redirect errors, and redirects to nowhere' => sub {
    make_site({ '_config.yml' => "---\nname: x\nredirects:\n  old.html: /a.html\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    my $report = App::Dapper->new()->check();
    is_deeply([ map { "$_->{type} $_->{file}: $_->{message}" } @{ $report->{errors} } ],
        ['other _config.yml: the redirect from old.html must start with /'], 'reported against _config.yml');

    make_site({
        '_config.yml'  => "---\nname: x\nurl: https://example.com\nredirects:\n  /ok/: /a.html\n  /abs/: https://example.com/missing.html\n  /ext/: https://elsewhere.example/\n  /rel/: nope.html\n",
        '_source/a.md' => "---\ntitle: A\n---\nx\n",
    });
    $report = App::Dapper->new()->check();
    is_deeply([ map { "$_->{type} $_->{file}: $_->{message}" } @{ $report->{errors} } ], [
        'link the redirect from /abs/: links to https://example.com/missing.html, which is not in the site',
        'link the redirect from /rel/: links to https://example.com/nope.html, which is not in the site',
        'link the redirect from /rel/: links to nope.html, which is not in the site',
    ], 'absolute links to the site are checked, other sites ignored; a relative target is reported for its canonical link and its link')
        or diag explain $report->{errors};
};

subtest 'a page at the old URL wins over the redirect' => sub {
    make_site({
        '_config.yml'      => "---\nname: x\nredirects:\n  /a/: /b.html\n",
        '_source/a/index.md' => "---\ntitle: A\n---\nStill here\n",
        '_source/b.md'     => "---\ntitle: B\n---\nx\n",
    });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    like(slurp('_output/a/index.html'), qr/Still here/, 'page kept');
    is_deeply(\@warnings, ["warning: a page is still at /a/, so the redirect from it to /b.html was not written\n"], 'exact warning');
};

done_testing();
