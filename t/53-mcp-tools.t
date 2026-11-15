use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;
binmode(Test::More->builder->$_, q(:encoding(UTF-8))) for qw(output failure_output todo_output);

# Every MCP tool, called through tools/call: what each returns, what each
# writes, and every way each can refuse.

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::MCP;
use File::Temp qw(tempdir);
use JSON ();

sub call {
    my ($d, $name, $args) = @_;
    my $response = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 1, method => 'tools/call',
        params => { name => $name, arguments => $args || {} } });
    return $response->{result};
}

# The structured content of a call that must succeed
sub ok_call {
    my ($d, $name, $args, $label) = @_;
    my $result = call($d, $name, $args);
    ok(!$result->{isError}, "$label: not an error") or diag explain $result->{structuredContent};
    return $result->{structuredContent};
}

# The error message of a call that must fail
sub error_call {
    my ($d, $name, $args) = @_;
    my $result = call($d, $name, $args);
    return $result->{isError} ? $result->{structuredContent}->{error} : "(not an error)";
}

my %SITE = (
    '_config.yml'              => "---\nname: Tools\nurl: https://example.com\ndescription: A site for tools.\ncategory_pages:\n  layout: index\nfeed:\n  category: blog\n",
    '_source/index.md'         => "---\ntitle: Home\nlayout: index\n---\nHome.\n",
    '_source/blog/_schema.yml' => "required: [title, date]\nfields:\n  categories:\n    type: list\n    values: [blog, news]\n  title:\n    type: string\n    max_length: 40\n",
    '_source/blog/first.md'    => "---\ntitle: First\ndate: 2020-01-01\ncategories: blog\ntags: [a]\n---\n\nHello.\n",
    '_source/blog/second.md'   => "---\ntitle: Second\ndate: 2020-02-01\ncategories: [blog]\ntags: [a, b]\n---\n\nAgain.\n",
    '_source/notes.txt'        => "plain text\n",
    '_layout/post.html'        => "---\nlayout: index\ndescription: A post\n---\n<article>[% page.content %]</article>",
);

subtest 'site_info' => sub {
    make_site({ %SITE });
    my $d = App::Dapper->new();
    my $info = ok_call($d, 'site_info', {}, 'site_info');
    is($info->{name}, 'Tools', 'name');
    is($info->{url}, 'https://example.com', 'url');
    is($info->{description}, 'A site for tools.', 'description');
    is_deeply($info->{directories}, { source => '_source', output => '_output', layout => '_layout', data => '_data' }, 'directories');
    is($info->{pages}, 4, 'pages, including the generated category page');
    is_deeply($info->{categories}, { blog => 2 }, 'categories with their counts');
    is_deeply($info->{tags}, { a => 2, b => 1 }, 'tags with their counts');
    is_deeply($info->{layouts}, [qw(index post)], 'layouts, sorted');
    is(scalar @{$info->{schemas}}, 1, 'one schema');
    my $schema = $info->{schemas}->[0];
    is($schema->{applies_to}, '_source/blog', 'where it applies');
    is($schema->{file}, '_source/blog/_schema.yml', 'its file');
    is_deeply($schema->{required}, [qw(title date)], 'required');
    is_deeply($schema->{fields}->{categories}, { type => 'list', values => [qw(blog news)] }, 'fields');
    ok(JSON::is_bool($schema->{additional}) && $schema->{additional}, 'additional is a true boolean');

    my $settings = $info->{settings};
    is($settings->{name}, 'Tools', 'settings include the name');
    is($settings->{urlpattern}, '/:category/:year/:month/:slug/', 'and the defaults');
    is_deeply($settings->{feed}, { category => 'blog' }, 'and hashes');
    is(ref $settings->{ignore}, 'ARRAY', 'and lists');
    ok(!exists $settings->{$_}, "but not $_") for qw(pages categories tags data time category_pages tag_pages);
};

subtest 'site_info with other directories and strict schemas' => sub {
    make_site({
        '_config.yml'           => "---\nname: Other\nsource: pages\nlayout: templates\noutput: public\ndata_dir: info\n",
        'pages/index.md'        => "---\ntitle: Home\n---\nx\n",
        'pages/_schema.yml'     => "required: [title]\nadditional: false\nfields:\n  title:\n    type: string\n",
        'pages/docs/_schema.yml' => "required: [title, order]\nfields:\n  order:\n    type: integer\n    min: 1\n",
        'templates/index.html'  => "[% page.content %]",
    }, bare => 1);
    my $d = App::Dapper->new();
    my $info = ok_call($d, 'site_info', {}, 'site_info');
    is_deeply($info->{directories}, { source => 'pages', output => 'public', layout => 'templates', data => 'info' }, 'directories from the project file');
    is_deeply([ map { $_->{applies_to} } @{$info->{schemas}} ], [qw(pages pages/docs)], 'schemas sorted by where they apply');
    ok(JSON::is_bool($info->{schemas}->[0]->{additional}) && !$info->{schemas}->[0]->{additional}, 'additional: false');
    is_deeply($info->{schemas}->[1]->{fields}->{order}, { type => 'integer', min => 1 }, 'nested schema fields');
    is_deeply($info->{categories}, {}, 'no categories');
    is_deeply($info->{tags}, {}, 'no tags');
    is($info->{url}, undef, 'no url');
};

