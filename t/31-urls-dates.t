use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use POSIX ();

binmode(Test::More->builder->$_, ':encoding(UTF-8)') for qw(output failure_output todo_output);

sub pages_by_source {
    my ($d) = @_;
    return { map { $_->{source} => $_ } @{ $d->{site}->{pages} } };
}

# one_page($front_matter, %opts) - build a site with a single page and return
# that page
sub one_page {
    my ($fm, %files) = @_;
    make_site({ '_source/p.md' => "---\n$fm\n---\nx\n", %files });
    my $d = quiet_build();
    return $d->{site}->{pages}->[0];
}

sub capture {
    my ($code) = @_;
    my $out = '';
    open(my $fh, '>', \$out) or die;
    my $old = select $fh;
    my $ok = eval { $code->(); 1 };
    my $err = $@;
    select $old;
    die $err unless $ok;
    return $out;
}

subtest 'expand_urlpattern' => sub {
    my $x = \&App::Dapper::expand_urlpattern;
    my %page = (category => 'blog', tag => 'perl', year => 2014, month => '05', day => '02',
                hour => '09', minute => '08', second => '07', slug => 'hello');
    is($x->('/:category/:year/:month/:slug/', \%page), '/blog/2014/05/hello/', 'the default pattern');
    is($x->('/:year/:month/:day/:hour/:minute/:second/', \%page), '/2014/05/02/09/08/07/', 'every date token');
    is($x->('/:tag/:slug.html', \%page), '/perl/hello.html', ':tag');
    is($x->('/:year-:month-:day/:hour:minute:second-:slug', \%page), '/2014-05-02/090807-hello', 'tokens next to each other');
    is($x->('/:slug-:slug/', \%page), '/hello-hello/', 'a token used twice');
    is($x->('/:slugger/:years/:categoryx/', \%page), '/:slugger/:years/:categoryx/', 'longer words are not tokens');
    is($x->('/:nonsense/:slug', \%page), '/:nonsense/hello', 'unknown tokens are left');
    is($x->('/:category/:slug/', { slug => 's' }), '/s/', 'a missing value is removed with its slash');
    is($x->('/:category/:slug/', { slug => 's', category => undef }), '/s/', 'an undef value');
    is($x->('//:category//:slug//', { slug => 's' }), '/s/', 'runs of slashes squeezed');
    is($x->(':slug.html', { slug => 'x' }), '/x.html', 'leading slash added');
    is($x->(':year:month', { year => 2014, month => '05' }), '/201405', 'no slashes at all');
    is($x->('', {}), '/', 'empty pattern');
    is($x->(undef, {}), '/', 'undef pattern');
    is($x->('/fixed/path.html', \%page), '/fixed/path.html', 'no tokens');
    is($x->('/:category/', { category => 'a b' }), '/a b/', 'values are not changed');
    is($x->('/:category/', { category => 'Zoë' }), '/Zoë/', 'Unicode values');
    is($x->('/:category/', { category => 0 }), '/0/', 'a value of 0 is kept');
    is($x->('/:category/:slug/', { category => '', slug => '' }), '/', 'all empty');
    is($x->('/:slug/', { slug => '$1 \\1' }), '/$1 \\1/', 'replacement text is literal');
};

