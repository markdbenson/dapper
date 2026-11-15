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

# page.seo: every tag, and when each one appears.

sub date { App::Dapper::Utils::parse_date($_[0]) }
sub seo  { App::Dapper::Publish::seo(@_) }

sub tags_and_data {
    my ($html) = @_;
    my @lines = split /\n/, $html;
    my $script = pop @lines;
    my ($json) = $script =~ m{\A<script type="application/ld\+json">(.*)</script>\z};
    return (\@lines, JSON->new->decode($json), $json);
}

subtest 'an article with everything' => sub {
    my $site = { name => 'S', url => 'https://e.example', author => 'Jane', image => '/i.png', feed => 1 };
    my $page = { title => 'T', url => '/p/', categories => ['blog'], date => date('2020-01-01T00:00:00Z'),
                 updated => '2020-02-01T00:00:00Z', description => 'D', markdown_url => '/p/index.md' };
    is(seo($site, $page), join("\n",
        '<meta name="description" content="D">',
        '<link rel="canonical" href="https://e.example/p/">',
        '<link rel="alternate" type="text/markdown" href="https://e.example/p/index.md">',
        '<link rel="alternate" type="application/atom+xml" title="S" href="https://e.example/feed.xml">',
        '<meta property="og:type" content="article">',
        '<meta property="og:title" content="T">',
        '<meta property="og:description" content="D">',
        '<meta property="og:url" content="https://e.example/p/">',
        '<meta property="og:site_name" content="S">',
        '<meta property="og:image" content="https://e.example/i.png">',
        '<meta property="article:published_time" content="2020-01-01T00:00:00+00:00">',
        '<meta name="twitter:card" content="summary_large_image">',
        '<script type="application/ld+json">{"@context":"https://schema.org","@type":"BlogPosting",'
            . '"author":{"@type":"Person","name":"Jane"},"dateModified":"2020-02-01T00:00:00+00:00",'
            . '"datePublished":"2020-01-01T00:00:00+00:00","description":"D","headline":"T",'
            . '"image":"https://e.example/i.png","mainEntityOfPage":"https://e.example/p/",'
            . '"publisher":{"@type":"Organization","name":"S"},"url":"https://e.example/p/"}</script>',
    ), 'every tag, in order, with canonical JSON');
};

subtest 'a plain page with nothing' => sub {
    is(seo({}, { url => '/a.html' }), join("\n",
        '<meta property="og:type" content="website">',
        '<meta name="twitter:card" content="summary">',
        '<script type="application/ld+json">{"@context":"https://schema.org","@type":"WebPage"}</script>',
    ), 'only what is always there');
};

subtest 'a web page with a site name and url' => sub {
    my ($tags, $data) = tags_and_data(seo({ name => 'S', url => 'https://e.example/' }, { title => 'About', url => '/about.html', excerpt => '<p>Hi.</p>' }));
    is_deeply($tags, [
        '<meta name="description" content="Hi.">',
        '<link rel="canonical" href="https://e.example/about.html">',
        '<meta property="og:type" content="website">',
        '<meta property="og:title" content="About">',
        '<meta property="og:description" content="Hi.">',
        '<meta property="og:url" content="https://e.example/about.html">',
        '<meta property="og:site_name" content="S">',
        '<meta name="twitter:card" content="summary">',
    ], 'tags');
    is_deeply($data, { '@context' => 'https://schema.org', '@type' => 'WebPage', headline => 'About', name => 'About',
                       description => 'Hi.', url => 'https://e.example/about.html' }, 'WebPage has name and headline, no publisher');
};

subtest 'title' => sub {
    my ($tags, $data) = tags_and_data(seo({ name => 'Site' }, { url => '/' }));
    is($tags->[1], '<meta property="og:title" content="Site">', 'no page title: the site name');
    is($data->{headline}, 'Site', 'in JSON-LD too');
    ($tags) = tags_and_data(seo({ name => 'Site' }, { url => '/', title => ['x'] }));
    is($tags->[1], '<meta property="og:title" content="Site">', 'a title that is a list is ignored');
    ($tags) = tags_and_data(seo({ name => 'Site' }, { url => '/', title => '' }));
    is($tags->[1], '<meta property="og:title" content="">', 'an empty title is still the title');
};

