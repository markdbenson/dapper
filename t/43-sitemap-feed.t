use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Publish;
use App::Dapper::Utils;

# sitemap.xml and the Atom feed: the functions directly, then in builds.

sub date { App::Dapper::Utils::parse_date($_[0]) }

my $HEAD = qq{<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n};

subtest 'sitemap: exact XML' => sub {
    my $site = { url => 'https://example.com/' };
    my @pages = (
        { url => '/', filename => '_output/index.html', date => date('2020-01-02T03:04:05Z') },
        { url => '/a&b.html', filename => '_output/a&b.html', date => date('2020-01-01T00:00:00-05:00'), updated => '2021-02-03T04:05:06+01:00' },
        { url => '/feed.xml', filename => '_output/feed.xml', date => date('2020-01-01T00:00:00Z') },
        { url => '/hidden.html', filename => '_output/hidden.html', date => date('2020-01-01T00:00:00Z'), sitemap => 'false' },
        { url => '/shown.html', filename => '_output/shown.html', date => date('2020-01-01T00:00:00Z'), sitemap => 'true' },
        { url => '/404.html', filename => '_output/404.html', date => date('2020-01-01T00:00:00Z') },
        { url => '/fr/404.html', filename => '_output/fr/404.html', date => date('2020-01-01T00:00:00Z') },
        { url => '/not-404.html', filename => '_output/not-404.html', date => date('2020-01-01T00:00:00Z') },
        { url => '/nodate.htm', filename => '_output/nodate.htm' },
        { url => '/bad-updated.html', filename => '_output/bad-updated.html', date => date('2020-05-05T00:00:00Z'), updated => 'whenever' },
    );
    is(App::Dapper::Publish::sitemap($site, \@pages), $HEAD
        . "  <url>\n    <loc>https://example.com/</loc>\n    <lastmod>2020-01-02T03:04:05+00:00</lastmod>\n  </url>\n"
        . "  <url>\n    <loc>https://example.com/a&amp;b.html</loc>\n    <lastmod>2021-02-03T04:05:06+01:00</lastmod>\n  </url>\n"
        . "  <url>\n    <loc>https://example.com/shown.html</loc>\n    <lastmod>2020-01-01T00:00:00+00:00</lastmod>\n  </url>\n"
        . "  <url>\n    <loc>https://example.com/not-404.html</loc>\n    <lastmod>2020-01-01T00:00:00+00:00</lastmod>\n  </url>\n"
        . "  <url>\n    <loc>https://example.com/nodate.htm</loc>\n  </url>\n"
        . "  <url>\n    <loc>https://example.com/bad-updated.html</loc>\n    <lastmod>2020-05-05T00:00:00+00:00</lastmod>\n  </url>\n"
        . "</urlset>\n",
        'HTML pages only; sitemap: false and 404 pages left out; updated wins; a bad updated falls back to date; no date, no lastmod');
};

subtest 'sitemap: empty' => sub {
    is(App::Dapper::Publish::sitemap({ url => 'https://example.com' }, []), "$HEAD</urlset>\n", 'no pages');
};

subtest 'sitemap: a date that is not a date object has no lastmod' => sub {
    is(App::Dapper::Publish::sitemap({ url => 'https://e.example' }, [ { url => '/', filename => 'o/index.html', date => '2020-01-01' } ]),
        "$HEAD  <url>\n    <loc>https://e.example/</loc>\n  </url>\n</urlset>\n", 'string date ignored');
};

