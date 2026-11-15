use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Defaults;

binmode(Test::More->builder->$_, ':encoding(UTF-8)') for qw(output failure_output todo_output);

# capture(sub) - run code and return what it printed to STDOUT
sub capture {
    my ($code) = @_;
    my $out = '';
    open(my $fh, '>', \$out) or die;
    my $old = select $fh;
    my $ok = eval { $code->(); 1 };
    my $err = $@;
    select $old;
    close $fh;
    utf8::decode($out);
    die $err unless $ok;
    return $out;
}

sub build_with {
    my (%opts) = @_;
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{$_} = $opts{$_} for keys %opts;
    $d->build();
    return $d;
}

subtest 'Defaults' => sub {
    my $defaults = App::Dapper::Defaults::get_defaults();
    my %flags = map { $_ => delete $defaults->{$_} } qw(markdown_twins llms_txt sitemap);
    ok($flags{$_}, "$_ is on") for sort keys %flags;
    is_deeply($defaults, {
        urlpattern     => '/:category/:year/:month/:slug/',
        source         => '_source/',
        output         => '_output/',
        layout         => '_layout/',
        data_dir       => '_data',
        ignore         => ['^\.', '^_', '^dapper$'],
        extension      => '.html',
    }, 'every other default');
    $defaults->{source} = 'changed';
    push @{ $defaults->{ignore} }, 'x';
    my $again = App::Dapper::Defaults::get_defaults();
    is($again->{source}, '_source/', 'each call returns a fresh copy');
    is(scalar @{ $again->{ignore} }, 3, 'including nested lists');
};

subtest 'new' => sub {
    my $d = App::Dapper->new();
    isa_ok($d, 'App::Dapper');
    is($d->{source}, '_source', 'default source');
    is($d->{output}, '_output', 'default output');
    is($d->{layout}, '_layout', 'default layout');
    is($d->{config}, '_config.yml', 'default config');
    is($d->{quiet}, 0, 'not quiet');
    is($d->{created}, 1, 'created');
    is_deeply($d->{explicit}, { source => '', output => '', layout => '', config => '' }, 'nothing explicit');
    isa_ok($d->{site}->{time}, 'App::Dapper::Date', 'site.time');
    isnt($d->{site}->{time}->time_zone->name, 'floating', 'site.time has a time zone');
    is_deeply($d->{site}->{pages}, [], 'no pages');
    is_deeply($d->{site}->{categories}, {}, 'no categories');
    is_deeply($d->{site}->{tags}, {}, 'no tags');
    is_deeply($d->{layout_content}, {}, 'no layouts');
    is_deeply($d->{static_files}, [], 'no static files');
    is($d->{id}, 0, 'ids start at zero');
    is($d->{site}->{urlpattern}, '/:category/:year/:month/:slug/', 'defaults are in the site hash');

    my $e = App::Dapper->new('s', 'o', 'l', 'c.yml');
    is_deeply([@$e{qw(source output layout config)}], ['s', 'o', 'l', 'c.yml'], 'explicit values');
    is_deeply($e->{explicit}, { source => 1, output => 1, layout => 1, config => 1 }, 'all explicit');

    my $p = App::Dapper->new(undef, 'o', undef, undef);
    is_deeply($p->{explicit}, { source => '', output => 1, layout => '', config => '' }, 'undef is not explicit');
    is($p->{source}, '_source', 'undef falls back to the default');

    my $z = App::Dapper->new('', '0');
    is($z->{explicit}->{source}, 1, 'an empty string is explicit');
    is($z->{output}, '0', 'so is 0');
};

