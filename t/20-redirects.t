use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::MCP;

sub call {
    my ($d, $name, $args) = @_;
    return App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 1, method => 'tools/call',
        params => { name => $name, arguments => $args || {} } })->{result};
}

subtest 'redirects from the project file and the data file' => sub {
    make_site({
        '_config.yml'        => "---\nname: x\nurl: https://example.com\nredirects:\n  /old/: /new.html\n  /gone.html: https://elsewhere.example/\n",
        '_data/redirects.yml' => "/older: /new.html\n",
        '_source/new.md'     => "---\ntitle: New\n---\nx\n",
    });
    quiet_build();
    my $page = slurp('_output/old/index.html');
    like($page, qr{<meta http-equiv="refresh" content="0; url=/new\.html">}, 'refresh to the new URL');
    like($page, qr{<link rel="canonical" href="https://example\.com/new\.html">}, 'canonical is absolute');
    like($page, qr{<meta name="robots" content="noindex">}, 'not indexed');
    like(slurp('_output/gone.html'), qr{url=https://elsewhere\.example/}, 'redirect to another site');
    ok(-f '_output/older/index.html', 'from the data file, without a trailing slash');
    unlike(slurp('_output/sitemap.xml'), qr/old/, 'redirects are not in the sitemap');
};

subtest 'a page still at the old URL wins' => sub {
    make_site({
        '_config.yml'      => "---\nname: x\nredirects:\n  /a.html: /b.html\n",
        '_source/a.md'     => "---\ntitle: A\n---\nStill here\n",
        '_source/b.md'     => "---\ntitle: B\n---\nx\n",
    });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    like(slurp('_output/a.html'), qr/Still here/, 'page kept');
    like(join('', @warnings), qr{a page is still at /a\.html}, 'with a warning');
};

subtest 'check reports redirects to nowhere' => sub {
    make_site({ '_config.yml' => "---\nname: x\nredirects:\n  /old/: /missing/\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    my $report = App::Dapper->new()->check();
    my ($problem) = grep { $_->{type} eq 'link' } @{ $report->{errors} };
    is($problem->{file}, 'the redirect from /old/', 'named by its old URL');
    like($problem->{message}, qr{links to /missing/}, 'and the missing target');
};

subtest 'bad redirects' => sub {
    make_site({ '_config.yml' => "---\nname: x\nredirects:\n  old: /new/\n", '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    eval { quiet_build() };
    like($@, qr{the redirect from old must start with /}, 'old URL must start with /');
};

subtest 'MCP rename_page' => sub {
    make_site({
        '_source/blog/_schema.yml' => "required: [title, date]\n",
        '_source/blog/first.md'    => "---\ntitle: First Post\ndate: 2020-01-01\ncategories: blog\n---\nx\n",
        '_source/about.md'         => "---\ntitle: About\n---\nx\n",
        '_data/redirects.yml'      => "/very-old/: /about.html\n",
    });
    my $d = App::Dapper->new();

    my $moved = call($d, 'rename_page', { source => 'about.md', new_source => 'company/about.md' });
    ok(!$moved->{isError}, 'moved') or diag explain $moved;
    is($moved->{structuredContent}->{old_url}, '/about.html', 'old URL');
    is($moved->{structuredContent}->{new_url}, '/company/about.html', 'new URL');
    ok(-f '_source/company/about.md' && !-e '_source/about.md', 'file moved');
    my $redirects = slurp('_data/redirects.yml');
    like($redirects, qr{^/about\.html: /company/about\.html$}m, 'redirect added');
    like($redirects, qr{^/very-old/: /company/about\.html$}m, 'older redirect repointed, no chain');

    quiet_build();
    like(slurp('_output/about.html'), qr{url=/company/about\.html}, 'old URL redirects after a build');

    my $same = call($d, 'rename_page', { source => 'blog/first.md', new_source => 'blog/renamed.md' });
    ok(!$same->{isError}, 'renamed a post');
    ok(!exists $same->{structuredContent}->{redirect}, 'no redirect when the URL comes from the title and is unchanged');

    my $refused = call($d, 'rename_page', { source => 'company/about.md', new_source => 'blog/about.md' });
    ok($refused->{isError}, 'refused: it would not match the blog schema');
    is_deeply($refused->{structuredContent}->{problems}, ['"date" is required'], 'with the reason');
    ok(-f '_source/company/about.md', 'and not moved');

    ok(call($d, 'rename_page', { source => 'company/about.md', new_source => 'blog/renamed.md' })->{isError}, 'will not overwrite');
    ok(call($d, 'rename_page', { source => 'company/about.md', new_source => '../out.md' })->{isError}, 'stays in the source directory');
};

subtest 'MCP layouts' => sub {
    make_site({ '_source/a.md' => "---\ntitle: A\n---\nx\n" });
    my $d = App::Dapper->new();

    like(call($d, 'read_layout', { name => 'index' })->{structuredContent}->{content}, qr/page\.content/, 'read');
    ok(call($d, 'read_layout', { name => 'nope' })->{isError}, 'missing layout');

    my $broken = call($d, 'write_layout', { name => 'post', content => "<article>[% IF page.title %]\n" });
    ok($broken->{isError}, 'template error refused');
    like($broken->{structuredContent}->{error}, qr/Missing END directive/, 'with the parser message');
    ok(!-e '_layout/post.html', 'not saved');

    ok(call($d, 'write_layout', { name => 'post', content => "---\nlayout: nope\n---\nx" })->{isError}, 'missing parent refused');
    ok(call($d, 'write_layout', { name => '../evil', content => 'x' })->{isError}, 'bad name refused');

    my $good = call($d, 'write_layout', { name => 'post', content => "---\nlayout: index\ndescription: A post\n---\n<article>[% page.content %]</article>" });
    ok(!$good->{isError}, 'saved') or diag explain $good;
    like(slurp('_layout/post.html'), qr{<article>\[% page\.content %\]</article>\n\z}, 'content written');
    ok(call($d, 'write_layout', { name => 'index', content => 'x' })->{isError}, 'will not overwrite without overwrite');
};

done_testing();