subtest 'page URLs from urlpattern and categories' => sub {
    make_site({
        '_source/a.md' => "---\ntitle: A\ncategories: blog\ntags: solo\ndate: 2014-05-02T10:30:45\ntimezone: UTC\n"
                        . "urlpattern: /:tag/:category/:year-:month-:day/:hour:minute:second/:slug.html\n---\nx",
        '_source/b.md' => "---\ntitle: Tagged\ntag: mytag\ndate: 2014-05-02\ntimezone: UTC\nurlpattern: /:tag/:slug/\nextension: .htm\n---\nx",
        '_source/c.md' => "---\ntitle: Café Ünï\ndate: 2014-05-02\ntimezone: UTC\nurlpattern: /:nonsense/:slug\n---\nx",
        '_source/e.md' => "---\ntitle: E\ndate: 2014-05-02\ntimezone: UTC\nurlpattern: /:slugger/:slug/:year\n---\nx",
        '_source/f.md' => "---\ntitle: F\ndate: 2014-05-02T23:30:00-05:00\ntimezone: Asia/Tokyo\ncategories: x\n---\nx",
        '_source/g.md' => "---\ntitle: Spaced\ncategories: My News\ndate: 2014-05-02\ntimezone: UTC\n---\nx",
        '_source/h.md' => "---\ntitle: Zero\ncategories: 0\ndate: 2014-05-02\ntimezone: UTC\n---\nx",
        '_source/sub/dir/i.md' => "---\ntitle: Deep\ncategories: [a, b]\ndate: 2014-05-02\ntimezone: UTC\n---\nx",
        '_source/j.md' => "---\ntitle: J\ncategories: []\ndate: 2014-05-02\ntimezone: UTC\n---\nx",
        '_source/k.md' => "---\ntitle: K\ncategories: ''\ndate: 2014-05-02\ntimezone: UTC\n---\nx",
    });
    my $d = quiet_build();
    my $p = pages_by_source($d);

    is($p->{'_source/a.md'}->{url}, '/blog/2014-05-02/103045/a.html',
        ':tag comes from a "tag" setting, not from tags');
    is($p->{'_source/a.md'}->{filename}, '_output/blog/2014-05-02/103045/a.html', 'a URL with a file name');
    is($p->{'_source/b.md'}->{url}, '/mytag/tagged/', 'a tag setting fills :tag');
    is($p->{'_source/b.md'}->{filename}, '_output/mytag/tagged/index.htm', 'the page extension names the index file');
    is($p->{'_source/c.md'}->{url}, '/:nonsense/cafe-uni', 'unknown tokens stay in the URL');
    is($p->{'_source/c.md'}->{filename}, '_output/:nonsense/cafe-uni', 'and the file name, which has no extension added');
    is($p->{'_source/e.md'}->{url}, '/:slugger/e/2014', 'token boundaries');
    is($p->{'_source/f.md'}->{url}, '/x/2014/05/f/', 'a date with an offset is not moved into the page time zone');
    is($p->{'_source/g.md'}->{url}, '/My News/2014/05/spaced/', 'categories are used as written');
    is($p->{'_source/g.md'}->{filename}, '_output/My News/2014/05/spaced/index.html', 'including the file name');
    is($p->{'_source/h.md'}->{url}, '/0/2014/05/zero/', 'a category of 0');
    is($p->{'_source/sub/dir/i.md'}->{url}, '/a/2014/05/deep/', 'the source directory does not matter');
    is($p->{'_source/j.md'}->{url}, '/j.html', 'an empty list of categories is a plain page');
    is($p->{'_source/k.md'}->{url}, '/k.html', 'an empty category is a plain page');
    ok(-f '_output/My News/2014/05/spaced/index.html', 'written to disk');
    ok(-f '_output/:nonsense/cafe-uni', 'odd names are written too');
};

subtest 'urlpattern settings' => sub {
    make_site({
        '_config.yml'  => "---\nname: x\nurlpattern: /posts/:slug/\n",
        '_source/a.md' => "---\ntitle: A\ncategories: blog\ndate: 2014-01-01\n---\nx",
        '_source/b.md' => "---\ntitle: B\ndate: 2014-01-01\n---\nx",
        '_source/c.md' => "---\ntitle: C\nurlpattern: /own/:slug.html\ncategories: blog\ndate: 2014-01-01\n---\nx",
    });
    my $p = pages_by_source(quiet_build());
    is($p->{'_source/a.md'}->{url}, '/posts/a/', 'the site urlpattern applies to categorized pages');
    is($p->{'_source/b.md'}->{url}, '/b.html', 'but not to pages without categories');
    is($p->{'_source/c.md'}->{url}, '/own/c.html', 'a page urlpattern wins');

    my $page = one_page("title: Empty\nurlpattern: ''\ndate: 2014-01-01");
    is($page->{url}, '/', 'an empty urlpattern is the root');
    is($page->{filename}, '_output/index.html', 'and writes the root index');

    $page = one_page("title: E\nurlpattern: /x/\nextension: ''\ndate: 2014-01-01");
    is($page->{filename}, '_output/x/index', 'an empty extension for an index file');

    $page = one_page("title: N\nurlpattern: /x/\nextension: ~\ndate: 2014-01-01");
    is($page->{extension}, '.html', 'a null extension uses the site extension');

    make_site({
        '_config.yml'  => "---\nname: x\nextension: ''\n",
        '_source/a.md' => "---\ntitle: A\ndate: 2014-01-01\n---\nx",
        '_source/d/index.md' => "---\ntitle: I\ndate: 2014-01-01\n---\nx",
    });
    $p = pages_by_source(quiet_build());
    is($p->{'_source/a.md'}->{filename}, '_output/a', 'an empty site extension');
    is($p->{'_source/a.md'}->{url}, '/a', 'url');
    is($p->{'_source/d/index.md'}->{url}, '/d/index', 'index is kept in the URL without an extension');

    make_site({
        '_config.yml'  => "---\nname: x\nextension: ~\n",
        '_source/a.md' => "---\ntitle: A\ndate: 2014-01-01\n---\nx",
    });
    is(quiet_build()->{site}->{pages}->[0]->{filename}, '_output/a', 'a null site extension is no extension');
};

