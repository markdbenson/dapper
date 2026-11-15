use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;
use JSON ();

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Publish;
use App::Dapper::Utils;

# The small helpers in App::Dapper::Publish, Markdown twins, llms.txt and
# llms-full.txt.

sub date { App::Dapper::Utils::parse_date($_[0]) }

subtest 'absolute_url' => sub {
    my $a = \&App::Dapper::Publish::absolute_url;
    my $site = { url => 'https://example.com' };
    is($a->($site, '/about/'), 'https://example.com/about/', 'root-relative');
    is($a->($site, 'about/'), 'https://example.com/about/', 'a slash is added');
    is($a->($site, '/'), 'https://example.com/', 'the home page');
    is($a->({ url => 'https://example.com/' }, '/a.html'), 'https://example.com/a.html', 'trailing slash on the site URL');
    is($a->({ url => 'https://example.com///' }, '/a.html'), 'https://example.com/a.html', 'several trailing slashes');
    is($a->({ url => 'https://example.com/blog' }, '/a/'), 'https://example.com/blog/a/', 'a site URL with a path');
    is($a->($site, 'https://other.example/x'), 'https://other.example/x', 'already absolute');
    is($a->($site, 'mailto:a@b.c'), 'mailto:a@b.c', 'another scheme');
    is($a->($site, 'HTTP://X.EXAMPLE/'), 'HTTP://X.EXAMPLE/', 'scheme in capitals');
    is($a->($site, 'svn+ssh://x/'), 'svn+ssh://x/', 'scheme with + in it');
    is($a->($site, ''), '', 'empty stays empty');
    is($a->($site, undef), undef, 'undef stays undef');
    is($a->({}, '/a/'), '/a/', 'no site URL: unchanged');
    is($a->({ url => '' }, '/a/'), '/a/', 'empty site URL: unchanged');
    is($a->({}, 'a/'), 'a/', 'no site URL: no slash added either');
};

subtest 'plain_text' => sub {
    my $p = \&App::Dapper::Publish::plain_text;
    is($p->(undef), '', 'undef');
    is($p->(''), '', 'empty');
    is($p->('<p>Hello <em>there</em>.</p>'), 'Hello there.', 'tags removed');
    is($p->("  a\n\n\tb   c  "), 'a b c', 'white space collapsed and trimmed');
    is($p->('&lt;b&gt; &amp; &quot;q&quot; &#39;s&#39;&nbsp;x'), qq{<b> & "q" 's' x}, 'entities decoded');
    is($p->('&amp;lt;'), '&lt;', '&amp; is decoded last, so it is not decoded twice');
    is($p->('<img src="x.png" alt="A">'), '', 'an image has no text');
    is($p->('a<br>b'), 'ab', 'tags are removed without a space');
    is($p->('caf&eacute;'), 'caf&eacute;', 'other entities are left alone');
    is($p->("é <b>ü</b>"), 'é ü', 'characters kept');
};

subtest 'description' => sub {
    my $d = \&App::Dapper::Publish::description;
    is($d->({ description => 'Mine.' }), 'Mine.', 'from front matter');
    is($d->({ description => 'Mine.', excerpt => '<p>Excerpt.</p>' }), 'Mine.', 'front matter wins over the excerpt');
    is($d->({ excerpt => '<p>First &amp; <em>best</em>.</p>' }), 'First & best.', 'from the excerpt, as text');
    is($d->({ description => ['a'], excerpt => '<p>E.</p>' }), 'E.', 'a description that is a list is ignored');
    is($d->({ description => { a => 1 } }), '', 'a description that is a map is ignored, and no excerpt is empty');
    is($d->({}), '', 'nothing at all');
    is($d->({ description => '' }), '', 'an empty description');

    my $exact = 'x' x 200;
    is($d->({ description => $exact }), $exact, '200 characters is not shortened');
    is($d->({ description => 'x' x 201 }), ('x' x 200) . '...', 'one word longer than the limit is cut and gets ...');

    my $words = join(' ', ('word') x 50);
    my $short = $d->({ description => $words });
    is($short, join(' ', ('word') x 40) . '...', 'cut at a word boundary');
    is(length $short, 202, 'about 200 characters');

    my $mid = ('abcdefghi ' x 19) . 'abcdefghijklmnopqrstuvwxyz';
    is($d->({ description => $mid }), join(' ', ('abcdefghi') x 19) . '...', 'a word cut in half is dropped');

    my $ends_on_word = ('x' x 195) . ' abcd efgh';
    is($d->({ description => $ends_on_word }), ('x' x 195) . '...', 'the cut falls at the end of a word, and that word is dropped too');
};

