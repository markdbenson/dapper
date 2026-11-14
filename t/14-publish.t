use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;
use JSON ();

use lib 't/lib';
use DapperTest;
use App::Dapper;

my %blog = (
    '_config.yml' => "---\nname: Tom & Jerry's\ndescription: A test site.\nurl: https://example.com/\nauthor: Jane\ntimezone: UTC\nfeed:\n  category: blog\n  limit: 2\n",
    '_layout/index.html' => "<head>[% page.seo %]</head>[% page.content %]",
    '_source/index.md' => "---\ntitle: Home\n---\nWelcome home.\n",
    '_source/about.md' => "---\ntitle: About\ndescription: Who we are </script>\nimage: /img/me.jpg\nsitemap: false\n---\nAbout us.\n",
    '_source/404.md' => "---\ntitle: Not found\n---\nNothing here.\n",
    '_source/list.html' => "---\ntitle: List\n---\n<ul></ul>\n",
    '_source/blog/one.md' => "---\ntitle: One & Only\ncategories: blog\ndate: 2020-01-01\n---\nFirst & best.\n\nMore.\n",
    '_source/blog/two.md' => "---\ntitle: Two\ncategories: blog\ndate: 2020-02-01\nupdated: 2020-03-01\n---\nSecond post.\n",
    '_source/blog/three.md' => "---\ntitle: Three\ncategories: blog\ndate: 2020-04-01\nllms: false\n---\nThird post.\n",
    '_source/blog/hidden.md' => "---\ntitle: Hidden\ncategories: notes\ndate: 2020-05-01\nmarkdown_twin: false\n---\nNo twin.\n",
);

subtest 'Markdown twins' => sub {
    make_site({ %blog });
    my $d = quiet_build();
    is(slurp('_output/blog/2020/01/one-only/index.md'), "# One & Only\n\nFirst & best.\n\nMore.\n", 'twin of a post');
    is(slurp('_output/about.md'), "# About\n\n> Who we are </script>\n\nAbout us.\n", 'twin includes the description');
    ok(!-e '_output/list.md', 'no twin for a page that is not Markdown');
    ok(!-e '_output/blog/2020/05/hidden/index.md', 'markdown_twin: false');
    my ($one) = grep { $_->{title} eq 'One & Only' } @{ $d->{site}->{pages} };
    is($one->{markdown_url}, '/blog/2020/01/one-only/index.md', 'page.markdown_url');
};

subtest 'templated Markdown gets no twin' => sub {
    make_site({
        '_source/a.md' => "---\ntitle: A\ntemplate: true\n---\n[% site.name %]\n",
        '_source/b.md' => "---\ntitle: B\ntemplate: true\n---\nNo directives here.\n",
    });
    quiet_build();
    ok(!-e '_output/a.md', 'twin would show template code, so it is skipped');
    ok(-e '_output/b.md', 'a templated page without directives keeps its twin');
};

