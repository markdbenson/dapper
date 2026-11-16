use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Check;

# Links that lead nowhere: target_path and exists_in directly, then whole
# sites through dapper check.

sub link_errors {
    my (%options) = @_;
    my $d = App::Dapper->new();
    $d->{$_} = $options{$_} for keys %options;
    my $report = $d->check();
    return [ map { "$_->{file}: $_->{message}" } grep { $_->{type} eq 'link' } @{ $report->{errors} } ];
}

subtest 'target_path: links that lead outside the site, or nowhere' => sub {
    my $t = \&App::Dapper::Check::target_path;
    is($t->('', '/', ''), undef, 'empty');
    is($t->('   ', '/', ''), undef, 'white space');
    is($t->('#top', '/a/', ''), undef, 'a fragment');
    is($t->('  #top ', '/a/', ''), undef, 'a fragment with spaces');
    is($t->('?page=2', '/a/', ''), undef, 'a query on the same page');
    is($t->('https://other.example/', '/', ''), undef, 'another site');
    is($t->('http://other.example/x', '/', ''), undef, 'http');
    is($t->('//cdn.example/x.js', '/', ''), undef, 'protocol-relative');
    is($t->('mailto:a@b.c', '/', ''), undef, 'mailto');
    is($t->('tel:+15551234', '/', ''), undef, 'tel');
    is($t->('javascript:void(0)', '/', ''), undef, 'javascript');
    is($t->('data:image/png;base64,AAAA', '/', ''), undef, 'data');
    is($t->('MAILTO:X@Y.Z', '/', ''), undef, 'a scheme in capitals');
    is($t->('git+ssh://host/repo', '/', ''), undef, 'a scheme with +');
};

subtest 'target_path: root-relative and relative links' => sub {
    my $t = \&App::Dapper::Check::target_path;
    is($t->('/about.html', '/blog/', ''), '/about.html', 'root-relative');
    is($t->('/', '/blog/', ''), '/', 'the home page');
    is($t->('/blog/', '/', ''), '/blog/', 'a directory keeps its slash');
    is($t->('c.html', '/blog/', ''), '/blog/c.html', 'relative to the page directory');
    is($t->('c.html', '/', ''), '/c.html', 'relative at the top');
    is($t->('./c.html', '/blog/', ''), '/blog/c.html', './');
    is($t->('../b/', '/blog/a/', ''), '/blog/b/', '../');
    is($t->('../../x.png', '/a/b/c/', ''), '/a/x.png', 'two levels up');
    is($t->('../../../../x.png', '/a/', ''), '/x.png', 'cannot go above the top');
    is($t->('..', '/a/b/', ''), '/a', 'just ..');
    is($t->('.', '/a/b/', ''), '/a/b', 'just . (the slash is dropped, which exists_in allows)');
    is($t->('a//b.html', '/', ''), '/a/b.html', 'double slashes collapse');
    is($t->('/a/./b/../c.html', '/', ''), '/a/c.html', 'dots inside a root-relative link');
    is($t->('  /x.html  ', '/', ''), '/x.html', 'spaces around the link');
};

subtest 'target_path: query strings, fragments and encoding' => sub {
    my $t = \&App::Dapper::Check::target_path;
    is($t->('/a.html?x=1', '/', ''), '/a.html', 'query removed');
    is($t->('/a.html#part', '/', ''), '/a.html', 'fragment removed');
    is($t->('/a.html#x?y', '/', ''), '/a.html', 'fragment with a ?');
    is($t->('/a/?q#f', '/', ''), '/a/', 'both, after a directory');
    is($t->('my%20file.txt', '/docs/', ''), '/docs/my file.txt', 'percent-encoded');
    is($t->('%E2%9C%93.html', '/', ''), "/\xE2\x9C\x93.html", 'decoded to bytes');
    is($t->('a%2fb.html', '/', ''), '/a/b.html', 'an encoded slash is a slash');
    is($t->('Tom&amp;Jerry.html', '/', ''), '/Tom&Jerry.html', '&amp; in the HTML is &');
    is($t->('100%.html', '/', ''), '/100%.html', 'a % not followed by hex is kept');
};