subtest 'site_info with a broken schema' => sub {
    make_site({ %SITE, '_source/bad/_schema.yml' => "required: x\nbogus: 1\n" });
    my $d = App::Dapper->new();
    my $error = error_call($d, 'site_info');
    like($error, qr/\Athe schema "_source\/bad\/_schema\.yml" has problems:\n  unknown setting "bogus" \(use required, fields or additional\)/, 'the whole tool fails, naming the schema');
    unlike($error, qr/^error: /, 'without the error: prefix');
};

subtest 'list_pages' => sub {
    make_site({ %SITE });
    my $d = App::Dapper->new();
    my $pages = ok_call($d, 'list_pages', {}, 'all')->{pages};
    is_deeply([ map { $_->{source} } @$pages ], ['blog/first.md', 'blog/second.md', 'index.md', 'category_pages (blog)'], 'every page, sources relative to the source directory');
    my %by = map { $_->{source} => $_ } @$pages;
    is_deeply($by{'blog/first.md'}, { source => 'blog/first.md', url => '/blog/2020/01/first/', title => 'First',
        date => '2020-01-01T00:00:00', categories => ['blog'], tags => ['a'] }, 'a post: source, url, title, date, categories and tags');
    is($by{'index.md'}->{layout}, 'index', 'the layout when set');
    ok(!exists $by{'index.md'}->{categories}, 'no categories when there are none');
    ok(!exists $by{'blog/first.md'}->{layout}, 'no layout when not set');
    ok(!exists $by{'blog/first.md'}->{generated}, 'pages from files are not generated');
    ok(JSON::is_bool($by{'category_pages (blog)'}->{generated}) && $by{'category_pages (blog)'}->{generated}, 'generated pages say so');
    is($by{'category_pages (blog)'}->{url}, '/blog/', 'with their url');
    ok(!grep({ $_->{source} eq 'notes.txt' } @$pages), 'files without front matter are not pages');

    $pages = ok_call($d, 'list_pages', { category => 'blog' }, 'category')->{pages};
    is_deeply([ map { $_->{source} } @$pages ], ['blog/second.md', 'blog/first.md'], 'a category, newest first');
    $pages = ok_call($d, 'list_pages', { tag => 'a' }, 'tag')->{pages};
    is_deeply([ map { $_->{source} } @$pages ], ['blog/second.md', 'blog/first.md'], 'a tag, newest first');
    $pages = ok_call($d, 'list_pages', { tag => 'b' }, 'tag b')->{pages};
    is_deeply([ map { $_->{title} } @$pages ], ['Second'], 'only pages with the tag');
    $pages = ok_call($d, 'list_pages', { category => 'blog', tag => 'nope' }, 'both')->{pages};
    is(scalar @$pages, 2, 'the category wins over the tag');
    is_deeply(ok_call($d, 'list_pages', { category => 'nope' }, 'unknown category')->{pages}, [], 'an unknown category: no pages');
    is_deeply(ok_call($d, 'list_pages', { tag => 'nope' }, 'unknown tag')->{pages}, [], 'an unknown tag: no pages');

    spew('_source/untitled.md', "---\nlayout: index\n---\nx\n");
    $pages = ok_call($d, 'list_pages', {}, 'untitled')->{pages};
    my ($untitled) = grep { $_->{source} eq 'untitled.md' } @$pages;
    ok(!exists $untitled->{title}, 'a page without a title has no title');
    is($untitled->{url}, '/untitled.html', 'but has its url');
    unlink '_source/untitled.md';

    spew('_source/later.md', "---\ntitle: Later\ndraft: true\n---\nx\n");
    $pages = ok_call($d, 'list_pages', {}, 'with a draft')->{pages};
    ok(!grep({ $_->{source} eq 'later.md' } @$pages), 'drafts are not listed');
};