subtest 'escaping' => sub {
    my $html = seo({ name => q{A & "B"}, url => 'https://e.example' },
                   { title => q{<T> & 'u'}, url => '/a&b/', description => 'x </script> y' });
    like($html, qr{<meta name="description" content="x &lt;/script&gt; y">}, 'description');
    like($html, qr{<meta property="og:title" content="&lt;T&gt; &amp; &#39;u&#39;">}, 'title');
    like($html, qr{<meta property="og:site_name" content="A &amp; &quot;B&quot;">}, 'site name');
    like($html, qr{<link rel="canonical" href="https://e\.example/a&amp;b/">}, 'URL');
    my (undef, $data, $json) = tags_and_data($html);
    unlike($json, qr{</}, 'no </ inside the script');
    like($json, qr{x <\\/script> y}, 'escaped as <\\/');
    is($data->{description}, 'x </script> y', 'decodes back to the original');
    is($data->{headline}, q{<T> & 'u'}, 'JSON is not HTML-escaped');

    my ($tags, $u) = tags_and_data(seo({ name => 'Café' }, { title => 'Ünïcode', url => '/' }));
    is($u->{headline}, 'Ünïcode', 'characters, not bytes');
};

subtest 'images' => sub {
    my $tags_for = sub { (tags_and_data(seo(@_)))[0] };
    my $data_for = sub { (tags_and_data(seo(@_)))[1] };
    my $site = { url => 'https://e.example', image => '/site.png' };
    ok((grep { $_ eq '<meta property="og:image" content="https://e.example/site.png">' } @{ $tags_for->($site, { url => '/' }) }), 'site image');
    ok((grep { $_ eq '<meta property="og:image" content="https://e.example/page.png">' } @{ $tags_for->($site, { url => '/', image => 'page.png' }) }), 'page image wins, made absolute');
    ok((grep { $_ eq '<meta property="og:image" content="https://cdn.example/x.png">' } @{ $tags_for->($site, { url => '/', image => 'https://cdn.example/x.png' }) }), 'absolute image kept');
    ok((grep { $_ eq '<meta property="og:image" content="https://e.example/site.png">' } @{ $tags_for->($site, { url => '/', image => { src => 'x' } }) }), 'a page image that is a map falls back to the site image');
    ok(!(grep { /og:image/ } @{ $tags_for->({ image => ['x'] }, { url => '/' }) }), 'a site image that is a list is ignored');
    ok((grep { $_ eq '<meta name="twitter:card" content="summary">' } @{ $tags_for->({ image => ['x'] }, { url => '/' }) }), 'and the card is small');
    ok((grep { $_ eq '<meta property="og:image" content="/rel.png">' } @{ $tags_for->({}, { url => '/', image => '/rel.png' }) }), 'without url the image stays relative');
    is($data_for->($site, { url => '/', image => '/p.png' })->{image}, 'https://e.example/p.png', 'JSON-LD image');
};

subtest 'article dates' => sub {
    my $site = { name => 'S' };
    my ($tags, $data) = tags_and_data(seo($site, { url => '/p/', categories => 'blog', date => date('2020-01-01T09:00:00-05:00') }));
    ok((grep { $_ eq '<meta property="article:published_time" content="2020-01-01T09:00:00-05:00">' } @$tags), 'published time with its zone');
    is($data->{datePublished}, '2020-01-01T09:00:00-05:00', 'datePublished');
    is($data->{dateModified}, '2020-01-01T09:00:00-05:00', 'dateModified is the date when not updated');
    ok(!exists $data->{name}, 'a BlogPosting has no name');
    ok(!exists $data->{mainEntityOfPage}, 'no mainEntityOfPage without url');
    is_deeply($data->{publisher}, { '@type' => 'Organization', name => 'S' }, 'publisher');

    ($tags, $data) = tags_and_data(seo({}, { url => '/p/', categories => ['blog'], date => '2020-01-01' }));
    ok(!(grep { /published_time/ } @$tags), 'no published time when the date is not a date');
    ok(!exists $data->{datePublished}, 'nor datePublished');
    ok(!exists $data->{publisher}, 'no publisher without a site name');
    is($data->{'@type'}, 'BlogPosting', 'still an article');

    (undef, $data) = tags_and_data(seo({}, { url => '/p/', categories => ['blog'], date => date('2020-01-01T00:00:00Z'), updated => 'not a date' }));
    is($data->{dateModified}, '2020-01-01T00:00:00+00:00', 'a bad updated falls back to the date');
};

