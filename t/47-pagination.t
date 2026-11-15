use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Collections;
use App::Dapper::Utils;

# Pagination, category pages and tag pages: the functions directly, then in
# builds.

sub date { App::Dapper::Utils::parse_date($_[0]) }

my @posts = map { { title => "P$_", date => date(sprintf('2020-01-%02dT00:00:00Z', $_)) } } 1 .. 7;
my $dapper = { output => '_output', site => { categories => { blog => [ @posts[0 .. 4] ], notes => [ @posts[5, 6], $posts[0] ] },
                                              tags => { perl => [ @posts[1, 3] ] } } };

sub pages_of {
    my ($page) = @_;
    return [ App::Dapper::Collections::paginate($dapper, $page) ];
}

sub titles { [ map { $_->{title} } @{ $_[0] } ] }

subtest 'base_url' => sub {
    my $b = \&App::Dapper::Collections::base_url;
    is($b->('/blog/'), '/blog/', 'a directory stays');
    is($b->('/'), '/', 'the home page');
    is($b->('/archive.html'), '/archive/', 'a file becomes a directory');
    is($b->('/blog/index.html'), '/blog/', 'an index file is its directory');
    is($b->('/index.htm'), '/', 'the home index file');
    is($b->('/feed'), '/feed/', 'no extension');
    is($b->('/v1.2/list.html'), '/v1.2/list/', 'a dot in a directory is left alone');
};

subtest 'set_filename' => sub {
    my $page = { url => '/blog/page/2/', extension => '.html' };
    App::Dapper::Collections::set_filename({ output => '_output' }, $page);
    is($page->{filename}, '_output/blog/page/2/index.html', 'directory URL gets an index file');
    is($page->{dirname}, '_output/blog/page/2/', 'dirname');
    $page = { url => '/list.htm', extension => '.html' };
    App::Dapper::Collections::set_filename({ output => '_output/' }, $page);
    is($page->{filename}, '_output/list.htm', 'a file URL is used as it is');
    is($page->{dirname}, '_output/', 'dirname');
};

subtest 'items_for' => sub {
    my $site = $dapper->{site};
    my $i = sub { titles([ App::Dapper::Collections::items_for($site, $_[0]) ]) };
    is_deeply($i->({ category => 'blog' }), [qw/ P5 P4 P3 P2 P1 /], 'a category, newest first');
    is_deeply($i->({ tag => 'perl' }), [qw/ P4 P2 /], 'a tag');
    is_deeply($i->({ category => 'notes', tag => 'perl' }), [qw/ P7 P6 P1 /], 'category wins over tag');
    is_deeply($i->({ category => 'none' }), [], 'an unknown category');
    is_deeply($i->({ tag => 'none' }), [], 'an unknown tag');
    is_deeply($i->({}), [qw/ P7 P6 P5 P4 P3 P2 P1 /], 'neither: every page with a category, each once');
};

subtest 'paginate: not paginated' => sub {
    my $page = { title => 'Plain', url => '/' };
    my $pages = pages_of($page);
    is(scalar @$pages, 1, 'one page');
    is($pages->[0], $page, 'the same page');
    ok(!exists $page->{paginator}, 'no paginator');
    is(scalar @{ pages_of({ url => '/', paginate => 0 }) }, 1, 'paginate: 0 is off');
    ok(!exists pages_of({ url => '/', paginate => '' })->[0]->{paginator}, 'paginate: (empty) is off');
};