subtest 'is_html' => sub {
    my $h = \&App::Dapper::Publish::is_html;
    ok($h->({ filename => '_output/a.html' }), '.html');
    ok($h->({ filename => '_output/a.htm' }), '.htm');
    ok($h->({ filename => '_output/A.HTML' }), 'any case');
    ok(!$h->({ filename => '_output/feed.xml' }), '.xml');
    ok(!$h->({ filename => '_output/a.html.bak' }), '.html.bak');
    ok(!$h->({ filename => '_output/html' }), 'no extension');
    ok(!$h->({}), 'no filename');
};

subtest 'enabled' => sub {
    my $e = \&App::Dapper::Publish::enabled;
    ok($e->({}, 'x'), 'not set: on');
    ok($e->({ x => undef }, 'x'), 'undef: on');
    for my $off (0, '0', '', 'false', 'FALSE', 'no', 'No', 'off', 'OFF') {
        ok(!$e->({ x => $off }, 'x'), "'$off' is off");
    }
    for my $on (1, 'true', 'yes', 'on', 'anything', '00', ' false') {
        ok($e->({ x => $on }, 'x'), "'$on' is on");
    }
    ok($e->({ x => {} }, 'x'), 'a map is on');
    ok($e->({ x => [] }, 'x'), 'a list is on');
    is($e->({ x => 'no' }, 'x'), 0, 'returns 0 when off');
    is($e->({}, 'x'), 1, 'returns 1 when on');
    ok($e->({ x => JSON::true }, 'x'), 'JSON true is on');
    ok(!$e->({ x => JSON::false }, 'x'), 'JSON false is off');
};

subtest 'is_draft' => sub {
    my $d = \&App::Dapper::Publish::is_draft;
    ok(!$d->({}), 'no draft setting');
    ok($d->({ draft => 1 }), 'draft: true');
    ok($d->({ draft => 'yes' }), 'draft: yes');
    ok(!$d->({ draft => '' }), 'draft: false');
    ok(!$d->({ draft => 'no' }), 'draft: no');
    ok(!$d->({ draft => 0 }), 'draft: 0');
    ok(!$d->({ draft => undef }), 'draft: (empty)');
};

subtest 'twin_path and twin_url' => sub {
    my $p = \&App::Dapper::Publish::twin_path;
    my $u = \&App::Dapper::Publish::twin_url;
    is($p->({ filename => '_output/blog/post/index.html' }), '_output/blog/post/index.md', 'index file');
    is($p->({ filename => '_output/about.html' }), '_output/about.md', 'plain file');
    is($p->({ filename => '_output/v1.2/about.htm' }), '_output/v1.2/about.md', 'a dot in a directory is left alone');
    is($u->({ url => '/blog/post/' }), '/blog/post/index.md', 'directory URL');
    is($u->({ url => '/' }), '/index.md', 'home page');
    is($u->({ url => '/about.html' }), '/about.md', 'file URL');
    is($u->({ url => '/v1.2/about.htm' }), '/v1.2/about.md', 'a dot in a directory is left alone');
};