subtest 'read_page' => sub {
    make_site({ %SITE,
        '_source/crlf.md'  => "---\r\ntitle: Windows\r\n---\r\n\r\n\r\nBody\r\n",
        '_source/blank.md' => "---\ntitle: Blank lines\n---\n\n\n\nBody\n\nMore\n",
    });
    my $d = App::Dapper->new();
    is_deeply(ok_call($d, 'read_page', { source => 'blog/first.md' }, 'a post'),
        { source => 'blog/first.md', file => '_source/blog/first.md', body => "Hello.\n",
          front_matter => { title => 'First', date => '2020-01-01', categories => 'blog', tags => ['a'] } }, 'source, file, front matter and body');
    is(ok_call($d, 'read_page', { source => 'blank.md' }, 'blank')->{body}, "Body\n\nMore\n", 'leading blank lines are dropped, the rest kept');
    is(ok_call($d, 'read_page', { source => 'crlf.md' }, 'crlf')->{body}, "Body\r\n", 'Windows line endings too');
    my $plain = ok_call($d, 'read_page', { source => 'notes.txt' }, 'plain');
    is($plain->{front_matter}, undef, 'a file without front matter: front_matter is null');
    is($plain->{body}, "plain text\n", 'and the body is the whole file');
    my $prefixed = ok_call($d, 'read_page', { source => '_source/index.md' }, 'prefixed');
    is($prefixed->{file}, '_source/index.md', 'a path starting with the source directory is accepted');
    is($prefixed->{source}, '_source/index.md', 'and returned as given');
    is(ok_call($d, 'read_page', { source => './index.md' }, 'dot')->{file}, '_source/index.md', './ is tidied away');
    is(ok_call($d, 'read_page', { source => 'blog//first.md' }, 'double slash')->{file}, '_source/blog/first.md', 'and doubled slashes');

    is(error_call($d, 'read_page', { source => 'missing.md' }), 'there is no file "_source/missing.md"', 'a missing file');
    is(error_call($d, 'read_page', { source => 'blog' }), 'there is no file "_source/blog"', 'a directory');
    is(error_call($d, 'read_page', {}), 'give the source file, e.g. blog/my-post.md', 'no source');
    is(error_call($d, 'read_page', { source => '' }), 'give the source file, e.g. blog/my-post.md', 'an empty source');
    is(error_call($d, 'read_page', { source => '../_config.yml' }), '"../_config.yml" must not contain ..', 'outside the source directory');
    is(error_call($d, 'read_page', { source => '/etc/passwd' }), '"/etc/passwd" must be relative to the source directory', 'an absolute path');
    is(error_call($d, 'read_page', { source => '.hidden' }), '".hidden" must not be a hidden file', 'a hidden file');

    unlink '_config.yml';
    like(error_call($d, 'read_page', { source => 'index.md' }), qr/^could not find the project file/, 'without a project file');
};

subtest 'source paths' => sub {
    make_site({ %SITE });
    my $d = App::Dapper->new();
    $d->read_project();
    my %good = (
        'a.md'             => '_source/a.md',
        'blog/a.md'        => '_source/blog/a.md',
        '_source/a.md'     => '_source/a.md',
        './blog/./a.md'    => '_source/blog/a.md',
        'blog/'            => '_source/blog',
        '_source'          => '_source/_source',
        'café/naïve.md'    => '_source/café/naïve.md',
        'a..b.md'          => '_source/a..b.md',
    );
    for my $path (sort keys %good) {
        is(App::Dapper::MCP::source_path($d, $path), $good{$path}, "$path is $good{$path}");
    }
    my %bad = (
        '..'                 => '".." must not contain ..',
        '../x.md'            => '"../x.md" must not contain ..',
        'blog/../../x.md'    => '"blog/../../x.md" must not contain ..',
        'blog/../x.md'       => '"blog/../x.md" must not contain ..',
        '_source/../x.md'    => '"_source/../x.md" must not contain ..',
        '/etc/passwd'        => '"/etc/passwd" must be relative to the source directory',
        '/tmp/../x'          => '"/tmp/../x" must be relative to the source directory',
        '.env'               => '".env" must not be a hidden file',
        'blog/.secret/x.md'  => '"blog/.secret/x.md" must not be a hidden file',
        '.'                  => '"." must not be a hidden file',
        ''                   => 'give the source file, e.g. blog/my-post.md',
    );
    for my $path (sort keys %bad) {
        eval { App::Dapper::MCP::source_path($d, $path) };
        is($@, "error: $bad{$path}\n", "refuses \"$path\"");
    }
    eval { App::Dapper::MCP::source_path($d, undef) };
    is($@, "error: give the source file, e.g. blog/my-post.md\n", 'refuses no path');
};