subtest 'directory precedence' => sub {
    make_site({
        '_config.yml'          => "---\nname: x\nsource: src/\noutput: ./public//\nlayout: lay\n",
        'src/index.md'         => "---\ntitle: Hi\n---\nHi\n",
        'lay/index.html'       => 'L:[% page.content %]',
        'other/index.md'       => "---\ntitle: Other\n---\nOther\n",
        'otherlay/index.html'  => 'O:[% page.content %]',
    });
    my $d = quiet_build();
    is($d->{source}, 'src', 'config source, canonical');
    is($d->{output}, 'public', 'config output, canonical');
    is($d->{layout}, 'lay', 'config layout');
    is_deeply([@{ $d->{site} }{qw(source output layout)}], ['src', 'public', 'lay'], 'site.* matches');
    is(slurp('public/index.html'), "L:<p>Hi</p>\n", 'built from the config directories');

    $d = quiet_build('other/', 'out', 'otherlay');
    is_deeply([@$d{qw(source output layout)}], ['other', 'out', 'otherlay'], 'explicit wins over the config file');
    is(slurp('out/index.html'), "O:<p>Other</p>\n", 'built from the explicit directories');

    $d = quiet_build(undef, 'mixed');
    is_deeply([@$d{qw(source output layout)}], ['src', 'mixed', 'lay'], 'one explicit, the rest from the config');

    make_site({ '_source/index.md' => "---\ntitle: d\n---\nd\n" });
    $d = quiet_build();
    is_deeply([@$d{qw(source output layout)}], ['_source', '_output', '_layout'], 'defaults without trailing slashes');
    is($d->{site}->{source}, '_source', 'site.source too');

    make_site({
        'alt.yml'       => "---\nname: Alt\noutput: altout\n",
        '_source/a.md'  => "---\ntitle: a\n---\n[% site.name %]\n",
        '_layout/index.html' => '[% site.name %]',
    });
    $d = quiet_build(undef, undef, undef, 'alt.yml');
    is($d->{config}, 'alt.yml', 'another config file');
    is(slurp('altout/a.html'), 'Alt', 'read from it');
};

subtest 'project file errors' => sub {
    make_site({ '_config.yml' => "---\n- a\n- b\n", '_source/a.md' => "---\n---\nx" });
    eval { quiet_build() };
    is($@, qq{error: "_config.yml" must contain key: value pairs\n}, 'a list');

    make_site({ '_config.yml' => "just words\n", '_source/a.md' => "---\n---\nx" });
    eval { quiet_build() };
    is($@, qq{error: "_config.yml" must contain key: value pairs\n}, 'a scalar');

    make_site({ '_config.yml' => "name: [broken\n" });
    eval { quiet_build() };
    like($@, qr/^error: could not parse "_config\.yml": /, 'invalid YAML');

    for my $key (qw(source output layout)) {
        make_site({ '_config.yml' => "---\n$key: ''\n" });
        eval { quiet_build() };
        is($@, qq{error: "$key" must be defined in project file\n}, "empty $key");

        make_site({ '_config.yml' => "---\n$key: ~\n" });
        eval { quiet_build() };
        is($@, qq{error: "$key" must be defined in project file\n}, "null $key");
    }

    make_site({}, bare => 1);
    eval { quiet_build() };
    is($@, qq{error: could not find the project file "_config.yml". Run "dapper init" to create a new project.\n},
        'missing project file');

    eval { quiet_build(undef, undef, undef, 'nope.yml') };
    like($@, qr/could not find the project file "nope\.yml"/, 'missing named project file');

    # read_project(1), as serve uses, allows a missing project file
    my $d = App::Dapper->new(undef, 'served');
    $d->read_project(1);
    is($d->{output}, 'served', 'optional project file');
    is_deeply($d->{configured}, {}, 'nothing configured');
    is_deeply($d->{site}->{data}, {}, 'no data');

    make_site({ '_config.yml' => '' });
    $d = App::Dapper->new();
    $d->read_project();
    is_deeply($d->{configured}, {}, 'an empty project file is fine');
    is($d->{source}, '_source', 'and uses the defaults');

    make_site({ '_config.yml' => "---\nname: N\nextension: .htm\nnew_key: v\n" });
    $d = App::Dapper->new();
    $d->read_project();
    is_deeply($d->{configured}, { name => 1, extension => 1, new_key => 1 }, 'configured keys remembered');
    is($d->{site}->{extension}, '.htm', 'project file overrides a default');
    is($d->{site}->{new_key}, 'v', 'and adds its own keys');
    ok($d->{site}->{sitemap}, 'other defaults kept');
};

subtest 'missing directories' => sub {
    make_site({});
    eval { quiet_build() };
    is($@, qq{error: source directory "_source" does not exist\n}, 'missing source directory');

    make_site({ '_source/a.md' => "---\n---\nx" }, bare => 1);
    spew('_config.yml', "---\nname: x\n");
    eval { quiet_build() };
    is($@, qq{error: could not open layout directory "_layout"\n}, 'missing layout directory');

    make_site({ '_source/a.md' => "---\n---\nx" });
    my $d = App::Dapper->new();
    $d->read_project();
    eval { $d->walk('nowhere', '_output') };
    is($@, qq{error: could not open source directory "nowhere"\n}, 'walk on a missing directory');
};