subtest 'paginate: every field of the paginator' => sub {
    my $page = { title => 'Blog', url => '/blog/', source => 's', extension => '.html', markdown => 'M', markdown_url => '/blog/index.md',
                 paginate => { category => 'blog', per_page => 2 } };
    my $pages = pages_of($page);
    is(scalar @$pages, 3, 'three pages');
    is($pages->[0], $page, 'page 1 is the page itself');
    is_deeply([ map { $_->{url} } @$pages ], [ '/blog/', '/blog/page/2/', '/blog/page/3/' ], 'URLs');
    is_deeply([ map { $_->{filename} } @$pages[1, 2] ], [ '_output/blog/page/2/index.html', '_output/blog/page/3/index.html' ], 'filenames');
    is_deeply([ map { $_->{dirname} } @$pages[1, 2] ], [ '_output/blog/page/2/', '_output/blog/page/3/' ], 'dirnames');
    is($pages->[0]->{markdown}, 'M', 'page 1 keeps its Markdown');
    is($pages->[0]->{markdown_url}, '/blog/index.md', 'and its twin');
    ok(!exists $pages->[1]->{markdown}, 'page 2 has no Markdown');
    ok(!exists $pages->[1]->{markdown_url}, 'nor a twin');
    is($pages->[2]->{title}, 'Blog', 'later pages copy the settings');
    ok(!exists $pages->[1]->{posts}, 'posts only set for generated pages');

    my $all_pages = [ { number => 1, url => '/blog/' }, { number => 2, url => '/blog/page/2/' }, { number => 3, url => '/blog/page/3/' } ];
    my @expected = (
        { page => 1, items => [qw/ P5 P4 /], previous_url => undef, next_url => '/blog/page/2/' },
        { page => 2, items => [qw/ P3 P2 /], previous_url => '/blog/', next_url => '/blog/page/3/' },
        { page => 3, items => [qw/ P1 /], previous_url => '/blog/page/2/', next_url => undef },
    );
    for my $n (0 .. 2) {
        my $p = { %{ $pages->[$n]->{paginator} } };
        $p->{items} = titles($p->{items});
        is_deeply($p, {
            %{ $expected[$n] },
            per_page => 2, total_pages => 3, total_items => 5,
            first_url => '/blog/', last_url => '/blog/page/3/', pages => $all_pages,
        }, "page " . ($n + 1));
    }
};

subtest 'paginate: a number is per_page over every post' => sub {
    my $pages = pages_of({ url => '/archive.html', extension => '.html', source => 's', paginate => 3 });
    is(scalar @$pages, 3, '7 posts in pages of 3');
    is_deeply([ map { $_->{url} } @$pages ], [ '/archive.html', '/archive/page/2/', '/archive/page/3/' ], 'URLs below the page');
    is_deeply(titles($pages->[2]->{paginator}->{items}), ['P1'], 'last page');
    is($pages->[0]->{paginator}->{total_items}, 7, 'total');
};

subtest 'paginate: per_page' => sub {
    my $pages = pages_of({ url => '/', extension => '.html', source => 's', paginate => { tag => 'perl' } });
    is($pages->[0]->{paginator}->{per_page}, 10, 'defaults to 10');
    is(scalar @$pages, 1, 'one page');
    $pages = pages_of({ url => '/', extension => '.html', source => 's', paginate => { per_page => 0 } });
    is($pages->[0]->{paginator}->{per_page}, 10, 'per_page: 0 also means 10');
    $pages = pages_of({ url => '/', extension => '.html', source => 's', paginate => { per_page => 7 } });
    is(scalar @$pages, 1, 'exactly one full page');
    is($pages->[0]->{paginator}->{next_url}, undef, 'no next page');
    $pages = pages_of({ url => '/', extension => '.html', source => 's', paginate => { per_page => 6 } });
    is(scalar @$pages, 2, 'one more than fits');
    $pages = pages_of({ url => '/', extension => '.html', source => 's', paginate => { per_page => 1 } });
    is(scalar @$pages, 7, 'one each');
    is($pages->[6]->{url}, '/page/7/', 'URLs from the home page');
};

subtest 'paginate: an empty list still has one page' => sub {
    my $pages = pages_of({ url => '/empty/', extension => '.html', source => 's', paginate => { category => 'none', per_page => 5 } });
    is(scalar @$pages, 1, 'one page');
    is_deeply($pages->[0]->{paginator}, {
        items => [], page => 1, per_page => 5, total_pages => 1, total_items => 0,
        previous_url => undef, next_url => undef, first_url => '/empty/', last_url => '/empty/',
        pages => [ { number => 1, url => '/empty/' } ],
    }, 'paginator');
};

subtest 'paginate: given items' => sub {
    my $page = { url => '/t/', extension => '.html', source => 's', generated => 1, paginate => { items => [ @posts[0 .. 2] ], per_page => 2 } };
    my $pages = pages_of($page);
    is_deeply(titles($pages->[0]->{paginator}->{items}), [qw/ P1 P2 /], 'items kept in the order given');
    is_deeply(titles($pages->[0]->{posts}), [qw/ P1 P2 /], 'generated pages get posts');
    is_deeply(titles($pages->[1]->{posts}), [qw/ P3 /], 'on every page');
};