subtest 'plain page URLs' => sub {
    make_site({
        '_source/index.md'          => "---\ndate: 2014-01-01\n---\nx",
        '_source/about/index.md'    => "---\ndate: 2014-01-01\n---\nx",
        '_source/a/b/c/page.md'     => "---\ndate: 2014-01-01\n---\nx",
        '_source/my page.md'        => "---\ndate: 2014-01-01\n---\nx",
        '_source/Café.md'           => "---\ndate: 2014-01-01\n---\nx",
        '_source/index.html'        => "---\ndate: 2014-01-01\nextension: .htm\n---\nx",
        '_source/reindex.md'        => "---\ndate: 2014-01-01\n---\nx",
        '_source/v1.2/notes.txt.md' => "---\ndate: 2014-01-01\n---\nx",
    });
    # _source/index.html and _source/index.md both want /; use separate sites
    unlink '_source/index.html';
    my $p = pages_by_source(quiet_build());
    is($p->{'_source/index.md'}->{url}, '/', 'root index');
    is($p->{'_source/about/index.md'}->{url}, '/about/', 'directory index');
    is($p->{'_source/about/index.md'}->{filename}, '_output/about/index.html', 'directory index file');
    is($p->{'_source/a/b/c/page.md'}->{url}, '/a/b/c/page.html', 'nested page');
    is($p->{'_source/a/b/c/page.md'}->{dirname}, '_output/a/b/c/', 'dirname of a nested page');
    is($p->{'_source/my page.md'}->{url}, '/my page.html', 'spaces kept');
    is($p->{'_source/my page.md'}->{slug}, 'my-page', 'but slugged');
    is($p->{'_source/Café.md'}->{url}, '/Café.html', 'Unicode file name');
    is($p->{'_source/Café.md'}->{slug}, 'cafe', 'and its slug');
    is($p->{'_source/reindex.md'}->{url}, '/reindex.html', 'only a whole "index" is removed');
    is($p->{'_source/v1.2/notes.txt.md'}->{url}, '/v1.2/notes.txt.html', 'only the last extension is replaced');
    is($p->{'_source/v1.2/notes.txt.md'}->{slug}, 'notestxt', 'slug from the stem');
    ok(-f App::Dapper::Utils::name_bytes('_output/Café.html'), 'Unicode file written');

    make_site({ '_source/index.html' => "---\ndate: 2014-01-01\nextension: .htm\n---\nx" });
    my $page = quiet_build()->{site}->{pages}->[0];
    is($page->{url}, '/', 'index with the page extension is the directory');
    is($page->{filename}, '_output/index.htm', 'written with the page extension');

    make_site({ '_source/index.md' => "---\ndate: 2014-01-01\n---\nx" });
    $page = quiet_build(undef, 'out/deep/')->{site}->{pages}->[0];
    is($page->{url}, '/', 'URL is relative to a nested output directory');
    is($page->{filename}, 'out/deep/index.html', 'filename');
};

subtest 'slugs' => sub {
    my %cases = (
        "title: Hello World"          => 'hello-world',
        "title: 'Café: A Story'"      => 'cafe-a-story',
        "title: 日本語"                => 'p',
        "title: ''"                   => 'p',
        "title: '!!!'"                => 'p',
        "title: 0"                    => '0',
        "title: ~"                    => 'p',
        "title: 2014"                 => '2014',
        "title: '  Spaces  '"         => 'spaces',
        "title: Hello\nslug: custom"  => 'hello',
    );
    for my $fm (sort keys %cases) {
        my $page = one_page("$fm\ndate: 2014-01-01");
        is($page->{slug}, $cases{$fm}, "slug for [$fm]");
    }
    make_site({ '_source/My File_Name.md' => "---\ndate: 2014-01-01\n---\nx",
                '_source/日本.md' => "---\ndate: 2014-01-01\n---\nx" });
    my $p = pages_by_source(quiet_build());
    is($p->{'_source/My File_Name.md'}->{slug}, 'my-file_name', 'slug from a file name');
    is($p->{'_source/日本.md'}->{slug}, '', 'no slug can be made at all');
};