subtest 'site.data' => sub {
    make_site({
        '_data/people.yml'          => "- Ann\n- Bob\n",
        '_data/colors.yaml'         => "main: blue\n",
        '_data/numbers.json'        => '{"one": 1, "list": [1, 2, 3], "name": "Zoë"}',
        '_data/UPPER.YML'           => "up: true\n",
        '_data/Shout.JSON'          => '[true]',
        '_data/menus/main.yml'      => "- home\n",
        '_data/menus/deep/more.json' => '{"x": "y"}',
        '_data/empty.yml'           => '',
        '_data/notes.txt'           => "ignored\n",
        '_data/.hidden.yml'         => "a: b\n",
        '_data/.dotdir/x.yml'       => "a: b\n",
        '_source/a.md'              => "---\n---\nx",
    });
    my $d = App::Dapper->new();
    $d->read_project();
    is_deeply([sort keys %{ $d->{site}->{data} }], [qw(Shout UPPER colors empty menus numbers people)],
        'files and directories, no others');
    $d = quiet_build();
    my $data = $d->{site}->{data};
    is_deeply([sort keys %$data], [qw(Shout UPPER colors empty menus numbers people)], 'still no others after a build');
    is_deeply($data->{people}, ['Ann', 'Bob'], '.yml');
    is_deeply($data->{colors}, { main => 'blue' }, '.yaml');
    is_deeply($data->{numbers}, { one => 1, list => [1, 2, 3], name => 'Zoë' }, '.json, decoded as characters');
    is_deeply([keys %{ $data->{UPPER} }], ['up'], 'upper-case .YML');
    ok($data->{UPPER}->{up}, 'a YAML true');
    is(scalar @{ $data->{Shout} }, 1, 'upper-case .JSON');
    ok($data->{Shout}->[0], 'a JSON true');
    is_deeply($data->{menus}, { main => ['home'], deep => { more => { x => 'y' } } }, 'directories nest');
    ok(exists $data->{empty} && !defined $data->{empty}, 'an empty YAML file is undef');

    is_deeply(App::Dapper::read_data('_data/menus'), { main => ['home'], deep => { more => { x => 'y' } } },
        'read_data called directly');

    make_site({ '_data/bad.yml' => "a: [1\n", '_source/a.md' => "---\n---\nx" });
    eval { quiet_build() };
    like($@, qr/^error: could not parse the data file "_data\/bad\.yml": /, 'bad YAML names the file');

    make_site({ '_data/sub/bad.json' => "{oops", '_source/a.md' => "---\n---\nx" });
    eval { quiet_build() };
    like($@, qr/^error: could not parse the data file "_data\/sub\/bad\.json": /, 'bad JSON in a subdirectory');

    make_site({ '_config.yml' => "---\nname: x\ndata_dir: ./info/\n", 'info/x.yml' => "v: 1\n",
                '_data/ignored.yml' => "v: 2\n", '_source/a.md' => "---\n---\nx" });
    $d = App::Dapper->new();
    $d->read_project();
    is($d->{data_dir}, 'info', 'data_dir canonical');
    is_deeply($d->{site}->{data}, { x => { v => 1 } }, 'only the configured data directory is read');

    make_site({ '_source/a.md' => "---\n---\nx" });
    $d = App::Dapper->new();
    $d->read_project();
    is_deeply($d->{site}->{data}, {}, 'no data directory is an empty hash');
};