subtest 'feed_settings' => sub {
    my $f = \&App::Dapper::Publish::feed_settings;
    is($f->({}), undef, 'not set: no feed');
    is($f->({ feed => undef }), undef, 'empty: no feed');
    is($f->({ feed => 'false' }), undef, 'feed: false');
    is($f->({ feed => '' }), undef, 'feed: (empty string)');
    is($f->({ feed => 0 }), undef, 'feed: 0');
    is_deeply($f->({ feed => 1, name => 'N' }), { path => '/feed.xml', limit => 20, title => 'N' }, 'feed: true gives the defaults');
    is_deeply($f->({ feed => 'yes' }), { path => '/feed.xml', limit => 20, title => undef }, 'no site name: no title');
    is_deeply($f->({ feed => {}, name => 'N' }), { path => '/feed.xml', limit => 20, title => 'N' }, 'an empty map gives the defaults');
    is_deeply($f->({ feed => { path => 'atom.xml', limit => 5, title => 'Mine', category => 'blog' }, name => 'N' }),
        { path => '/atom.xml', limit => 5, title => 'Mine', category => 'blog' }, 'every setting, with / added to the path');
    is_deeply($f->({ feed => { path => '/blog/feed.xml' } }), { path => '/blog/feed.xml', limit => 20, title => undef }, 'a path with /');
    is_deeply($f->({ feed => { limit => 0 } })->{limit}, 0, 'limit: 0 is kept');
    is_deeply($f->({ feed => ['x'], name => 'N' }), { path => '/feed.xml', limit => 20, title => 'N' }, 'a list turns it on with the defaults');
    my $site = { feed => { limit => 3 } };
    $f->($site);
    is_deeply($site->{feed}, { limit => 3 }, 'the site settings are not changed');
};

my @posts = map {
    { title => "Post $_", url => "/blog/p$_/", filename => "_output/blog/p$_/index.html",
      date => date(sprintf('2020-01-%02dT12:00:00Z', $_)), content => "<p>Post $_</p>" }
} 1 .. 5;
my $xml_page = { title => 'XML', url => '/x.xml', filename => '_output/x.xml', date => date('2020-02-01T00:00:00Z'), content => 'x' };
my $note = { title => 'Note', url => '/notes/n/', filename => '_output/notes/n/index.html', date => date('2020-01-10T00:00:00Z'), content => 'n' };

subtest 'feed_pages' => sub {
    my $site = { categories => { blog => [ @posts, $xml_page ], notes => [ $note, $posts[0] ] } };
    my $titles = sub { [ map { $_->{title} } @{ App::Dapper::Publish::feed_pages($site, $_[0]) } ] };
    is_deeply($titles->({ category => 'blog', limit => 20 }), [ 'Post 5', 'Post 4', 'Post 3', 'Post 2', 'Post 1' ],
        'one category, newest first, HTML only');
    is_deeply($titles->({ category => 'blog', limit => 2 }), [ 'Post 5', 'Post 4' ], 'limit');
    is_deeply($titles->({ category => 'blog', limit => 5 }), [ 'Post 5', 'Post 4', 'Post 3', 'Post 2', 'Post 1' ], 'limit equal to the count');
    is_deeply($titles->({ category => 'blog', limit => 0 }), [ 'Post 5', 'Post 4', 'Post 3', 'Post 2', 'Post 1' ], 'limit 0 means no limit');
    is_deeply($titles->({ category => 'nope', limit => 20 }), [], 'a category with no pages');
    is_deeply($titles->({ limit => 20 }), [ 'Note', 'Post 5', 'Post 4', 'Post 3', 'Post 2', 'Post 1' ],
        'no category: every page with a category, each once');
    is_deeply($titles->({ limit => 3 }), [ 'Note', 'Post 5', 'Post 4' ], 'no category, with a limit');
    is_deeply(App::Dapper::Publish::feed_pages({ categories => {} }, { limit => 20 }), [], 'no categories at all');
};