subtest 'write_page' => sub {
    make_site({ %SITE });
    my $d = App::Dapper->new();

    my $result = ok_call($d, 'write_page', { source => 'about.md', front_matter => { title => 'About', description => 'Us' }, body => 'All about us.' }, 'a page');
    is_deeply($result, { written => JSON::true, file => '_source/about.md', note => 'Run check to find problems, or build to publish.' }, 'the result');
    is(slurp('_source/about.md'), "---\ndescription: Us\ntitle: About\n---\n\nAll about us.\n", 'front matter (keys sorted), a blank line, the body and a final newline');

    ok_call($d, 'write_page', { source => 'blog/2020/deep/post.md', front_matter => { title => 'Deep', date => '2020-03-01', tags => ['x', 'y'], draft => JSON::true }, body => "Line\n" }, 'nested');
    is(slurp('_source/blog/2020/deep/post.md'), "---\ndate: 2020-03-01\ndraft: true\ntags:\n- x\n- y\ntitle: Deep\n---\n\nLine\n", 'directories are made; lists and booleans written as YAML');

    ok_call($d, 'write_page', { source => 'empty.md', front_matter => {}, body => 'Hi' }, 'empty front matter');
    is(slurp('_source/empty.md'), "---\n---\n\nHi\n", 'empty front matter is two lines of dashes');
    my $back = ok_call($d, 'read_page', { source => 'empty.md' }, 'read it back');
    is($back->{body}, "Hi\n", 'the page reads back as a page');
    ok_call($d, 'write_page', { source => 'nobody.md', front_matter => { title => 'No body' } }, 'no body');
    is(slurp('_source/nobody.md'), "---\ntitle: No body\n---\n\n\n", 'a missing body is empty');

    ok_call($d, 'write_page', { source => '_source/prefixed.md', front_matter => { title => 'P' }, body => 'x' }, 'prefixed');
    ok(-f '_source/prefixed.md', 'a path with the source directory is not doubled');
    ok(!-e '_source/_source', 'no nested source directory');

    ok_call($d, 'write_page', { source => 'unicode.md', front_matter => { title => 'Ünïcödé — 日本' }, body => 'Café' }, 'unicode');
    like(slurp('_source/unicode.md'), qr/^title: Ünïcödé — 日本$/m, 'UTF-8 front matter');

    $result = call($d, 'write_page', { source => 'about.md', front_matter => { title => 'Again' }, body => 'x' });
    ok($result->{isError}, 'an existing file is refused');
    is_deeply($result->{structuredContent}, { written => JSON::false, error => '_source/about.md already exists; set overwrite to true to replace it' }, 'with the reason');
    like(slurp('_source/about.md'), qr/title: About/, 'and left alone');

    $result = call($d, 'write_page', { source => 'about.md', front_matter => { title => 'Again' }, body => 'x', overwrite => JSON::false });
    ok($result->{isError}, 'overwrite: false refuses too');
    ok_call($d, 'write_page', { source => 'about.md', front_matter => { title => 'Again' }, body => 'New', overwrite => JSON::true }, 'overwrite');
    is(slurp('_source/about.md'), "---\ntitle: Again\n---\n\nNew\n", 'overwritten');

    is(error_call($d, 'write_page', { source => 'x.md', front_matter => [ 'title' ], body => 'x' }), 'front_matter must be an object of page settings', 'front matter that is a list');
    is(error_call($d, 'write_page', { source => 'x.md', front_matter => 'title: x', body => 'x' }), 'front_matter must be an object of page settings', 'front matter that is text');
    is(error_call($d, 'write_page', { source => 'x.md', body => 'x' }), 'front_matter must be an object of page settings', 'no front matter');
    is(error_call($d, 'write_page', { source => 'x.md', front_matter => {}, body => ['x'] }), 'body must be text', 'a body that is a list');
    is(error_call($d, 'write_page', { source => 'x.md', front_matter => {}, body => { a => 1 } }), 'body must be text', 'a body that is an object');
    is(error_call($d, 'write_page', { front_matter => {}, body => 'x' }), 'give the source file, e.g. blog/my-post.md', 'no source');
    ok(!-e '_source/x.md', 'none of them written');

    for my $path ('../outside.md', '/tmp/outside.md', 'blog/../../outside.md', '.hidden.md', 'blog/.git/x.md') {
        my $error = error_call($d, 'write_page', { source => $path, front_matter => { title => 'x' }, body => 'x' });
        like($error, qr/^"\Q$path\E" must /, "refuses $path");
    }
    ok(!-e 'outside.md' && !-e '../outside.md', 'nothing written outside');
};