subtest 'llms.txt and llms-full.txt' => sub {
    make_site({ %blog });
    quiet_build();
    my $llms = slurp('_output/llms.txt');
    like($llms, qr/\A# Tom & Jerry's\n\n> A test site\.\n\n## Blog\n\n/, 'title and description');
    like($llms, qr{- \[Two\]\(https://example\.com/blog/2020/02/two/index\.md\): Second post\.\n- \[One & Only\]}, 'newest first, with absolute twin links');
    unlike($llms, qr/Three/, 'llms: false leaves a page out');
    like($llms, qr{## Pages\n\n.*\[About\]\(https://example\.com/about\.md\): Who we are}s, 'other pages listed last');
    like(slurp('_output/llms-full.txt'), qr{---\n\nURL: https://example\.com/blog/2020/01/one-only/\n\n# One & Only\n\nFirst & best\.}, 'full text');
};

subtest 'sitemap' => sub {
    make_site({ %blog });
    quiet_build();
    my $xml = slurp('_output/sitemap.xml');
    like($xml, qr{<loc>https://example\.com/</loc>}, 'home page');
    like($xml, qr{<loc>https://example\.com/blog/2020/02/two/</loc>\n    <lastmod>2020-03-01T00:00:00\+00:00</lastmod>}, 'updated date used for lastmod');
    unlike($xml, qr/about/, 'sitemap: false');
    unlike($xml, qr/404/, '404 page left out');

    make_site({ '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    quiet_build();
    ok(!-e '_output/sitemap.xml', 'no sitemap without a url (and no warning, since it was not asked for)');
};

subtest 'feed' => sub {
    make_site({ %blog });
    quiet_build();
    my $xml = slurp('_output/feed.xml');
    like($xml, qr{<title>Tom &amp; Jerry&#39;s</title>}, 'escaped site name');
    like($xml, qr{<link rel="self" href="https://example\.com/feed\.xml"/>}, 'self link');
    my @entries = $xml =~ /<entry>/g;
    is(scalar @entries, 2, 'limit');
    like($xml, qr{<entry>\n    <title>Three</title>.*<entry>\n    <title>Two</title>}s, 'newest first');
    unlike($xml, qr/Hidden/, 'other categories left out');
    like($xml, qr{<content type="html">&lt;p&gt;Second post\.&lt;/p&gt;}, 'escaped content');

    make_site({ '_config.yml' => "---\nname: x\nfeed: true\n", '_source/a.md' => "---\ntitle: A\ncategories: x\n---\nx\n" });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    ok(!-e '_output/feed.xml', 'no feed without a url');
    like(join('', @warnings), qr/the feed needs the site's address/, 'with a warning');
};

subtest 'a page that writes the same file wins' => sub {
    make_site({ %blog, '_source/feed.xml' => "---\nlayout: raw\nextension: .xml\n---\n<mine/>\n", '_layout/raw.html' => '[% page.content %]' });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    is(slurp('_output/feed.xml'), "<mine/>\n", 'the page is kept');
    like(join('', @warnings), qr/already writes _output\/feed\.xml/, 'with a warning');
};

subtest 'page.seo' => sub {
    make_site({ %blog });
    quiet_build();
    my $about = slurp('_output/about.html');
    like($about, qr{<meta name="description" content="Who we are &lt;/script&gt;">}, 'description escaped');
    like($about, qr{<link rel="canonical" href="https://example\.com/about\.html">}, 'canonical');
    like($about, qr{<meta property="og:image" content="https://example\.com/img/me\.jpg">}, 'image made absolute');
    like($about, qr{<meta property="og:type" content="website">}, 'website type');
    like($about, qr{<meta name="twitter:card" content="summary_large_image">}, 'large card with an image');
    like($about, qr{<link rel="alternate" type="application/atom\+xml"}, 'feed link');

    my ($json) = $about =~ m{<script type="application/ld\+json">(.*?)</script>}s;
    unlike($json, qr{</script}, 'script end is escaped inside JSON-LD');
    my $data = JSON->new->decode($json);
    is($data->{'@type'}, 'WebPage', 'JSON-LD type');
    is($data->{description}, 'Who we are </script>', 'JSON-LD description round-trips');

    my $post = slurp('_output/blog/2020/01/one-only/index.html');
    like($post, qr{<meta property="og:type" content="article">}, 'article type');
    like($post, qr{<meta property="article:published_time" content="2020-01-01T00:00:00\+00:00">}, 'published time');
    my ($post_json) = $post =~ m{<script type="application/ld\+json">(.*?)</script>}s;
    my $post_data = JSON->new->decode($post_json);
    is($post_data->{'@type'}, 'BlogPosting', 'BlogPosting');
    is($post_data->{author}->{name}, 'Jane', 'author from the site');
    is($post_data->{description}, 'First & best.', 'description from the excerpt');
};

subtest 'everything can be turned off' => sub {
    make_site({ %blog, '_config.yml' => "---\nname: x\nurl: https://example.com\nmarkdown_twins: false\nllms_txt: false\nsitemap: false\n" });
    quiet_build();
    ok(!-e '_output/about.md', 'no twins');
    ok(!-e '_output/llms.txt', 'no llms.txt');
    ok(!-e '_output/sitemap.xml', 'no sitemap');
    ok(!-e '_output/feed.xml', 'no feed unless asked for');
};

done_testing();