subtest 'target_path: absolute links to the site itself' => sub {
    my $t = \&App::Dapper::Check::target_path;
    my $base = 'https://example.com';
    is($t->('https://example.com/x/', '/', $base), '/x/', 'a page');
    is($t->('https://example.com', '/blog/', $base), '/', 'the site URL alone is the home page');
    is($t->('https://example.com/', '/blog/', $base), '/', 'with a slash');
    is($t->('https://example.com/a.html?x#y', '/', $base), '/a.html', 'query and fragment');
    is($t->('https://example.com#top', '/', $base), undef, 'a fragment on the home page URL');
    is($t->('http://example.com/x/', '/', $base), undef, 'another scheme is another site');
    is($t->('https://www.example.com/x/', '/', $base), undef, 'another host');
    is($t->('/x/', '/', $base), '/x/', 'root-relative links still work');
    is($t->('https://example.com/blog/x/', '/', 'https://example.com/blog'), '/x/', 'a site URL with a path');
    is($t->('https://example.com.evil.example/x', '/', $base), undef, 'a host that starts with the site host');
    is($t->('https://example.com/blogroll/', '/', 'https://example.com/blog'), undef,
        'a path that only starts with the site path is outside the site');
};

subtest 'exists_in' => sub {
    make_site({});
    spew('out/a.html', 'x');
    spew('out/dir/index.html', 'x');
    spew('out/old/index.htm', 'x');
    spew('out/empty/other.txt', 'x');
    spew('out/sp ace.txt', 'x');
    my $e = \&App::Dapper::Check::exists_in;
    is($e->('out', '/a.html'), 1, 'a file');
    is($e->('out', '/dir/'), 1, 'a directory with index.html');
    is($e->('out', '/dir'), 1, 'without the slash');
    is($e->('out', '/old/'), 1, 'a directory with index.htm');
    is($e->('out', '/empty/'), 0, 'a directory without an index');
    is($e->('out', '/missing.html'), 0, 'missing');
    is($e->('out', '/sp ace.txt'), 1, 'a space in the name');
    is($e->('out', '/'), 0, 'no top index');
    spew('out/index.html', 'x');
    is($e->('out', '/'), 1, 'top index');
};

subtest 'links in a built site' => sub {
    make_site({
        '_config.yml'        => "---\nname: x\nurl: https://example.com/\n",
        '_layout/index.html' => qq{<html><head><link rel="stylesheet" href="/css/site.css"><script src='/js/app.js'></script></head>\n[% page.content %]</html>},
        '_source/index.md'   => "---\ntitle: Home\n---\n[a](/a.html) [a again](/a.html) [b](blog/b.html) [abs](https://example.com/a.html) [gone abs](https://example.com/nope/)\n",
        '_source/a.md'       => "---\ntitle: A\n---\n[up](./index.html) [frag](#top) [q](/a.html?x=1) [enc](my%20file.txt) <a href=\"missing.html#x\">m</a>\n",
        '_source/blog/b.md'  => "---\ntitle: B\n---\n[rel](../a.html) [dir](../blog/) [img](../img/x.png) ![p](pic.png)\n",
        '_source/my file.txt' => "text",
        '_source/img/x.png'  => "PNG",
        '_source/css/site.css' => "body {}",
    });
    is_deeply(link_errors(), [
        '_source/a.md: links to /js/app.js, which is not in the site',
        '_source/a.md: links to missing.html#x, which is not in the site',
        '_source/blog/b.md: links to /js/app.js, which is not in the site',
        '_source/blog/b.md: links to ../blog/, which is not in the site',
        '_source/blog/b.md: links to pic.png, which is not in the site',
        '_source/index.md: links to /js/app.js, which is not in the site',
        '_source/index.md: links to https://example.com/nope/, which is not in the site',
    ], 'each missing target once per page, pages in output order, links in page order; layouts are checked too; a directory needs an index') or diag explain link_errors();
};

subtest 'links inside comments are not followed' => sub {
    make_site({
        '_source/a.html' => "---\ntitle: A\n---\n<!-- <a href=\"/gone/\">x</a> -->\n<!--[if IE]><script src=\"/ie.js\"></script><![endif]-->\n<!--\nmulti\n<img src=\"/old.png\">\nline -->\n<a href=\"/real-gone/\">y</a>\n",
    });
    is_deeply(link_errors(), ['_source/a.html: links to /real-gone/, which is not in the site'], 'only the live link');
};