subtest 'write_page checks the schema' => sub {
    make_site({ %SITE,
        '_source/strict/_schema.yml' => "required: [title]\nadditional: false\nfields:\n  title:\n    type: string\n",
    });
    my $d = App::Dapper->new();

    my $result = call($d, 'write_page', { source => 'blog/bad.md', front_matter => { title => 'x' x 41, categories => ['other'] }, body => 'x' });
    ok($result->{isError}, 'a page that does not match is refused');
    is_deeply($result->{structuredContent}, {
        written  => JSON::false,
        schema   => '_source/blog/_schema.yml',
        error    => 'The front matter does not match _source/blog/_schema.yml, so the page was not written.',
        problems => [ '"date" is required', '"categories" has "other", which is not one of: blog, news', '"title" is 41 characters long; the most allowed is 40' ],
    }, 'with the schema and every problem');
    ok(!-e '_source/blog/bad.md', 'and not written');

    $result = call($d, 'write_page', { source => 'blog/2020/01/deep.md', front_matter => { title => 'Deep' }, body => 'x' });
    is_deeply($result->{structuredContent}->{problems}, ['"date" is required'], 'the nearest schema above applies to folders below it');
    ok(!-e '_source/blog/2020', 'no directories made for a refused page');

    $result = call($d, 'write_page', { source => 'strict/a.md', front_matter => { title => 'A', extra => 1 }, body => 'x' });
    is_deeply($result->{structuredContent}->{problems}, ['"extra" is not one of the fields in the schema'], 'additional: false');

    ok_call($d, 'write_page', { source => 'blog/good.md', front_matter => { title => 'Good', date => '2020-05-01', categories => ['news'] }, body => 'x' }, 'a page that matches');
    ok_call($d, 'write_page', { source => 'loose.md', front_matter => { anything => 'goes' }, body => 'x' }, 'outside any schema');

    $result = call($d, 'write_page', { source => 'blog/good.md', front_matter => { title => 'Good' }, body => 'x', overwrite => JSON::true });
    ok($result->{isError}, 'overwriting is checked against the schema too');
    like(slurp('_source/blog/good.md'), qr/categories:/, 'and the old page is kept');

    $result = call($d, 'write_page', { source => 'blog/good.md', front_matter => { title => 'Good' }, body => 'x' });
    like($result->{structuredContent}->{error}, qr/already exists/, 'an existing file is reported before the schema');

    spew('_source/broken/_schema.yml', "required: x\nbogus: 1\n");
    like(error_call($d, 'write_page', { source => 'broken/a.md', front_matter => { title => 'A' }, body => 'x' }),
        qr/\Athe schema "_source\/broken\/_schema\.yml" has problems:/, 'a broken schema is an error');
    ok(!-e '_source/broken/a.md', 'and nothing is written');
};

subtest 'write_page and symbolic links' => sub {
    my $outside = tempdir(CLEANUP => 1);
    make_site({ %SITE });
    plan skip_all => 'symbolic links are not available' unless eval { symlink($outside, '_source/linked') };
    my $d = App::Dapper->new();
    call($d, 'write_page', { source => 'linked/escape.md', front_matter => { title => 'x' }, body => 'x' });
    ok(!-e "$outside/escape.md", 'nothing is written outside the source directory');
};

subtest 'rename_page' => sub {
    make_site({ %SITE, '_source/about.md' => "---\ntitle: About\n---\nAbout.\n" });
    my $d = App::Dapper->new();

    my $result = ok_call($d, 'rename_page', { source => 'about.md', new_source => 'us.md' }, 'rename');
    is_deeply($result, {
        moved    => JSON::true,
        from     => '_source/about.md',
        to       => '_source/us.md',
        old_url  => '/about.html',
        new_url  => '/us.html',
        redirect => '/about.html -> /us.html (in _data/redirects.yml)',
        note     => 'Run check to find problems, or build to publish.',
    }, 'the result');
    ok(!-e '_source/about.md', 'the old file is gone');
    is(slurp('_source/us.md'), "---\ntitle: About\n---\nAbout.\n", 'the new file has the same content');
    is(slurp('_data/redirects.yml'), "# Redirects from old URLs to new ones (written by Dapper when pages move; edit freely)\n/about.html: /us.html\n", 'a redirect is recorded');

    ok_call($d, 'rename_page', { source => 'us.md', new_source => 'company/team.md' }, 'move into a new folder');
    ok(-f '_source/company/team.md', 'the folder is made');
    is(slurp('_data/redirects.yml'), "# Redirects from old URLs to new ones (written by Dapper when pages move; edit freely)\n/about.html: /company/team.html\n/us.html: /company/team.html\n", 'earlier redirects point at the new URL: no chains');

    ok_call($d, 'rename_page', { source => 'company/team.md', new_source => 'about.md' }, 'move back');
    is(slurp('_data/redirects.yml'), "# Redirects from old URLs to new ones (written by Dapper when pages move; edit freely)\n/company/team.html: /about.html\n/us.html: /about.html\n", 'moving back drops the redirect from the URL that is in use again');

    $result = ok_call($d, 'rename_page', { source => 'blog/first.md', new_source => 'blog/renamed.md' }, 'a post with a URL pattern');
    is($result->{old_url}, '/blog/2020/01/first/', 'old url');
    is($result->{new_url}, '/blog/2020/01/first/', 'the same url, from the title');
    ok(!exists $result->{redirect}, 'so no redirect');
    unlike(slurp('_data/redirects.yml'), qr/first/, 'and none recorded');

    $result = ok_call($d, 'rename_page', { source => 'notes.txt', new_source => 'docs/notes.txt' }, 'a file that is not a page');
    is($result->{old_url}, undef, 'has no old url');
    is($result->{new_url}, undef, 'nor a new one');
    ok(!exists $result->{redirect}, 'and gets no redirect');
    ok(-f '_source/docs/notes.txt', 'but is moved');

    spew('_source/page.md', "---\ntitle: Page\n---\nx\n");
    $result = ok_call($d, 'rename_page', { source => 'page.md', new_source => 'page.txt' }, 'another extension');
    is($result->{new_url}, '/page.html', 'keeps the url, so');
    ok(!exists $result->{redirect}, 'no redirect is added');
    $result = ok_call($d, 'rename_page', { source => 'page.txt', new_source => '_archive/page.md' }, 'into a folder starting with _');
    is($result->{new_url}, '/_archive/page.html', 'which is still published below the top level');
    is($result->{redirect}, '/page.html -> /_archive/page.html (in _data/redirects.yml)', 'so it gets a redirect');

    ok_call($d, 'rename_page', { source => '_source/index.md', new_source => '_source/home.md' }, 'paths with the source directory');
    ok(-f '_source/home.md', 'are accepted');
    like(slurp('_data/redirects.yml'), qr{^/: /home\.html$}m, 'the home page gets a redirect from /');
};