subtest 'categories and tags' => sub {
    make_site({
        '_source/a.md' => "---\ntitle: A\ncategories: [news, tech]\ntags: [perl, web]\ndate: 2014-03-01\ntimezone: UTC\n---\nx",
        '_source/b.md' => "---\ntitle: B\ncategories: news\ntags: perl\ndate: 2014-01-01\ntimezone: UTC\n---\nx",
        '_source/c.md' => "---\ntitle: C\ncategories: [news]\ntags: [web, ~, '', {x: 1}]\ndate: 2014-02-01\ntimezone: UTC\n---\nx",
        '_source/d.md' => "---\ntitle: D\ntags: [solo]\ndate: 2014-04-01\ntimezone: UTC\n---\nx",
        '_source/e.md' => "---\ntitle: E\ncategories: [~, '', tech]\ndate: 2013-01-01\ntimezone: UTC\n---\nx",
        '_source/f.md' => "---\ntitle: F\ntags: {not: a list}\ndate: 2014-04-01\ntimezone: UTC\n---\nx",
        '_source/g.md' => "---\ntitle: G\ntags: 0\ndate: 2014-04-01\ntimezone: UTC\n---\nx",
        '_layout/index.html' => '[% FOREACH p IN site.categories.news %][% p.title %][% END %]|'
                              . '[% FOREACH p IN site.tags.perl %][% p.title %][% END %]',
    });
    my $d = quiet_build();
    my $cats = $d->{site}->{categories};
    my $tags = $d->{site}->{tags};
    is_deeply([sort keys %$cats], [qw(news tech)], 'categories');
    is_deeply([map { $_->{title} } @{ $cats->{news} }], [qw(B C A)], 'sorted by date');
    is_deeply([map { $_->{title} } @{ $cats->{tech} }], [qw(E A)], 'empty categories skipped; first real one used');
    is(pages_by_source($d)->{'_source/e.md'}->{url}, '/tech/2013/01/e/', 'URL uses the first non-empty category');
    is_deeply([sort keys %$tags], [qw(0 perl solo web)], 'tags; refs, empties and nulls skipped');
    is_deeply([map { $_->{title} } @{ $tags->{perl} }], [qw(B A)], 'tags sorted by date');
    is_deeply([map { $_->{title} } @{ $tags->{web} }], [qw(C A)], 'tag from a list');
    is_deeply([map { $_->{title} } @{ $tags->{0} }], ['G'], 'a tag of 0');
    is($cats->{news}->[0], pages_by_source($d)->{'_source/b.md'}, 'the same page hash as site.pages');
    is(slurp('_output/news/2014/03/a/index.html'), 'BCA|BA', 'available to templates');

    make_site({ '_source/p.md' => "---\ntitle: T\ncategories: {a: 1}\ndate: 2014-01-01\n---\nx" });
    my $dd = quiet_build();
    is_deeply([keys %{ $dd->{site}->{categories} }], [], 'a hash category is ignored');
    is($dd->{site}->{pages}->[0]->{url}, '/p.html', 'and the page is a plain page');
    make_site({ '_source/p.md' => "---\ntitle: T\ncategories: [[a]]\ndate: 2014-01-01\n---\nx" });
    $dd = quiet_build();
    is_deeply([keys %{ $dd->{site}->{categories} }], [], 'a nested list category is ignored');
};