subtest 'has_twin' => sub {
    my $h = \&App::Dapper::Publish::has_twin;
    my %page = (source_file_extension => '.md', filename => '_output/a.html', markdown => 'Text');
    ok($h->({}, { %page }), 'a Markdown page');
    ok(!$h->({ markdown_twins => 'false' }, { %page }), 'markdown_twins: false for the site');
    ok(!$h->({ markdown_twins => 0 }, { %page }), 'markdown_twins: 0');
    ok(!$h->({}, { %page, source_file_extension => '.html' }), 'not made from Markdown');
    ok(!$h->({}, { %page, source_file_extension => undef }), 'no source extension');
    ok(!$h->({}, { %page, filename => '_output/a.xml' }), 'not HTML');
    ok(!$h->({}, { %page, markdown_twin => 'false' }), 'markdown_twin: false for the page');
    ok($h->({}, { %page, markdown_twin => 'true' }), 'markdown_twin: true for the page');
    ok(!$h->({}, { %page, markdown => undef }), 'no Markdown');
    ok(!$h->({}, { %page, template => 1, markdown => 'Hi [% name %]' }), 'templated, with a directive');
    ok($h->({}, { %page, template => 1, markdown => 'Hi there' }), 'templated, without a directive');
    ok($h->({}, { %page, markdown => 'Hi [% name %]' }), 'a directive, but not templated, is just text');
    ok(!$h->({ templates_in_content => 1 }, { %page, markdown => 'Hi [% name %]' }), 'templates_in_content for the site');
};

subtest 'twin' => sub {
    my $t = \&App::Dapper::Publish::twin;
    is($t->({}, { title => 'T', description => 'D', markdown => "\n\nBody\n\n" }), "# T\n\n> D\n\nBody\n", 'title, description and body');
    is($t->({}, { markdown => 'Body' }), "Body\n", 'body only');
    is($t->({}, { title => '', description => '', markdown => 'Body' }), "Body\n", 'empty title and description are left out');
    is($t->({}, { title => 'T', description => ['x'], markdown => 'Body' }), "# T\n\nBody\n", 'a description that is a list is left out');
    is($t->({}, { title => 'T', markdown => "  indented\n\n" }), "# T\n\nindented\n", 'leading white space removed');
};

my @pages = (
    { title => 'Old post', url => '/blog/old/', categories => ['blog'], date => date('2020-01-01T00:00:00Z'), markdown => 'Old.', excerpt => '<p>Old.</p>' },
    { title => 'New post', url => '/blog/new/', categories => 'blog', date => date('2020-06-01T00:00:00Z'), markdown => 'New.', description => 'Newest' },
    { title => 'A note', url => '/notes/n/', categories => ['notes', 'blog'], date => date('2020-03-01T00:00:00Z'), markdown => 'Note.' },
    { title => '', url => '/untitled.html', date => date('2020-01-01T00:00:00Z'), markdown => 'Untitled.' },
    { title => 'About', url => '/about.html', categories => [], date => date('2020-01-01T00:00:00Z'), markdown => 'About.', description => 'Who' },
    { title => 'Secret', url => '/secret.html', date => date('2020-01-01T00:00:00Z'), markdown => 'Secret.', llms => 'false' },
    { title => 'Kept', url => '/kept.html', date => date('2020-01-01T00:00:00Z'), markdown => 'Kept.', llms => 'true' },
);