subtest 'build' => sub {
    make_site({ '_source/a.md' => "---\ntitle: A\n---\nx" });
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    is($d->build(), $d, 'build returns the object');
    is_deeply($d->{problems}, [], 'no problems');
    is_deeply($d->{held}, [], 'nothing held back');
    is_deeply([sort keys %{ $d->{written} }], [qw(a.html a.md llms-full.txt llms.txt)], 'written files, relative to the output');
    is_deeply($d->{page_owner}, { '_output/a.html' => '_source/a.md' }, 'which page wrote what');
    $d->build();
    is(scalar @{ $d->{site}->{pages} }, 1, 'no duplicate pages on a second build');
    is($d->{site}->{pages}->[0]->{id}, 1, 'ids start again');
    is(scalar @{ $d->{static_files} }, 0, 'no duplicate static files');

    make_site({ '_source/a.md' => "---\ntitle: A\n---\nx", 'extra.txt' => "e\n", '_source/s.txt' => "s\n" });
    my $out = capture(sub { App::Dapper->new()->build() });
    is($out, join('', map { "$_\n" }
        'Processing _source/a.md', 'Wrote _output/a.html', 'Wrote _output/a.md',
        'Copied _source/s.txt', 'Copied extra.txt',
        'Wrote _output/llms.txt', 'Wrote _output/llms-full.txt', 'Project built.'),
        'progress messages in order');

    $out = capture(sub { quiet_build() });
    is($out, '', 'nothing printed when quiet');
};

subtest 'content is not a template unless asked' => sub {
    make_site({
        '_config.yml'       => "---\nname: Site\ntagline: 'By [% site.name %]'\n",
        '_source/plain.md'  => "---\ntitle: Plain\n---\nName: [% site.name %]\n",
        '_source/tmpl.md'   => "---\ntitle: Tmpl\ntemplate: true\n---\nName: [% site.name %] / [% page.title %]\n",
        '_source/off.md'    => "---\ntitle: Off\ntemplate: false\n---\n[% page.title %]\n",
        '_source/page.html' => "---\ntitle: H\ntemplate: true\n---\n[% 1 + 2 %]",
        '_layout/index.html' => '[% page.content %]|[% site.tagline %]',
    });
    quiet_build();
    is(slurp('_output/plain.html'), "<p>Name: [% site.name %]</p>\n|By [% site.name %]", 'content and config values are literal');
    is(slurp('_output/tmpl.html'), "<p>Name: Site / Tmpl</p>\n|By [% site.name %]", 'template: true runs the content');
    is(slurp('_output/off.html'), "<p>[% page.title %]</p>\n|By [% site.name %]", 'template: false');
    is(slurp('_output/page.html'), '3|By [% site.name %]', 'template: true in an HTML page');

    spew('_config.yml', "---\nname: Site\ntagline: 'By [% site.name %]'\ntemplates_in_content: true\n");
    quiet_build();
    is(slurp('_output/plain.html'), "<p>Name: Site</p>\n|By Site", 'templates_in_content runs content and config values');
    is(slurp('_output/off.html'), "<p>Off</p>\n|By Site", 'even with template: false');

    make_site({
        '_source/bad.md' => "---\ntemplate: true\n---\n[% IF x %]never closed\n",
    });
    eval { quiet_build() };
    like($@, qr{^error: could not process the content of _source/bad\.md: .*Missing END}, 'error in template content');

    make_site({
        '_config.yml'    => "---\nname: x\ntemplates_in_content: true\n",
        '_source/bad.md' => "---\n---\n[% IF x %]never closed\n",
    });
    eval { quiet_build() };
    like($@, qr{^error: could not process _source/bad\.md with layout index \(2nd pass\): }, 'second pass error');

    make_site({
        '_config.yml'    => "---\nname: x\ntemplates_in_content: true\n",
        '_source/a.md'   => "---\n---\nx\n",
        '_layout/index.html' => '[% FOREACH %]',
    });
    eval { quiet_build() };
    like($@, qr{^error: could not process _source/a\.md with layout index: }, 'first pass error');

    make_site({ '_source/a.md' => "---\n---\nx\n", '_layout/index.html' => '[% END %]' });
    eval { quiet_build() };
    like($@, qr{^error: could not process _source/a\.md with layout index: }, 'layout error without templates_in_content');
};

subtest 'layouts are chosen per page' => sub {
    make_site({
        '_source/a.md' => "---\n---\nA",
        '_source/b.md' => "---\nlayout: post\n---\nB",
        '_source/c.md' => "---\nlayout: ''\n---\nC",
        '_layout/index.html' => 'index:[% page.content %]',
        '_layout/post.tt'    => 'post:[% page.content %]',
    });
    my $d = quiet_build();
    is(slurp('_output/a.html'), "index:<p>A</p>\n", 'index by default');
    is(slurp('_output/b.html'), "post:<p>B</p>\n", 'named layout, any extension');
    is(slurp('_output/c.html'), "index:<p>C</p>\n", 'an empty layout is index');
    is($d->{site}->{pages}->[0]->{layout}, 'index', 'page.layout is filled in');
};