subtest 'dates' => sub {
    my %cases = (
        'date: 2014-05-02T10:30:00'       => '2014-05-02T10:30:00+00:00',
        'date: 2014-05-02 10:30:00'       => '2014-05-02T10:30:00+00:00',
        'date: 2014-05-02 10:30'          => '2014-05-02T10:30:00+00:00',
        'date: 2014-05-02'                => '2014-05-02T00:00:00+00:00',
        "date: '2014-05-02'"              => '2014-05-02T00:00:00+00:00',
        'date: 2014-05-02T10:30:00Z'      => '2014-05-02T10:30:00+00:00',
        'date: 2014-05-02T10:30:00+02:00' => '2014-05-02T10:30:00+02:00',
        'date: 2014'                      => '2014-01-01T00:00:00+00:00',
    );
    for my $fm (sort keys %cases) {
        my $page = one_page("$fm\ntimezone: UTC");
        is($page->{date}->xmlschema, $cases{$fm}, "[$fm]");
    }

    make_site({ '_source/p.md' => "---\ndate: ''\n---\nx" });
    eval { quiet_build() };
    like($@, qr/^error: could not understand the date "" in "_source\/p\.md"/, 'an empty date');

    make_site({ '_source/p.md' => "---\ndate: May 2nd\n---\nx" });
    eval { quiet_build() };
    is($@, qq{error: could not understand the date "May 2nd" in "_source/p.md". Use the ISO 8601 format, e.g. 2014-05-02T10:30:00\n},
        'an unreadable date');

    make_site({ '_source/p.md' => "---\ndate: 2014-05-02T10:30:00\ntimezone: UTC\n---\nx",
                '_layout/index.html' => '[% page.date %]|[% page.date.year %]|[% page.date.strftime("%d %b %Y") %]|[% page.date.epoch %]' });
    quiet_build();
    is(slurp('_output/p.html'), '2014-05-02T10:30:00|2014|02 May 2014|1399026600', 'date methods in templates');
};

subtest 'dates from the file' => sub {
    local $ENV{TZ} = 'UTC';
    POSIX::tzset();
    make_site({
        '_source/nodate.md' => "---\ntitle: x\n---\nx",
        '_source/null.md'   => "---\ntitle: x\ndate: ~\n---\nx",
    });
    utime 1_000_000_000, 1_000_000_000, '_source/nodate.md', '_source/null.md' or die;
    my $p = pages_by_source(quiet_build());
    is($p->{'_source/nodate.md'}->{date}->xmlschema, '2001-09-09T01:46:40+00:00', 'the modification time is the date');
    is($p->{'_source/null.md'}->{date}->xmlschema, '2001-09-09T01:46:40+00:00', 'a null date too');
    is($p->{'_source/nodate.md'}->{timezone}->name, 'UTC', 'in the local time zone');
    POSIX::tzset();
};

subtest 'time zones' => sub {
    make_site({
        '_config.yml'      => "---\nname: x\ntimezone: America/Chicago\n",
        '_source/site.md'  => "---\ndate: 2014-05-02T10:30:00\n---\nx",
        '_source/page.md'  => "---\ndate: 2014-05-02T10:30:00\ntimezone: Asia/Tokyo\n---\nx",
        '_source/given.md' => "---\ndate: 2014-05-02T10:30:00+02:00\ntimezone: Asia/Tokyo\n---\nx",
        '_source/z.md'     => "---\ndate: 2014-05-02T10:30:00Z\n---\nx",
        '_source/winter.md' => "---\ndate: 2014-01-02T10:30:00\n---\nx",
        '_source/empty.md' => "---\ndate: 2014-01-02T10:30:00\ntimezone: ''\n---\nx",
        '_source/utc.md'   => "---\ndate: 2014-01-02T10:30:00\ntimezone: UTC\n---\nx",
        '_source/offset.md' => "---\ndate: 2014-01-02T10:30:00\ntimezone: '+0530'\n---\nx",
        '_source/float.md' => "---\ndate: 2014-01-02T10:30:00\ntimezone: floating\n---\nx",
        '_layout/index.html' => '[% page.date.xmlschema %] [% page.timezone.name %] [% page.day %]',
    });
    quiet_build();
    is(slurp('_output/site.html'), '2014-05-02T10:30:00-05:00 America/Chicago 02', 'the site time zone (summer)');
    is(slurp('_output/winter.html'), '2014-01-02T10:30:00-06:00 America/Chicago 02', 'the site time zone (winter)');
    is(slurp('_output/page.html'), '2014-05-02T10:30:00+09:00 Asia/Tokyo 02', 'the page time zone wins');
    is(slurp('_output/given.html'), '2014-05-02T10:30:00+02:00 Asia/Tokyo 02', 'an offset in the date is kept, the zone recorded');
    is(slurp('_output/z.html'), '2014-05-02T10:30:00+00:00 America/Chicago 02', 'Z is kept');
    is(slurp('_output/empty.html'), '2014-01-02T10:30:00-06:00 America/Chicago 02', 'an empty page time zone uses the site');
    is(slurp('_output/utc.html'), '2014-01-02T10:30:00+00:00 UTC 02', 'UTC');
    is(slurp('_output/offset.html'), '2014-01-02T10:30:00+05:30 +0530 02', 'an offset as a time zone');
    is(slurp('_output/float.html'), '2014-01-02T10:30:00+00:00 floating 02', 'floating');

    {
        local $ENV{TZ} = 'Asia/Tokyo';
        make_site({ '_source/p.md' => "---\ndate: 2014-05-02T10:30:00\n---\nx" });
        my $page = quiet_build()->{site}->{pages}->[0];
        is($page->{date}->xmlschema, '2014-05-02T10:30:00+09:00', 'without any setting the local time zone is used');
        is($page->{timezone}->name, 'Asia/Tokyo', 'page.timezone is the local zone');
    }

    make_site({ '_config.yml' => "---\nname: x\ntimezone: Nowhere/Land\n", '_source/a.md' => "---\ndate: 2014-01-01\n---\nx" });
    eval { quiet_build() };
    is($@, qq{error: unknown time zone "Nowhere/Land" in "_source/a.md"\n}, 'a bad site time zone names the page');

    make_site({ '_source/a.md' => "---\ndate: 2014-01-01\ntimezone: +0530\n---\nx" });
    eval { quiet_build() };
    is($@, qq{error: unknown time zone "530" in "_source/a.md"\n}, 'an unquoted offset is a number in YAML');

    # A DateTime::TimeZone object set from Perl is used as it is
    make_site({ '_source/a.md' => "---\ndate: 2014-01-01T12:00:00\n---\nx" });
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->read_project();
    $d->{site}->{timezone} = DateTime::TimeZone->new(name => 'Europe/Paris');
    $d->read_templates();
    $d->{problems} = []; $d->{written} = {}; $d->{page_owner} = {}; $d->{held} = [];
    $d->transform();
    is($d->{site}->{pages}->[0]->{date}->xmlschema, '2014-01-01T12:00:00+01:00', 'a time zone object');

    make_site({ '_source/a.md' => "---\ndate: 2014-01-01\ntimezone: [x]\n---\nx" });
    eval { quiet_build() };
    like($@, qr/^error: unknown time zone/, 'a list is not a time zone');
};

