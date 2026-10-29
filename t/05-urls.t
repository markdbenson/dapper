use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

sub page_for {
    my ($d, $source) = @_;
    my ($page) = grep { $_->{source} eq $source } @{ $d->{site}->{pages} };
    return $page;
}

# GitHub issue #5: output file names should match the computed URL.

subtest 'page-level urlpattern decides the output file' => sub {
    make_site({
        '_source/posts/0001.md' => "---\ntitle: Foo Bar Baz\ndate: 2015-08-01T10:00:00\nurlpattern: /:year/:month/:slug.html\n---\nOne\n",
        '_source/posts/0002.md' => "---\ntitle: Yada Yada Yada\ndate: 2015-08-02T10:00:00\nurlpattern: /:year/:month/:slug/\n---\nTwo\n",
    });
    my $d = quiet_build();

    ok(-f '_output/2015/08/foo-bar-baz.html', 'file named after the URL');
    ok(-f '_output/2015/08/yada-yada-yada/index.html', 'URL ending in / becomes index.html');
    ok(!-e '_output/posts/0001.html', 'source file name is not used');
    is(page_for($d, '_source/posts/0001.md')->{url}, '/2015/08/foo-bar-baz.html', 'page.url');
};

subtest 'categories use the site urlpattern' => sub {
    make_site({
        '_source/a.md' => "---\ntitle: Cat Post\ncategories: blog\ndate: 2015-08-02T10:00:00\n---\nhi\n",
    });
    my $d = quiet_build();
    ok(-f '_output/blog/2015/08/cat-post/index.html', 'categorized page path');
    is(page_for($d, '_source/a.md')->{url}, '/blog/2015/08/cat-post/', 'categorized page.url');
};

subtest 'a list of categories' => sub {
    make_site({
        '_source/a.md' => "---\ntitle: Multi\ncategories: [news, blog]\ndate: 2015-08-02T10:00:00\n---\nhi\n",
    });
    my $d = quiet_build();
    is(page_for($d, '_source/a.md')->{url}, '/news/2015/08/multi/', 'first category is used in the URL');
    is(scalar @{ $d->{site}->{categories}->{news} }, 1, 'listed under the first category');
    is(scalar @{ $d->{site}->{categories}->{blog} }, 1, 'listed under the second category');
};

subtest 'missing tokens and slugs' => sub {
    make_site({
        '_source/no-title.md' => "---\ndate: 2015-08-02T10:00:00\nurlpattern: /:category/:year/:slug/\n---\nhi\n",
    });
    my $d = quiet_build();
    is(page_for($d, '_source/no-title.md')->{url}, '/2015/no-title/',
        'empty :category is dropped and the file name is the slug');
};

subtest 'the extension is used for index files' => sub {
    make_site({
        '_source/feed.md' => "---\ntitle: Feed\ncategories: feeds\nextension: .xml\nurlpattern: /:category/\n---\nhi\n",
    });
    quiet_build();
    ok(-f '_output/feeds/index.xml', 'index file uses the page extension');
};

subtest 'plain pages keep their source path' => sub {
    make_site({
        '_source/index.md'       => "---\ntitle: Home\n---\nhi\n",
        '_source/about/index.md' => "---\ntitle: About\n---\nhi\n",
        '_source/404.md'         => "---\ntitle: Missing\n---\nhi\n",
    });
    my $d = quiet_build();
    ok(-f '_output/about/index.html', 'nested page path');
    is(page_for($d, '_source/index.md')->{url}, '/', 'root index url');
    is(page_for($d, '_source/about/index.md')->{url}, '/about/', 'directory index url');
    is(page_for($d, '_source/404.md')->{url}, '/404.html', 'plain file url');
};

subtest 'pages are in source path order and ids are stable' => sub {
    make_site({
        map { ("_source/$_.md" => "---\ntitle: $_\n---\nhi\n") } qw(c a b)
    });
    my $d = quiet_build();
    is_deeply([ map { $_->{title} } @{ $d->{site}->{pages} } ], [qw(a b c)], 'sorted by path');
    is_deeply([ map { $_->{id} } @{ $d->{site}->{pages} } ], [1, 2, 3], 'ids follow the order');
};

subtest 'expand_urlpattern' => sub {
    is(App::Dapper::expand_urlpattern('/:year/:month/:day/:slug/', { year => 2020, month => '01', day => '02', slug => 'x' }),
        '/2020/01/02/x/', 'all tokens');
    is(App::Dapper::expand_urlpattern(':slug.html', { slug => 'x' }), '/x.html', 'leading slash added');
};

done_testing();