subtest 'feed: exact XML' => sub {
    my $site = { name => 'Tom & Jerry', description => 'A <test> site', url => 'https://example.com', author => 'Jane',
                 time => date('2021-01-01T00:00:00Z') };
    my @pages = (
        { title => 'Two "quoted"', url => '/two/', date => date('2020-02-01T00:00:00Z'), updated => '2020-03-01T08:00:00-05:00',
          author => 'Bob', description => 'Second & last', content => '<p>Two</p>' },
        { url => '/one/', date => date('2020-01-01T00:00:00+02:00'), author => ['Not', 'a', 'name'],
          excerpt => '<p>One <b>only</b></p>', content => '<p>One <b>only</b></p>' },
        { title => 'Three', url => '/three/', date => date('2019-01-01T00:00:00Z'), content => '' },
    );
    my $settings = { path => '/feed.xml', title => 'Feed & co', limit => 20 };
    is(App::Dapper::Publish::feed($site, $settings, \@pages), <<'XML', 'every element, escaped');
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Feed &amp; co</title>
  <subtitle>A &lt;test&gt; site</subtitle>
  <link href="https://example.com/"/>
  <link rel="self" href="https://example.com/feed.xml"/>
  <id>https://example.com/</id>
  <updated>2020-03-01T08:00:00-05:00</updated>
  <author><name>Jane</name></author>
  <entry>
    <title>Two &quot;quoted&quot;</title>
    <link href="https://example.com/two/"/>
    <id>https://example.com/two/</id>
    <published>2020-02-01T00:00:00+00:00</published>
    <updated>2020-03-01T08:00:00-05:00</updated>
    <author><name>Bob</name></author>
    <summary>Second &amp; last</summary>
    <content type="html">&lt;p&gt;Two&lt;/p&gt;</content>
  </entry>
  <entry>
    <title>/one/</title>
    <link href="https://example.com/one/"/>
    <id>https://example.com/one/</id>
    <published>2020-01-01T00:00:00+02:00</published>
    <updated>2020-01-01T00:00:00+02:00</updated>
    <summary>One only</summary>
    <content type="html">&lt;p&gt;One &lt;b&gt;only&lt;/b&gt;&lt;/p&gt;</content>
  </entry>
  <entry>
    <title>Three</title>
    <link href="https://example.com/three/"/>
    <id>https://example.com/three/</id>
    <published>2019-01-01T00:00:00+00:00</published>
    <updated>2019-01-01T00:00:00+00:00</updated>
    <content type="html"></content>
  </entry>
</feed>
XML
};

subtest 'feed: no pages, no description, no author' => sub {
    my $site = { name => 'N', url => 'https://example.com/', time => date('2021-06-07T08:09:10Z') };
    is(App::Dapper::Publish::feed($site, { path => '/atom.xml', title => 'N' }, []), <<'XML', 'updated is the build time');
<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>N</title>
  <link href="https://example.com/"/>
  <link rel="self" href="https://example.com/atom.xml"/>
  <id>https://example.com/</id>
  <updated>2021-06-07T08:09:10+00:00</updated>
</feed>
XML
};