subtest 'llms_txt' => sub {
    my $site = { name => 'My Site', description => 'All about it.', url => 'https://example.com/' };
    is(App::Dapper::Publish::llms_txt($site, \@pages), <<'TEXT', 'exact text');
# My Site

> All about it.

## Blog

- [New post](https://example.com/blog/new/index.md): Newest
- [Old post](https://example.com/blog/old/index.md): Old.

## Notes

- [A note](https://example.com/notes/n/index.md)

## Pages

- [/untitled.html](https://example.com/untitled.md)
- [About](https://example.com/about.md): Who
- [Kept](https://example.com/kept.md)

TEXT

    is(App::Dapper::Publish::llms_txt({}, []), "# Site\n\n", 'no name, no description, no pages');
    is(App::Dapper::Publish::llms_txt({ name => 'N', description => '' }, [ $pages[4] ]),
        "# N\n\n## Pages\n\n- [About](/about.md): Who\n\n", 'empty description left out; relative links with no url');
};

subtest 'llms_full_txt' => sub {
    my $site = { name => 'My Site', description => 'All about it.', url => 'https://example.com' };
    is(App::Dapper::Publish::llms_full_txt($site, [ @pages[0, 1, 5] ]), <<'TEXT', 'exact text, in the order given');
# My Site

> All about it.

---

URL: https://example.com/blog/old/

# Old post

Old.

---

URL: https://example.com/blog/new/

# New post

> Newest

New.

TEXT
    is(App::Dapper::Publish::llms_full_txt({}, []), "# Site\n\n", 'empty');
};

my %site = (
    '_config.yml'        => "---\nname: Twins\nurl: https://example.com\ntimezone: UTC\n",
    '_source/index.md'   => "---\ntitle: Home\n---\nHello.\n",
    '_source/raw.html'   => "---\ntitle: Raw\n---\n<p>HTML</p>\n",
    '_source/feed.md'    => "---\ntitle: Feed-ish\nextension: .xml\n---\nNot HTML.\n",
    '_source/p.md'       => "---\ntitle: Post\ncategories: blog\ndate: 2020-01-01T00:00:00Z\ndescription: A post.\n---\nPost body.\n",
);

subtest 'twins in a build' => sub {
    make_site({ %site });
    my $d = quiet_build();
    is(slurp('_output/index.md'), "# Home\n\nHello.\n", 'home page twin');
    is(slurp('_output/blog/2020/01/post/index.md'), "# Post\n\n> A post.\n\nPost body.\n", 'post twin');
    ok(!-e '_output/raw.md', 'no twin for HTML source');
    ok(!-e '_output/feed.md', 'no twin when the output is not HTML');
    my %url = map { $_->{title} => $_->{markdown_url} } @{ $d->{site}->{pages} };
    is($url{Home}, '/index.md', 'markdown_url set');
    ok(!defined $url{Raw}, 'not set without a twin');
    is(slurp('_output/llms.txt'), "# Twins\n\n## Blog\n\n- [Post](https://example.com/blog/2020/01/post/index.md): A post.\n\n"
        . "## Pages\n\n- [Home](https://example.com/index.md): Hello.\n\n", 'llms.txt lists the twins');
    like(slurp('_output/index.html'), qr/Hello/, 'the page itself');
};

subtest 'no llms.txt when no page has a twin' => sub {
    make_site({ '_config.yml' => "---\nname: x\n", '_source/raw.html' => "---\ntitle: Raw\n---\n<p>x</p>\n" });
    quiet_build();
    ok(!-e '_output/llms.txt', 'no llms.txt');
    ok(!-e '_output/llms-full.txt', 'no llms-full.txt');
};

subtest 'llms_txt: false keeps the twins' => sub {
    make_site({ %site, '_config.yml' => "---\nname: x\nllms_txt: false\n" });
    quiet_build();
    ok(!-e '_output/llms.txt', 'no llms.txt');
    ok(-e '_output/index.md', 'twins still written');
};

subtest 'page 2 of a paginated page has no twin' => sub {
    make_site({
        %site,
        '_source/list.md' => "---\ntitle: List\npaginate:\n  per_page: 1\n---\nList.\n",
        '_source/q.md'    => "---\ntitle: Q\ncategories: blog\ndate: 2020-02-01T00:00:00Z\n---\nQ.\n",
    });
    quiet_build();
    ok(-e '_output/list.md', 'page 1 has its twin');
    ok(-e '_output/list/page/2/index.html', 'page 2 written');
    ok(!-e '_output/list/page/2/index.md', 'page 2 has none');
};

done_testing();