subtest 'paginate: errors' => sub {
    eval { pages_of({ url => '/', source => '_source/x.md', paginate => [2] }) };
    is($@, "error: paginate in _source/x.md must be a number or settings such as per_page: 10\n", 'a list');
    for my $bad ('ten', -1, '2.5', '1e1', ' 2') {
        eval { pages_of({ url => '/', source => '_source/x.md', paginate => { per_page => $bad } }) };
        is($@, "error: per_page in _source/x.md must be a whole number above 0\n", "per_page: '$bad'");
    }
    eval { pages_of({ url => '/', source => '_source/x.md', paginate => 'ten' }) };
    is($@, "error: per_page in _source/x.md must be a whole number above 0\n", "paginate: ten");
};

subtest 'list_pages' => sub {
    my $d = { output => '_output', config => '_config.yml', site => { extension => '.html' } };
    my %urls;
    my @pages = App::Dapper::Collections::list_pages($d, 'tag',
        { 'Open Source' => [ @posts[0, 1] ], perl => [ $posts[2] ] }, \%urls, { layout => 'tag', sitemap => 'false' });
    is(scalar @pages, 2, 'one page per tag');
    my ($os, $perl) = @pages;
    is($os->{title}, 'Open Source', 'title, sorted by name');
    is($os->{tag}, 'Open Source', 'page.tag');
    ok(!exists $os->{category}, 'no page.category');
    is_deeply(titles($os->{posts}), [qw/ P2 P1 /], 'posts newest first');
    is($os->{date}, $posts[1]->{date}, 'dated by the newest post');
    is($os->{url}, '/tags/open-source/', 'default URL, slugified');
    is($os->{filename}, '_output/tags/open-source/index.html', 'filename');
    is($os->{layout}, 'tag', 'layout');
    is($os->{extension}, '.html', 'site extension');
    is($os->{content}, '', 'no content');
    is($os->{source}, 'tag_pages (Open Source)', 'source names the setting');
    is($os->{generated}, 1, 'generated');
    is($os->{sitemap}, 'false', 'sitemap setting passed on');
    ok(!exists $os->{paginate}, 'not paginated without per_page');
    is_deeply(\%urls, { 'Open Source' => '/tags/open-source/', perl => '/tags/perl/' }, 'URLs recorded');

    %urls = ();
    @pages = App::Dapper::Collections::list_pages($d, 'category', { 'My Stuff' => [ @posts[0, 1, 2] ] }, \%urls,
        { layout => 'cat', per_page => 2 });
    is($pages[0]->{url}, '/My Stuff/', 'category URLs are not slugified');
    is($pages[0]->{category}, 'My Stuff', 'page.category');
    is_deeply($pages[0]->{paginate}, { items => $pages[0]->{posts}, per_page => 2 }, 'per_page sets up pagination');

    @pages = App::Dapper::Collections::list_pages($d, 'category', { blog => [ $posts[0] ] }, \%urls,
        { layout => 'cat', urlpattern => '/c/:category.html' });
    is($pages[0]->{url}, '/c/blog.html', 'urlpattern');
    is($pages[0]->{filename}, '_output/c/blog.html', 'file URL');

    is_deeply([ App::Dapper::Collections::list_pages($d, 'tag', {}, \%urls, { layout => 'x' }) ], [], 'no tags, no pages');

    eval { App::Dapper::Collections::list_pages($d, 'tag', {}, {}, {}) };
    is($@, "error: tag_pages in _config.yml needs a layout, e.g. layout: tag\n", 'needs a layout');
    eval { App::Dapper::Collections::list_pages($d, 'category', {}, {}, { layout => '' }) };
    is($@, "error: category_pages in _config.yml needs a layout, e.g. layout: category\n", 'an empty layout');
};

subtest 'generate: settings that are not a map' => sub {
    for my $kind (qw/ category tag /) {
        my $d = { output => '_output', config => '_config.yml', site => { pages => [], categories => {}, tags => {}, "${kind}_pages" => 'yes' } };
        eval { App::Dapper::Collections::generate($d) };
        is($@, "error: ${kind}_pages in _config.yml must be settings such as layout: $kind\n", "${kind}_pages: yes");
    }
    my $d = { output => '_output', config => '_config.yml', site => { pages => [ { url => '/' } ], categories => {}, tags => {} } };
    App::Dapper::Collections::generate($d);
    is_deeply($d->{site}->{category_pages}, {}, 'site.category_pages is an empty map when off');
    is_deeply($d->{site}->{tag_pages}, {}, 'site.tag_pages too');
    is(scalar @{ $d->{site}->{pages} }, 1, 'pages kept');
};

