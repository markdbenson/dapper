use 5.010;
use strict;
use warnings;
use Test::More;
use JSON ();

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Check;

# dapper check: the shape of the report, the JSON, how problems are
# classified and cleaned, the text for people, and what check leaves alone.

my $clean_config = "---\nname: x\nurl: https://example.com\n";
my $layout = qq{<html lang="en"><head><title>[% page.title %]</title></head><body>[% page.content %]</body></html>};

sub check { App::Dapper->new(@_)->check() }

subtest 'the report of a clean site, exactly' => sub {
    make_site({
        '_config.yml'        => $clean_config,
        '_layout/index.html' => $layout,
        '_source/index.md'   => "---\ntitle: Home\n---\nWelcome.\n",
    });
    my $report = check();
    is_deeply($report, { ok => JSON::true, pages => 1, errors => [], warnings => [], held => [] }, 'every key');
    ok(JSON::is_bool($report->{ok}), 'ok is a JSON boolean');
    is(JSON->new->canonical->encode($report), '{"errors":[],"held":[],"ok":true,"pages":1,"warnings":[]}', 'as JSON');
    is(App::Dapper::Check::text($report), "Checked 1 page: 0 errors, 0 warnings.\n", 'as text');
    ok(!-e '_output', 'nothing written to the output directory');
};

subtest 'a report with errors and warnings, as JSON' => sub {
    make_site({
        '_layout/index.html' => $layout,
        '_source/a.md'       => "---\ntitle: A\n---\nSee [b](/b.html).\n",
    });
    my $report = check();
    ok(!$report->{ok}, 'not ok');
    ok(JSON::is_bool($report->{ok}), 'ok is a JSON boolean');
    is(JSON->new->canonical->encode($report), '{"errors":[{"file":"_source/a.md","message":"links to /b.html, which is not in the site","type":"link"}],'
        . '"held":[],"ok":false,"pages":1,'
        . '"warnings":[{"file":"_config.yml","message":"url is not set, so there is no sitemap, and links in llms.txt and page.seo are not absolute","type":"setting"}]}',
        'exact JSON');
    is(App::Dapper::Check::text($report),
        "error: _source/a.md: links to /b.html, which is not in the site\n"
        . "warning: _config.yml: url is not set, so there is no sitemap, and links in llms.txt and page.seo are not absolute\n"
        . "Checked 1 page: 1 error, 1 warning.\n", 'exact text');
    is_deeply([ sort keys %{ $report->{errors}->[0] } ], [qw/ file message type /], 'each problem has file, type and message only');
};

subtest 'an existing output directory is not touched' => sub {
    make_site({ '_config.yml' => $clean_config, '_layout/index.html' => $layout, '_source/index.md' => "---\ntitle: Home\n---\nHi.\n" });
    spew('_output/old.html', 'left over');
    check();
    is(slurp('_output/old.html'), 'left over', 'old files stay');
    ok(!-e '_output/index.html', 'nothing new');
};

subtest 'the Dapper object is put back as it was' => sub {
    make_site({ '_config.yml' => $clean_config, '_layout/index.html' => $layout, '_source/index.md' => "---\ntitle: Home\n---\nHi.\n" });
    my $d = App::Dapper->new();
    $d->{quiet} = 0;
    my ($collect, $output, $explicit) = ($d->{collect}, $d->{output}, $d->{explicit}->{output});
    $d->check();
    is($d->{quiet}, 0, 'quiet');
    is($d->{collect}, $collect, 'collect');
    is($d->{output}, $output, 'output');
    is($d->{explicit}->{output}, $explicit, 'explicit output');
    is($d->{site}->{output}, '_output', 'site.output is the real directory');

    $d = App::Dapper->new(undef, '_elsewhere');
    $d->check();
    is($d->{output}, '_elsewhere', 'an output given on the command line is kept');
    ok($d->{explicit}->{output}, 'and still explicit');
    ok(!-e '_elsewhere', 'and not written');
    quiet_build();
    ok(-f '_output/index.html', 'a build afterwards writes to the real directory');
};