subtest 'what makes an article' => sub {
    my $type = sub { (tags_and_data(seo({}, { url => '/', %{ $_[0] } })))[1]->{'@type'} };
    is($type->({ categories => ['blog'] }), 'BlogPosting', 'a list of categories');
    is($type->({ categories => 'blog' }), 'BlogPosting', 'one category');
    is($type->({ categories => [] }), 'WebPage', 'an empty list');
    is($type->({ categories => '' }), 'WebPage', 'an empty string');
    is($type->({ categories => { a => 1 } }), 'WebPage', 'a map');
    is($type->({}), 'WebPage', 'no categories');
};

subtest 'author' => sub {
    my $author = sub { (tags_and_data(seo(@_)))[1]->{author} };
    is_deeply($author->({ author => 'Site' }, { url => '/' }), { '@type' => 'Person', name => 'Site' }, 'site author');
    is_deeply($author->({ author => 'Site' }, { url => '/', author => 'Page' }), { '@type' => 'Person', name => 'Page' }, 'page author wins');
    is_deeply($author->({ author => 'Site' }, { url => '/', author => ['A', 'B'] }), { '@type' => 'Person', name => 'Site' }, 'a list falls back to the site');
    is($author->({ author => { name => 'x' } }, { url => '/' }), undef, 'a site author that is a map is left out');
    is($author->({}, { url => '/' }), undef, 'no author');
};

subtest 'feed link' => sub {
    my $tags = (tags_and_data(seo({ name => 'S', feed => { path => 'atom.xml', title => 'News & more' } }, { url => '/' })))[0];
    ok((grep { $_ eq '<link rel="alternate" type="application/atom+xml" title="News &amp; more" href="/atom.xml">' } @$tags), 'custom title and path, relative without url');
    $tags = (tags_and_data(seo({ name => 'S', feed => 'false' }, { url => '/' })))[0];
    ok(!(grep { /atom/ } @$tags), 'feed: false');
    $tags = (tags_and_data(seo({ feed => 1 }, { url => '/' })))[0];
    ok((grep { $_ eq '<link rel="alternate" type="application/atom+xml" title="" href="/feed.xml">' } @$tags), 'no title at all');
};

subtest 'page.seo in a build' => sub {
    make_site({
        '_config.yml'        => "---\nname: Built\nurl: https://example.com\ntimezone: UTC\n",
        '_layout/index.html' => "<head>\n[% page.seo %]\n</head>",
        '_source/a.md'       => "---\ntitle: A page\n---\nFirst *para*.\n\nSecond.\n",
    });
    quiet_build();
    is(slurp('_output/a.html'), "<head>\n" . join("\n",
        '<meta name="description" content="First para.">',
        '<link rel="canonical" href="https://example.com/a.html">',
        '<link rel="alternate" type="text/markdown" href="https://example.com/a.md">',
        '<meta property="og:type" content="website">',
        '<meta property="og:title" content="A page">',
        '<meta property="og:description" content="First para.">',
        '<meta property="og:url" content="https://example.com/a.html">',
        '<meta property="og:site_name" content="Built">',
        '<meta name="twitter:card" content="summary">',
        '<script type="application/ld+json">{"@context":"https://schema.org","@type":"WebPage","description":"First para.",'
            . '"headline":"A page","name":"A page","url":"https://example.com/a.html"}</script>',
    ) . "\n</head>", 'the whole head');
};

done_testing();