subtest 'page fields' => sub {
    make_site({
        '_source/index.md'     => "---\ntitle: Home\ndate: 2014-05-02T03:04:05\ntimezone: UTC\nextra: [1, 2]\n---\n\n  \nFirst para *x*.\n\nSecond.\n",
        '_source/blog/post.md' => "---\ntitle: My Post!\ncategories: [news, '', tech]\ntags: [a, b, [x], '']\ndate: 2014-01-02\ntimezone: UTC\n---\nHi\n",
        '_source/raw.txt'      => "---\nextension: ''\ndate: 2015-10-11T12:13:14\n---\nraw",
        '_source/feed.xml'     => "---\nextension: .xml\ntitle: ''\ndate: 2015-01-01\n---\n<x/>",
        '_source/noext'        => "---\ndate: 2015-01-01\n---\nnoext",
        '_source/html.html'    => "---\ndate: 2015-01-01\n---\n<p>one</p><p>two</p>",
        '_layout/index.html'   => '[% page.content %]',
    });
    my $d = quiet_build();
    my %by = map { $_->{source} => $_ } @{ $d->{site}->{pages} };

    is_deeply([map { $_->{source} } @{ $d->{site}->{pages} }],
        [qw(_source/blog/post.md _source/feed.xml _source/html.html _source/index.md _source/noext _source/raw.txt)],
        'pages in sorted source path order');
    is_deeply([map { $_->{id} } @{ $d->{site}->{pages} }], [1 .. 6], 'ids in that order');

    my $home = $by{'_source/index.md'};
    is($home->{title}, 'Home', 'front matter copied');
    is_deeply($home->{extra}, [1, 2], 'any front matter');
    is($home->{slug}, 'home', 'slug from the title');
    is($home->{url}, '/', 'root url');
    is($home->{filename}, '_output/index.html', 'filename');
    is($home->{dirname}, '_output/', 'dirname');
    is($home->{extension}, '.html', 'extension from the site');
    is($home->{source_file_extension}, '.md', 'source_file_extension');
    is($home->{excerpt}, '<p>First para <em>x</em>.</p>', 'excerpt is the first paragraph');
    is($home->{markdown}, "\n\n  \nFirst para *x*.\n\nSecond.\n", 'page.markdown is the raw body');
    is($home->{content}, "<p>First para <em>x</em>.</p>\n\n<p>Second.</p>\n", 'leading blank lines removed from content');
    is(join(' ', @$home{qw(year month day hour minute second)}), '2014 05 02 03 04 05', 'zero-padded date parts');
    is("$home->{date}", '2014-05-02T03:04:05', 'page.date');
    isa_ok($home->{date}, 'App::Dapper::Date');
    is($home->{timezone}->name, 'UTC', 'page.timezone is a time zone object');
    is(slurp('_output/index.html'), "<p>First para <em>x</em>.</p>\n\n<p>Second.</p>\n", 'rendered');

    my $post = $by{'_source/blog/post.md'};
    is($post->{slug}, 'my-post', 'punctuation removed from the slug');
    is($post->{url}, '/news/2014/01/my-post/', 'first non-empty category in the url');
    is($post->{filename}, '_output/news/2014/01/my-post/index.html', 'index file in the url directory');
    is($post->{dirname}, '_output/news/2014/01/my-post/', 'dirname');
    is_deeply([sort keys %{ $d->{site}->{categories} }], [qw(news tech)], 'empty categories ignored');
    is_deeply([sort keys %{ $d->{site}->{tags} }], [qw(a b)], 'empty and non-string tags ignored');
    is_deeply($post->{tags}, ['a', 'b', ['x'], ''], 'page.tags left as written');
    is($post->{excerpt}, '<p>Hi</p>', 'excerpt');

    my $raw = $by{'_source/raw.txt'};
    is($raw->{extension}, '', 'an empty extension');
    is($raw->{filename}, '_output/raw', 'written without one');
    is($raw->{url}, '/raw', 'url');
    is($raw->{source_file_extension}, '.txt', 'source extension');
    ok(!exists $raw->{excerpt}, 'no excerpt for a page that is not Markdown');
    ok(!exists $raw->{markdown}, 'no page.markdown either');
    is($raw->{content}, 'raw', 'content as written');
    is(join(' ', @$raw{qw(year month day hour minute second)}), '2015 10 11 12 13 14', 'parts of 10 and over are not padded');
    is(slurp('_output/raw'), 'raw', 'rendered');

    my $feed = $by{'_source/feed.xml'};
    is($feed->{slug}, 'feed', 'an empty title falls back to the file name');
    is($feed->{filename}, '_output/feed.xml', 'page extension');
    is($feed->{url}, '/feed.xml', 'url');

    my $noext = $by{'_source/noext'};
    is($noext->{source_file_extension}, '', 'no source extension is an empty string');
    is($noext->{filename}, '_output/noext.html', 'site extension added');
    is($noext->{slug}, 'noext', 'slug from the file name');

    my $html = $by{'_source/html.html'};
    ok(!exists $html->{excerpt}, 'HTML pages have no excerpt');
    is(slurp('_output/html.html'), '<p>one</p><p>two</p>', 'HTML content is not Markdown');
};