subtest 'drafts and scheduled pages' => sub {
    my %site = (
        '_source/past.md'    => "---\ntitle: Past\ndate: 2000-01-01\ntimezone: UTC\n---\nx",
        '_source/future.md'  => "---\ntitle: Future\ndate: 2999-01-01\ntimezone: UTC\n---\nx",
        '_source/draft.md'   => "---\ntitle: Draft\ndraft: true\ndate: 2000-01-01\ntimezone: UTC\n---\nx",
        '_source/nodraft.md' => "---\ntitle: No\ndraft: no\ndate: 2000-01-01\ntimezone: UTC\n---\nx",
    );
    make_site({ %site });
    my $out = capture(sub { App::Dapper->new()->build() });
    like($out, qr/^Held back _source\/draft\.md \(draft\)$/m, 'draft message');
    like($out, qr/^Held back _source\/future\.md \(scheduled for 2999-01-01T00:00:00\)$/m, 'scheduled message with its date');
    my $d = quiet_build();
    is_deeply([sort map { $_->{title} } @{ $d->{site}->{pages} }], [qw(No Past)], 'only published pages');
    is_deeply([map { "$_->{file}:$_->{reason}" } @{ $d->{held} }],
        ['_source/draft.md:draft', '_source/future.md:scheduled'], 'held list');
    isa_ok($d->{held}->[1]->{date}, 'DateTime', 'held date');
    is_deeply([map { $_->{id} } @{ $d->{site}->{pages} }], [1, 2], 'held pages use no ids');

    make_site({ %site, '_config.yml' => "---\nname: x\nfuture: true\n" });
    $d = quiet_build();
    is_deeply([sort map { $_->{title} } @{ $d->{site}->{pages} }], [qw(Future No Past)], 'future: true publishes future pages');

    make_site({ %site, '_config.yml' => "---\nname: x\nfuture: 'off'\n" });
    $d = quiet_build();
    is_deeply([sort map { $_->{title} } @{ $d->{site}->{pages} }], [qw(No Past)], 'future: off');

    make_site({ %site });
    $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{drafts} = 1;
    $d->build();
    is_deeply([sort map { $_->{title} } @{ $d->{site}->{pages} }], [qw(Draft Future No Past)], 'everything with drafts on');
    is_deeply($d->{held}, [], 'nothing held');
};

done_testing();