subtest 'a project that cannot be read is one error' => sub {
    make_site({ '_config.yml' => "- a\n- b\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    my $report = check();
    is_deeply($report, {
        ok => JSON::false, pages => 0, held => [], warnings => [],
        errors => [ { file => '_config.yml', type => 'other', message => '"_config.yml" must contain key: value pairs' } ],
    }, 'reported against _config.yml, and nothing else is checked');
    is(App::Dapper::Check::text($report), "error: _config.yml: \"_config.yml\" must contain key: value pairs\nChecked 0 pages: 1 error, 0 warnings.\n", 'text');

    make_site({ '_config.yml' => "name: [unclosed\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    $report = check();
    is(scalar @{ $report->{errors} }, 1, 'a YAML error');
    like($report->{errors}->[0]->{message}, qr/\Acould not parse "_config\.yml": /, 'with the parser message');
    unlike($report->{errors}->[0]->{message}, qr/\s\z/, 'trailing white space removed');

    make_site({ '_config.yml' => "---\nname: x\nsource: _nowhere\n" });
    $report = check();
    is_deeply($report->{errors}, [ { file => '_config.yml', type => 'other', message => 'source directory "_nowhere" does not exist' } ], 'no source directory');

    make_site({ '_config.yml' => "---\nname: x\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    unlink '_config.yml';
    $report = check();
    is_deeply($report->{errors}, [ { file => '_config.yml', type => 'other',
        message => 'could not find the project file "_config.yml". Run "dapper init" to create a new project.' } ], 'no project file');
};

subtest 'held drafts and scheduled pages' => sub {
    make_site({
        '_config.yml'        => $clean_config,
        '_layout/index.html' => $layout,
        '_source/a.md'       => "---\ntitle: A\n---\nA.\n",
        '_source/d1.md'      => "---\ntitle: D1\ndraft: true\n---\nx\n",
        '_source/d2.md'      => "---\ntitle: D2\ndraft: yes\n---\nx\n",
        '_source/later.md'   => "---\ntitle: L\ndate: 2999-01-01T00:00:00Z\n---\nx\n",
    });
    my $report = check();
    is_deeply($report->{held}, [
        { file => '_source/d1.md', reason => 'draft' },
        { file => '_source/d2.md', reason => 'draft' },
        { file => '_source/later.md', reason => 'scheduled' },
    ], 'file and reason, in source order, and no date');
    is($report->{pages}, 1, 'held pages are not counted');
    ok($report->{ok}, 'held pages are not errors');
    is(App::Dapper::Check::text($report),
        "Not published: 2 drafts, 1 scheduled (use --drafts to include them).\nChecked 1 page: 0 errors, 0 warnings.\n", 'text');
    is_deeply(check(undef, undef, undef, undef)->{held}, $report->{held}, 'the same on a second run');

    my $d = App::Dapper->new();
    $d->{drafts} = 1;
    is_deeply($d->check()->{held}, [], 'none held with drafts');
    is($d->check()->{pages}, 4, 'and all are counted');
};

subtest 'text: wording and plurals' => sub {
    my $t = \&App::Dapper::Check::text;
    my $p = sub { { file => 'f', type => 'x', message => "m$_[0]" } };
    is($t->({ pages => 0, errors => [], warnings => [] }), "Checked 0 pages: 0 errors, 0 warnings.\n", 'all zero');
    is($t->({ pages => 1, errors => [ $p->(1) ], warnings => [ $p->(2) ] }),
        "error: f: m1\nwarning: f: m2\nChecked 1 page: 1 error, 1 warning.\n", 'all one');
    is($t->({ pages => 2, errors => [ $p->(1), $p->(2) ], warnings => [ $p->(3), $p->(4), $p->(5) ] }),
        "error: f: m1\nerror: f: m2\nwarning: f: m3\nwarning: f: m4\nwarning: f: m5\nChecked 2 pages: 2 errors, 3 warnings.\n", 'plurals, errors first');
    is($t->({ pages => 1, errors => [], warnings => [], held => [] }), "Checked 1 page: 0 errors, 0 warnings.\n", 'nothing held: no line');
    is($t->({ pages => 1, errors => [], warnings => [], held => [ { reason => 'draft' } ] }),
        "Not published: 1 draft, 0 scheduled (use --drafts to include them).\nChecked 1 page: 0 errors, 0 warnings.\n", 'one draft');
    is($t->({ pages => 1, errors => [], warnings => [], held => [ { reason => 'scheduled' }, { reason => 'scheduled' } ] }),
        "Not published: 0 drafts, 2 scheduled (use --drafts to include them).\nChecked 1 page: 0 errors, 0 warnings.\n", 'scheduled only');
    is($t->({ pages => 3, errors => [ $p->(1) ], warnings => [], held => [ { reason => 'draft' } ] }),
        "error: f: m1\nNot published: 1 draft, 0 scheduled (use --drafts to include them).\nChecked 3 pages: 1 error, 0 warnings.\n",
        'the held line comes after the problems');
};

subtest 'classify: every type' => sub {
    my $c = sub { App::Dapper::Check::classify({ message => $_[0] }) };
    is($c->('"title" is required (see _source/_schema.yml)'), 'schema', 'schema rule');
    is($c->('the schema "_source/_schema.yml" has problems:'), 'schema', 'schema file');
    is($c->('"a.md" has front matter that is never closed with a line containing ---'), 'front_matter', 'front matter');
    is($c->('could not understand the date "x" in "a.md"'), 'front_matter', 'a date');
    is($c->('unknown time zone "Mars/Base" in "a.md"'), 'front_matter', 'a time zone');
    is($c->('uses the layout "nope", but there is no such file in _layout'), 'layout', 'missing layout');
    is($c->('layout "a" is part of a loop of layouts'), 'layout', 'loop of layouts');
    is($c->('layout "a" names the layout "b", which does not exist'), 'layout', 'missing parent layout');
    is($c->('could not process a.md with layout index: parse error'), 'template', 'template');
    is($c->('a.md and b.md both write _output/x.html'), 'duplicate', 'two pages, one file');
    is($c->('a page in the source directory already writes _output/feed.xml, so Dapper did not generate one'), 'duplicate', 'a page and a generated file');
    is($c->("the sitemap needs the site's address; set url in _config.yml"), 'setting', 'needs the site');
    is($c->('tag_pages in _config.yml needs a layout, e.g. layout: tag'), 'setting', 'needs a layout');
    is($c->('search: true needs Pagefind; install it'), 'setting', 'needs Pagefind');
    is($c->('category_pages in _config.yml must be settings such as layout: category'), 'setting', 'must be settings');
    is($c->('uses the component "::: nope", which doesn\'t exist'), 'component', 'unknown component');
    is($c->('the component template "x" is broken'), 'component', 'component template');
    is($c->('the redirect from old must start with /'), 'other', 'anything else');
    is($c->(''), 'other', 'empty');
};

subtest 'classify: the first matching kind wins' => sub {
    my $c = sub { App::Dapper::Check::classify({ message => $_[0] }) };
    is($c->('uses the layout "schema"'), 'schema', 'schema is checked first');
    is($c->('could not process the front matter'), 'front_matter', 'front matter before template');
    is($c->('could not process: both write'), 'template', 'template before duplicate');
};

subtest 'run: problems keep a type they already have' => sub {
    make_site({ '_layout/index.html' => $layout, '_source/a.md' => "---\ntitle: A\n---\n[x](/schema-page.html)\n" });
    my $report = check();
    is($report->{errors}->[0]->{type}, 'link', 'a link to a page named schema is still a link');
};

subtest 'messages do not repeat the file' => sub {
    make_site({
        '_layout/index.html' => $layout,
        '_source/a.md'       => "---\ntitle: A\n---\nx\n\n::: nosuch\nx\n:::\n",
        '_source/b.md'       => "---\ntitle: [unclosed\n---\nx\n",
        '_source/c.md'       => "---\ntitle: C\nlayout: missing\n---\nx\n",
        '_source/d.md'       => "---\ntitle: D\ndate: someday\n---\nx\n",
    });
    my $report = check();
    my %by_file = map { ($_->{file} => $_) } @{ $report->{errors} }, @{ $report->{warnings} };
    like($by_file{'_source/a.md'}->{message}, qr/\Auses the component "::: nosuch", which doesn't exist; the built-in ones are /, '"a.md uses" becomes "uses"');
    is($by_file{'_source/a.md'}->{type}, 'component', 'component');
    is($by_file{'_source/c.md'}->{message}, 'uses the layout "missing", but there is no such file in _layout', 'layout');
    like($by_file{'_source/d.md'}->{message}, qr/\Acould not understand the date "someday" in "_source\/d\.md"\. Use the ISO 8601 format/, 'a quoted file name inside is kept');
    is($by_file{'_source/d.md'}->{type}, 'front_matter', 'date problems are front matter');
    is($by_file{'_source/b.md'}->{type}, 'front_matter', 'YAML that cannot be read');
    unlike($by_file{'_source/b.md'}->{message}, qr/\s\z/, 'no trailing white space');
};

subtest 'two pages writing one file' => sub {
    make_site({
        '_layout/index.html' => $layout,
        '_source/a.md' => "---\ntitle: A\nurlpattern: /same.html\n---\nx\n",
        '_source/b.md' => "---\ntitle: B\nurlpattern: /same.html\n---\nx\n",
    });
    my $report = check();
    my @dupes = grep { $_->{type} eq 'duplicate' } @{ $report->{errors} };
    is(scalar @dupes, 1, 'one error');
    is($dupes[0]->{file}, '_source/b.md', 'against the second page');
    like($dupes[0]->{message}, qr{\Aand _source/a\.md both write _output/same\.html\z}, 'naming the other page');
    is($report->{pages}, 2, 'both counted');
};

subtest 'warnings: pages without a title' => sub {
    make_site({
        '_config.yml'        => $clean_config,
        '_layout/index.html' => $layout,
        '_layout/raw.html'   => '[% page.content %]',
        '_source/a.md'       => "---\ndescription: x\n---\nA.\n",
        '_source/b.md'       => "---\ntitle: ''\n---\nB.\n",
        '_source/c.md'       => "---\ntitle: 0\n---\nC.\n",
        '_source/feed.xml'   => "---\nlayout: raw\nextension: .xml\n---\n<x/>\n",
    });
    my $report = check();
    is_deeply([ map { "$_->{type} $_->{file}: $_->{message}" } grep { $_->{message} eq 'has no title' } @{ $report->{warnings} } ], [
        'front_matter _source/a.md: has no title',
        'front_matter _source/b.md: has no title',
    ], 'missing and empty titles; 0 is a title; non-HTML pages need none');
};

subtest 'warnings: url' => sub {
    make_site({ '_config.yml' => "---\nname: x\nurl: ''\n", '_layout/index.html' => $layout, '_source/a.md' => "---\ntitle: A\n---\nA.\n" });
    my @url = grep { $_->{message} =~ /^url is not set/ } @{ check()->{warnings} };
    is_deeply(\@url, [ { file => '_config.yml', type => 'setting',
        message => 'url is not set, so there is no sitemap, and links in llms.txt and page.seo are not absolute' } ], 'an empty url is not set');
};

subtest 'the order of a report' => sub {
    make_site({
        '_layout/index.html' => $layout,
        '_source/a.md'       => "---\ntitle: A\nlayout: nope\n---\nx\n",
        '_source/b.md'       => "---\n---\n[gone](/gone/) <img src=\"/b.png\">\n",
        '_source/b.png'      => "PNG",
    });
    my $report = check();
    is_deeply([ map { "$_->{type} $_->{file}" } @{ $report->{errors} } ], [ 'layout _source/a.md', 'link _source/b.md' ], 'errors: build, then links');
    is_deeply([ map { "$_->{type} $_->{file}" } @{ $report->{warnings} } ], [
        'setting _config.yml', 'front_matter _source/b.md', 'accessibility _source/b.md',
    ], 'warnings: settings and titles, then quality');
};

done_testing();