subtest 'rename_page refusals' => sub {
    make_site({ %SITE,
        '_source/about.md'  => "---\ntitle: About\n---\nAbout.\n",
        '_source/taken.md'  => "---\ntitle: Taken\n---\nTaken.\n",
        '_source/strict/_schema.yml' => "required: [title, order]\n",
    });
    my $d = App::Dapper->new();

    my $result = call($d, 'rename_page', { source => 'about.md', new_source => 'taken.md' });
    ok($result->{isError}, 'onto an existing file: refused');
    is_deeply($result->{structuredContent}, { moved => JSON::false, error => '_source/taken.md already exists' }, 'with the reason');
    ok(-f '_source/about.md', 'nothing moved');
    is(slurp('_source/taken.md'), "---\ntitle: Taken\n---\nTaken.\n", 'nothing overwritten');

    $result = call($d, 'rename_page', { source => 'about.md', new_source => 'strict/about.md' });
    ok($result->{isError}, 'into a folder whose schema it does not match: refused');
    is_deeply($result->{structuredContent}, { moved => JSON::false, schema => '_source/strict/_schema.yml',
        problems => ['"order" is required'], error => 'The page does not match _source/strict/_schema.yml, so it was not moved.' }, 'with the problems');
    ok(-f '_source/about.md', 'nothing moved');

    is(error_call($d, 'rename_page', { source => 'missing.md', new_source => 'x.md' }), 'there is no file "_source/missing.md"', 'a missing page');
    is(error_call($d, 'rename_page', { source => 'about.md' }), 'give the source file, e.g. blog/my-post.md', 'no new source');
    is(error_call($d, 'rename_page', { new_source => 'x.md' }), 'give the source file, e.g. blog/my-post.md', 'no source');
    is(error_call($d, 'rename_page', { source => 'about.md', new_source => '../about.md' }), '"../about.md" must not contain ..', 'out of the source directory');
    is(error_call($d, 'rename_page', { source => '../_config.yml', new_source => 'config.md' }), '"../_config.yml" must not contain ..', 'from outside it');
    is(error_call($d, 'rename_page', { source => 'about.md', new_source => '.about.md' }), '".about.md" must not be a hidden file', 'to a hidden file');
    ok(-f '_source/about.md' && !-e '_data/redirects.yml', 'nothing moved, no redirects');
};