subtest 'excerpts' => sub {
    make_site({
        '_source/none.md'  => "---\n---\n# Only a heading\n",
        '_source/multi.md' => "---\n---\nLine one\nline two\n\nNext\n",
        '_source/list.md'  => "---\n---\n- item\n\nAfter the list\n",
        '_layout/index.html' => '[[% page.excerpt %]]',
    });
    my $d = quiet_build();
    my %by = map { $_->{source} => $_ } @{ $d->{site}->{pages} };
    ok(!defined $by{'_source/none.md'}->{excerpt}, 'no paragraph, no excerpt');
    is(slurp('_output/none.html'), '[]', 'renders as nothing');
    is($by{'_source/multi.md'}->{excerpt}, "<p>Line one\nline two</p>", 'a paragraph over several lines');
    is($by{'_source/list.md'}->{excerpt}, '<p>After the list</p>', 'the first <p>, wherever it is');
};

subtest 'problems and collect mode' => sub {
    make_site({
        '_source/good.md'     => "---\ntitle: Good\n---\nok\n",
        '_source/badfm.md'    => "---\ntitle: [x\n---\n",
        '_source/open.md'     => "---\ntitle: x\n",
        '_source/nolayout.md' => "---\nlayout: nope\n---\nx",
        '_source/baddate.md'  => "---\ndate: someday\n---\nx",
        '_source/badtz.md'    => "---\ntimezone: Mars/X\n---\nx",
        '_source/badtmpl.md'  => "---\ntemplate: true\n---\n[% IF %]",
        '_source/comp.md'     => "---\n---\n::: nosuch\nx\n:::\n\n::: nosuch\ny\n:::\n",
    });
    my $d = build_with(collect => 1);
    my @problems = @{ $d->{problems} };
    is_deeply([map { "$_->{severity} $_->{file}" } @problems], [
        'error _source/baddate.md',
        'error _source/badfm.md',
        'error _source/badtz.md',
        'warning _source/comp.md',
        'error _source/open.md',
        'error _source/badtmpl.md',
        'error _source/nolayout.md',
    ], 'every problem found, in build order, with a component reported once');
    my %msg = map { $_->{file} => $_->{message} } @problems;
    is($msg{'_source/baddate.md'}, 'could not understand the date "someday" in "_source/baddate.md". Use the ISO 8601 format, e.g. 2014-05-02T10:30:00',
        'date message, without the error: prefix or newline');
    like($msg{'_source/badfm.md'}, qr/^could not parse front matter in "_source\/badfm\.md": /, 'YAML message');
    is($msg{'_source/badtz.md'}, 'unknown time zone "Mars/X" in "_source/badtz.md"', 'time zone message');
    like($msg{'_source/comp.md'}, qr/^_source\/comp\.md uses the component "::: nosuch", which doesn't exist; the built-in ones are .*note.*, and others can be added in _layout\/components$/,
        'component message');
    is($msg{'_source/open.md'}, '"_source/open.md" has front matter that is never closed with a line containing ---', 'unclosed message');
    like($msg{'_source/badtmpl.md'}, qr/^could not process the content of _source\/badtmpl\.md: /, 'template message');
    is($msg{'_source/nolayout.md'}, '_source/nolayout.md uses the layout "nope", but there is no such file in _layout', 'layout message');
    ok(-f '_output/good.html', 'the good page is still written');
    ok(!-e '.dapper/manifest.json', 'no manifest in collect mode');

    # Outside collect mode, warnings are printed and errors die
    make_site({ '_source/comp.md' => "---\n---\n::: nosuch\nx\n:::\n" });
    my @warnings;
    {
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        quiet_build();
    }
    is(scalar @warnings, 1, 'one warning');
    like($warnings[0], qr/^warning: _source\/comp\.md uses the component "::: nosuch"/, 'printed with warning:');
    ok(-f '_output/comp.html', 'the page is still built');
};