sub blog {
    my %files;
    for my $n (1 .. 5) {
        $files{"_source/blog/p$n.md"} = "---\ntitle: Post $n\ncategories: blog\ntags: [Perl Tips]\ndate: 2020-01-0${n}T00:00:00Z\n---\nPost $n.\n";
    }
    return %files;
}

subtest 'paginated category pages in a build' => sub {
    make_site({
        blog(),
        '_config.yml'       => "---\nname: x\nurl: https://example.com\ncategory_pages:\n  layout: list\n  per_page: 2\n  urlpattern: /topics/:category/\n  sitemap: false\ntag_pages:\n  layout: list\n  urlpattern: /t/:tag.html\n",
        '_layout/list.html' => "[% page.title %]|[% FOR p IN page.posts %][% p.title %],[% END %]|"
            . "[% paginator.page %]/[% paginator.total_pages %]|[% paginator.first_url %]|[% paginator.last_url %]",
    });
    my $d = quiet_build();
    is(slurp('_output/topics/blog/index.html'), 'blog|Post 5,Post 4,|1/3|/topics/blog/|/topics/blog/page/3/', 'page 1');
    is(slurp('_output/topics/blog/page/2/index.html'), 'blog|Post 3,Post 2,|2/3|/topics/blog/|/topics/blog/page/3/', 'page 2');
    is(slurp('_output/topics/blog/page/3/index.html'), 'blog|Post 1,|3/3|/topics/blog/|/topics/blog/page/3/', 'page 3');
    is(slurp('_output/t/perl-tips.html'), 'Perl Tips|Post 5,Post 4,Post 3,Post 2,Post 1,|/||', 'tag page as a file');
    is_deeply($d->{site}->{category_pages}, { blog => '/topics/blog/' }, 'site.category_pages');
    is_deeply($d->{site}->{tag_pages}, { 'Perl Tips' => '/t/perl-tips.html' }, 'site.tag_pages');
    my $sitemap = slurp('_output/sitemap.xml');
    unlike($sitemap, qr{/topics/}, 'sitemap: false on category pages');
    like($sitemap, qr{<loc>https://example\.com/t/perl-tips\.html</loc>}, 'tag pages in the sitemap');
    ok(!-e '_output/t/perl-tips.md', 'generated pages have no twin');
};

subtest 'check: generated pages need no title warning, and errors are typed setting' => sub {
    make_site({ blog(), '_config.yml' => "---\nname: x\nurl: https://example.com\ntag_pages:\n  layout: list\n",
                '_layout/list.html' => "<p>[% page.title %]</p>" });
    my $report = App::Dapper->new()->check();
    is_deeply([ grep { $_->{message} eq 'has no title' } @{ $report->{warnings} } ], [], 'no title warnings');

    make_site({ blog(), '_config.yml' => "---\nname: x\ntag_pages: yes\n" });
    $report = App::Dapper->new()->check();
    is_deeply([ map { "$_->{type} $_->{file}: $_->{message}" } @{ $report->{errors} } ],
        ['setting _config.yml: tag_pages in _config.yml must be settings such as layout: tag'], 'not a map');

    make_site({ blog(), '_config.yml' => "---\nname: x\ncategory_pages:\n  per_page: 2\n" });
    $report = App::Dapper->new()->check();
    is_deeply([ map { "$_->{type} $_->{file}: $_->{message}" } @{ $report->{errors} } ],
        ['setting _config.yml: category_pages in _config.yml needs a layout, e.g. layout: category'], 'no layout');
};

subtest 'paginate errors in a build' => sub {
    make_site({ blog(), '_source/index.html' => "---\ntitle: Home\npaginate:\n  per_page: none\n---\n" });
    eval { quiet_build() };
    is($@, "error: per_page in _source/index.html must be a whole number above 0\n", 'bad per_page stops the build');
};

subtest 'pages after the first are not checked for titles or quality' => sub {
    make_site({
        blog(),
        '_config.yml'        => "---\nname: x\nurl: https://example.com\n",
        '_layout/index.html' => qq{<html lang="en"><title>[% page.title %]</title>[% page.content %]</html>},
        '_source/list.html'  => "---\npaginate: 1\ndescription: All posts.\n---\n<p>list</p>\n",
    });
    my $report = App::Dapper->new()->check();
    my @untitled = map { $_->{file} } grep { $_->{message} eq 'has no title' } @{ $report->{warnings} };
    is_deeply(\@untitled, ['_source/list.html'], 'only page 1 of five is reported');
};

done_testing();