subtest 'feed: updated comes from the first page given' => sub {
    my $site = { name => 'N', url => 'https://e.example', time => date('2021-01-01T00:00:00Z') };
    my @pages = (
        { title => 'A', url => '/a/', date => date('2020-01-02T00:00:00Z'), content => '' },
        { title => 'B', url => '/b/', date => date('2020-01-01T00:00:00Z'), updated => '2020-12-31T00:00:00Z', content => '' },
    );
    like(App::Dapper::Publish::feed($site, { path => '/f.xml', title => 'N' }, \@pages),
        qr{<id>https://e\.example/</id>\n  <updated>2020-01-02T00:00:00\+00:00</updated>}, 'the newest page, not the latest update');
};

my %blog = (
    '_config.yml' => "---\nname: Blog\nurl: https://example.com\ntimezone: UTC\nfeed:\n  category: blog\n  path: news/atom.xml\n  title: News\n",
    '_source/index.md' => "---\ntitle: Home\n---\nHome.\n",
    '_source/a.md' => "---\ntitle: A\ncategories: blog\ndate: 2020-01-01T00:00:00Z\n---\nA text.\n",
    '_source/b.md' => "---\ntitle: B\ncategories: [blog, notes]\ndate: 2020-02-01T00:00:00Z\nauthor: Ann\n---\nB text.\n",
    '_source/c.md' => "---\ntitle: C\ncategories: notes\ndate: 2020-03-01T00:00:00Z\n---\nC text.\n",
);

subtest 'feed in a build: path, title and category' => sub {
    make_site({ %blog });
    quiet_build();
    ok(!-e '_output/feed.xml', 'not at the default path');
    my $xml = slurp('_output/news/atom.xml');
    like($xml, qr{<title>News</title>}, 'title');
    like($xml, qr{<link rel="self" href="https://example\.com/news/atom\.xml"/>}, 'self link');
    my @titles = $xml =~ m{<entry>\n    <title>([^<]*)</title>}g;
    is_deeply(\@titles, ['B', 'A'], 'only the category, newest first');
    like($xml, qr{<author><name>Ann</name></author>}, 'page author');
    like($xml, qr{<content type="html">&lt;p&gt;B text\.&lt;/p&gt;\n</content>}, 'content');
    like(slurp('_output/index.html'), qr/Home/, 'pages still built');
};

subtest 'feed: true in a build: every category' => sub {
    make_site({ %blog, '_config.yml' => "---\nname: Blog\nurl: https://example.com\nfeed: true\n" });
    quiet_build();
    my @titles = slurp('_output/feed.xml') =~ m{<entry>\n    <title>([^<]*)</title>}g;
    is_deeply(\@titles, ['C', 'B', 'A'], 'every page with a category, once each');
};

subtest 'sitemap in a build' => sub {
    make_site({
        %blog,
        '_config.yml'      => "---\nname: Blog\nurl: https://example.com/\ntimezone: UTC\n",
        '_source/x.md'     => "---\ntitle: X\nsitemap: no\ndate: 2020-01-01T00:00:00Z\n---\nx\n",
        '_source/data.md'  => "---\ntitle: Data\nextension: .json\ndate: 2020-01-01T00:00:00Z\n---\n{}\n",
    });
    quiet_build();
    my @locs = slurp('_output/sitemap.xml') =~ m{<loc>([^<]*)</loc>}g;
    is_deeply([ sort @locs ], [
        'https://example.com/',
        'https://example.com/blog/2020/01/a/',
        'https://example.com/blog/2020/02/b/',
        'https://example.com/notes/2020/03/c/',
    ], 'every HTML page except sitemap: no');
};

subtest 'sitemap: false and the warnings without url' => sub {
    make_site({ %blog, '_config.yml' => "---\nname: x\nurl: https://example.com\nsitemap: false\n" });
    quiet_build();
    ok(!-e '_output/sitemap.xml', 'sitemap: false');

    make_site({ %blog, '_config.yml' => "---\nname: x\nsitemap: true\n" });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    is_deeply(\@warnings, ["warning: the sitemap needs the site's address; set url in _config.yml\n"], 'sitemap: true without url warns');

    @warnings = ();
    make_site({ %blog, '_config.yml' => "---\nname: x\nfeed: true\n" });
    quiet_build();
    is_deeply(\@warnings, ["warning: the feed needs the site's address; set url in _config.yml\n"], 'feed without url warns');
    ok(!-e '_output/feed.xml', 'and no feed');
};

subtest 'check: the warnings without url are typed setting' => sub {
    make_site({ %blog, '_config.yml' => "---\nname: x\nsitemap: true\nfeed: true\n" });
    my $report = App::Dapper->new()->check();
    my @settings = map { "$_->{file}: $_->{message}" } grep { $_->{type} eq 'setting' } @{ $report->{warnings} };
    is_deeply(\@settings, [
        "_config.yml: the sitemap needs the site's address; set url in _config.yml",
        "_config.yml: the feed needs the site's address; set url in _config.yml",
        '_config.yml: url is not set, so there is no sitemap, and links in llms.txt and page.seo are not absolute',
    ], 'all three') or diag explain $report;
};

subtest 'a page at the sitemap path wins' => sub {
    make_site({ %blog, '_config.yml' => "---\nname: x\nurl: https://example.com\n",
                '_source/sitemap.xml' => "---\nlayout: raw\nextension: .xml\n---\n<mine/>\n", '_layout/raw.html' => '[% page.content %]' });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    is(slurp('_output/sitemap.xml'), "<mine/>\n", 'kept');
    is_deeply(\@warnings, ["warning: a page in the source directory already writes _output/sitemap.xml, so Dapper did not generate one\n"], 'warned');
};

done_testing();