subtest 'redirects' => sub {
    make_site({ %SITE,
        '_config.yml'         => "---\nname: R\ndata_dir: info\n",
        '_source/about.md'    => "---\ntitle: About\n---\nAbout.\n",
        'info/redirects.yml'  => "/old/: /about.html\n/other/: /elsewhere/\n",
    });
    my $d = App::Dapper->new();
    $d->read_project();
    is(App::Dapper::MCP::redirects_file($d), 'info/redirects.yml', 'the redirects file is in the data directory');

    ok_call($d, 'rename_page', { source => 'about.md', new_source => 'us.md' }, 'rename');
    is(slurp('info/redirects.yml'), "# Redirects from old URLs to new ones (written by Dapper when pages move; edit freely)\n/about.html: /us.html\n/old/: /us.html\n/other/: /elsewhere/\n", 'existing redirects kept, chains collapsed');

    spew('info/redirects.yml', "- not\n- a map\n");
    App::Dapper::MCP::add_redirect($d, '/a/', '/b/');
    is(slurp('info/redirects.yml'), "# Redirects from old URLs to new ones (written by Dapper when pages move; edit freely)\n/a/: /b/\n", 'a redirects file that is not a map is replaced');

    App::Dapper::MCP::add_redirect($d, '/b/', '/a/');
    is(slurp('info/redirects.yml'), "# Redirects from old URLs to new ones (written by Dapper when pages move; edit freely)\n/b/: /a/\n", 'no redirect from a URL to itself');
};

subtest 'read_layout' => sub {
    make_site({ %SITE, '_layout/feed.xml' => "<feed/>" });
    my $d = App::Dapper->new();
    is_deeply(ok_call($d, 'read_layout', { name => 'post' }, 'post'),
        { name => 'post', file => '_layout/post.html', content => "---\nlayout: index\ndescription: A post\n---\n<article>[% page.content %]</article>" }, 'name, file and content');
    is(ok_call($d, 'read_layout', { name => 'post.html' }, 'with .html')->{name}, 'post', '.html is dropped from the name');
    is(ok_call($d, 'read_layout', { name => 'post.htm' }, 'with .htm')->{name}, 'post', 'and .htm');
    is(ok_call($d, 'read_layout', { name => 'feed' }, 'xml')->{file}, '_layout/feed.xml', 'layouts with other extensions');
    is(error_call($d, 'read_layout', { name => 'nope' }), 'there is no layout called "nope" in _layout', 'a missing layout');
    is(error_call($d, 'read_layout', {}), "give the layout's name, e.g. post", 'no name');
    is(error_call($d, 'read_layout', { name => '' }), "give the layout's name, e.g. post", 'an empty name');
    for my $name ('../post', 'a/b', 'a b', 'post.txt', '.hidden', 'naïve') {
        is(error_call($d, 'read_layout', { name => $name }), 'a layout name can only have letters, digits, - and _', "refuses \"$name\"");
    }
    is(App::Dapper::MCP::layout_name('My_Layout-2.html'), 'My_Layout-2', 'layout_name keeps letters, digits, - and _');
};

subtest 'write_layout' => sub {
    make_site({ %SITE });
    my $d = App::Dapper->new();

    is_deeply(ok_call($d, 'write_layout', { name => 'plain', content => '<p>[% page.content %]</p>' }, 'new'),
        { written => JSON::true, file => '_layout/plain.html', note => 'Run check to find problems, or build to publish.' }, 'the result');
    is(slurp('_layout/plain.html'), "<p>[% page.content %]</p>\n", 'written with a final newline');

    ok_call($d, 'write_layout', { name => 'wrapped.html', content => "---\nlayout: index\ndescription: Wrapped\n---\n[% page.content %]\n" }, 'wrapped');
    is(slurp('_layout/wrapped.html'), "---\nlayout: index\ndescription: Wrapped\n---\n[% page.content %]\n", 'with front matter, as given');

    my $result = call($d, 'write_layout', { name => 'post', content => 'x' });
    ok($result->{isError}, 'an existing layout is refused');
    is_deeply($result->{structuredContent}, { written => JSON::false, error => '_layout/post.html already exists; set overwrite to true to replace it' }, 'with the reason');
    ok_call($d, 'write_layout', { name => 'post', content => '<div>[% page.content %]</div>', overwrite => JSON::true }, 'overwrite');
    is(slurp('_layout/post.html'), "<div>[% page.content %]</div>\n", 'overwritten');

    spew('_layout/feed.xml', '<feed/>');
    ok(call($d, 'write_layout', { name => 'feed', content => '<rss/>' })->{isError}, 'a layout with another extension is found');
    ok_call($d, 'write_layout', { name => 'feed', content => '<rss/>', overwrite => JSON::true }, 'and overwritten');
    is(slurp('_layout/feed.xml'), "<rss/>\n", 'in its own file');
    ok(!-e '_layout/feed.html', 'without a new .html file');

    $result = call($d, 'write_layout', { name => 'broken', content => '[% IF page.title %]no end' });
    ok($result->{isError}, 'a template error is refused');
    is_deeply($result->{structuredContent}, { written => JSON::false, error => $result->{structuredContent}->{error} }, 'and nothing else');
    like($result->{structuredContent}->{error}, qr/\AThe layout has a template error, so it was not saved: parse error - input text line 1 char \d+: Missing END directive\z/, 'with the parse error');
    ok(!-e '_layout/broken.html', 'and not saved');

    $result = call($d, 'write_layout', { name => 'broken', content => "---\ndescription: x\n---\n[% FOREACH %]" });
    like($result->{structuredContent}->{error}, qr/^The layout has a template error, so it was not saved: /, 'the template after front matter is checked');

    ok_call($d, 'write_layout', { name => 'described', content => "---\ndescription: Only a description\n---\n[% page.content %]" }, 'front matter without a layout');
    ok(-f '_layout/described.html', 'is saved');

    $result = call($d, 'write_layout', { name => 'orphan', content => "---\nlayout: missing\n---\n[% page.content %]" });
    ok($result->{isError}, 'wrapping in a missing layout is refused');
    is($result->{structuredContent}->{error}, 'The layout wraps itself in "missing", which does not exist, so it was not saved.', 'with the reason');
    ok(!-e '_layout/orphan.html', 'and not saved');

    is(error_call($d, 'write_layout', { name => 'x' }), 'content must be text', 'no content');
    is(error_call($d, 'write_layout', { name => 'x', content => ['a'] }), 'content must be text', 'content that is a list');
    is(error_call($d, 'write_layout', { content => 'x' }), "give the layout's name, e.g. post", 'no name');
    is(error_call($d, 'write_layout', { name => '../escape', content => 'x' }), 'a layout name can only have letters, digits, - and _', 'a path as the name');
    ok(!-e 'escape.html' && !-e '_layout/x.html', 'nothing written');

    ok_call($d, 'write_layout', { name => 'empty', content => '' }, 'empty content');
    is(slurp('_layout/empty.html'), "\n", 'is a newline');
};