subtest 'problem and attempt' => sub {
    make_site({});
    my $d = App::Dapper->new();

    eval { $d->problem('error', 'f', "error: something broke\n\n") };
    is($@, "error: something broke\n", 'error dies, prefix not doubled, trailing space removed');
    eval { $d->problem('error', 'f', 'plain') };
    is($@, "error: plain\n", 'prefix added');
    my @w;
    {
        local $SIG{__WARN__} = sub { push @w, @_ };
        $d->problem('warning', 'f', "warning: careful  \n");
        $d->problem('notice', 'f', 'other severities warn');
    }
    is_deeply(\@w, ["warning: careful\n", "warning: other severities warn\n"], 'warnings');

    $d->{collect} = 1;
    $d->{problems} = [];
    $d->problem('error', 'a.md', "error: bad\n");
    $d->problem('warning', 'b.md', "warning: meh\n");
    is_deeply($d->{problems}, [
        { severity => 'error', file => 'a.md', message => 'bad' },
        { severity => 'warning', file => 'b.md', message => 'meh' },
    ], 'recorded when collecting');

    $d->{problems} = [];
    my $r = $d->attempt('x.md', sub { die "error: oops\n" });
    is_deeply($d->{problems}, [{ severity => 'error', file => 'x.md', message => 'oops' }], 'attempt records a death');
    ok(!$r, 'and returns false');
    $r = $d->attempt('x.md', sub { 'fine' });
    is($r, 1, 'attempt returns true when the code lives');

    $d->{collect} = 0;
    is($d->attempt('x', sub { 'value' }), 'value', 'outside collect mode attempt returns the value');
    is_deeply([$d->attempt('x', sub { (1, 2, 3) })], [1, 2, 3], 'in list context too');
    eval { $d->attempt('x', sub { die "boom\n" }) };
    is($@, "boom\n", 'and lets errors through');
};

subtest '_log' => sub {
    my $d = App::Dapper->new();
    is(capture(sub { $d->_log('Hello Zoë') }), "Hello Zoë\n", 'prints a line');
    $d->{quiet} = 1;
    is(capture(sub { $d->_log('Hello') }), '', 'not when quiet');
};

subtest 'init' => sub {
    make_site({}, bare => 1);
    my $d = App::Dapper->new();
    my $out = capture(sub { $d->init() });
    like($out, qr/^Creating _config\.yml$/m, 'files listed');
    like($out, qr/^Creating AGENTS\.md$/m, 'AGENTS.md listed');
    like($out, qr/^Creating CLAUDE\.md$/m, 'CLAUDE.md listed');
    like($out, qr/Project initialized\.\n\z/, 'ends with a message');
    ok(-f $_, "$_ created") for qw(_config.yml _source/index.md _layout/index.html AGENTS.md CLAUDE.md);
    is($App::Dapper::Utils::QUIET, 0, 'QUIET restored after init');

    make_site({}, bare => 1);
    $d = App::Dapper->new('src', 'out', 'lay', 'site.yml');
    $d->{quiet} = 1;
    is(capture(sub { $d->init() }), '', 'nothing printed when quiet');
    ok(-f 'site.yml' && -f 'src/index.md' && -f 'lay/index.html', 'custom names used');
    unlike(slurp('site.yml'), qr/^source/m, 'the directories are not written into the project file');
    like(slurp('.gitignore'), qr{^out/}m, 'the output directory is in .gitignore');
    quiet_build('src', 'out', 'lay', 'site.yml');
    like(slurp('out/index.html'), qr{<title>Welcome</title>}, 'the new project builds with the same names');
};

done_testing();