subtest 'attribute forms' => sub {
    make_site({
        '_source/a.html' => "---\ntitle: A\n---\n<a HREF=\"/one/\">1</a> <img SRC = '/two.png'> <a href = \"/three/\">3</a> <a data-href=\"/four/\">4</a> <a href=/five/>5</a>\n",
    });
    is_deeply(link_errors(), [
        '_source/a.html: links to /one/, which is not in the site',
        '_source/a.html: links to /two.png, which is not in the site',
        '_source/a.html: links to /three/, which is not in the site',
        '_source/a.html: links to /four/, which is not in the site',
    ], 'any case, spaces around =, single quotes; data-href matches too; unquoted values are not read') or diag explain link_errors();
};

subtest 'only HTML files are read' => sub {
    make_site({
        '_layout/raw.html'  => '[% page.content %]',
        '_source/feed.xml'  => "---\nlayout: raw\nextension: .xml\n---\n<a href=\"/gone/\">x</a>\n",
        '_source/old.htm'   => "---\ntitle: Old\nextension: .htm\n---\n<a href=\"/gone-htm/\">x</a>\n",
        '_source/plain.css' => "a { background: url('/none.png') }\n",
    });
    is_deeply(link_errors(), ['_source/old.htm: links to /gone-htm/, which is not in the site'], '.htm is read; .xml and copied files are not');
};

subtest 'pagefind links are allowed only with search on' => sub {
    my %files = ('_source/a.html' => "---\ntitle: A\n---\n<script src=\"/pagefind/pagefind-ui.js\"></script>\n");
    make_site({ %files });
    is_deeply(link_errors(), ['_source/a.html: links to /pagefind/pagefind-ui.js, which is not in the site'], 'search off: reported');
    make_site({ %files, '_config.yml' => "---\nname: x\nsearch: true\n" });
    is_deeply(link_errors(), [], 'search on: the index is made after the check');
};

subtest 'links to drafts are broken unless drafts are shown' => sub {
    make_site({
        '_source/a.md' => "---\ntitle: A\n---\n[d](/d.html)\n",
        '_source/d.md' => "---\ntitle: D\ndraft: true\n---\nx\n",
    });
    is_deeply(link_errors(), ['_source/a.md: links to /d.html, which is not in the site'], 'held back');
    is_deeply(link_errors(drafts => 1), [], 'with drafts');
};

subtest 'links to generated files' => sub {
    make_site({
        '_config.yml'  => "---\nname: x\nurl: https://example.com\nfeed: true\nredirects:\n  /old/: /blog/2020/01/a/\n",
        '_source/a.md' => "---\ntitle: A\ncategories: blog\ndate: 2020-01-01T00:00:00Z\n---\n[s](/sitemap.xml) [f](/feed.xml) [l](/llms.txt) [o](/old/) [t](index.md)\n",
    });
    is_deeply(link_errors(), [], 'sitemap, feed, llms.txt, redirects and twins exist');
};

subtest 'HTML files copied as they are' => sub {
    make_site({
        '_config.yml'         => "---\nname: x\n",
        '_source/static.html' => "<a href=\"/gone/\">x</a>\n",
    });
    my $errors = link_errors();
    is(scalar @$errors, 1, 'a file without front matter is checked too');
    like($errors->[0], qr{static\.html: links to /gone/, which is not in the site\z}, 'the broken link');
    is_deeply($errors, ['_source/static.html: links to /gone/, which is not in the site'], 'named by its source file');
};

subtest 'a URL with no trailing slash in the site setting' => sub {
    make_site({
        '_config.yml'      => "---\nname: x\nurl: https://example.com/sub\n",
        '_source/a.html'   => "---\ntitle: A\n---\n<a href=\"https://example.com/sub/a.html\">a</a> <a href=\"https://example.com/sub/b.html\">b</a>\n",
    });
    is_deeply(link_errors(), ['_source/a.html: links to https://example.com/sub/b.html, which is not in the site'], 'matched against the site URL');
};

done_testing();