subtest 'build' => sub {
    make_site({ %SITE, '_source/draft.md' => "---\ntitle: Draft\ndraft: true\n---\nDraft.\n" });
    my $d = App::Dapper->new();
    my $result = ok_call($d, 'build', {}, 'build');
    ok(JSON::is_bool($result->{built}) && $result->{built}, 'built is true');
    is($result->{output}, '_output', 'the output directory');
    is($result->{pages}, 4, 'the number of pages');
    ok($result->{files} > $result->{pages}, 'and of files written');
    is_deeply([ sort keys %$result ], [qw(built files output pages)], 'nothing else');
    ok(-f '_output/blog/2020/01/first/index.html', 'the site is built');
    ok(!-e '_output/draft.html', 'without drafts');
    is($d->{quiet}, 0, 'quiet is put back');

    $result = ok_call($d, 'build', { drafts => JSON::true }, 'drafts');
    is($result->{pages}, 5, 'drafts: true includes them');
    ok(-f '_output/draft.html', 'and writes them');
    is($d->{drafts}, undef, 'drafts is put back');

    $result = ok_call($d, 'build', { drafts => JSON::false }, 'no drafts');
    is($result->{pages}, 4, 'drafts: false leaves them out');
    ok(!-e '_output/draft.html', 'and removes them');

    $result = App::Dapper::MCP::build($d, 'not an object');
    is($result->{pages}, 4, 'build arguments that are not an object mean no drafts');
    is(App::Dapper::MCP::check($d, undef)->{pages}, 4, 'and for check');

    spew('_layout/index.html', '[% IF %]');
    my $error = error_call($d, 'build', {});
    like($error, qr/\Acould not process _source\/\S+ with layout index: parse error - input text line 1 char \d+: Missing END directive\z/, 'a failed build is a tool error');
};

subtest 'check' => sub {
    make_site({ %SITE, '_source/draft.md' => "---\ntitle: Draft\ndraft: true\n---\n[x](/nowhere/)\n" });
    my $d = App::Dapper->new();
    my $result = call($d, 'check', {});
    ok(!$result->{isError}, 'check is not a tool error');
    my $report = $result->{structuredContent};
    ok($report->{ok}, 'the site is ok');
    is($report->{pages}, 4, 'pages checked');
    is_deeply($report->{held}, [ { file => '_source/draft.md', reason => 'draft' } ], 'the draft is held');
    ok(!-e '_output', 'nothing is built');

    $result = call($d, 'check', { drafts => JSON::true });
    ok(!$result->{isError}, 'a report with errors is still not a tool error');
    $report = $result->{structuredContent};
    ok(!$report->{ok}, 'drafts: true checks the draft, which has a broken link');
    is($report->{errors}->[0]->{file}, '_source/draft.md', 'naming it');
    is($report->{errors}->[0]->{type}, 'link', 'as a link error');
    is_deeply($report->{held}, [], 'nothing held');
    is($d->{drafts}, undef, 'drafts is put back');
};

done_testing();
