use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;
use JSON ();
use Cwd qw(abs_path getcwd);
use File::Spec;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::MCP;

my $dapper_bin = abs_path(File::Spec->catfile('bin', 'dapper'));
my $lib = abs_path('lib');

sub call {
    my ($d, $name, $args) = @_;
    my $response = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 1, method => 'tools/call',
        params => { name => $name, arguments => $args || {} } });
    return $response->{result};
}

make_site({
    '_config.yml'             => "---\nname: Test\nurl: https://example.com\n",
    '_source/blog/_schema.yml' => "required: [title, date]\nfields:\n  categories:\n    type: list\n    values: [blog]\n",
    '_source/blog/first.md'   => "---\ntitle: First\ndate: 2020-01-01\ncategories: blog\ntags: [a]\n---\n\nHello.\n",
    '_source/index.md'        => "---\ntitle: Home\n---\nHome.\n",
});
my $d = App::Dapper->new();

subtest 'protocol' => sub {
    my $init = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 1, method => 'initialize', params => { protocolVersion => '2025-06-18' } });
    is($init->{result}->{serverInfo}->{name}, 'dapper', 'server name');
    is($init->{result}->{protocolVersion}, '2025-06-18', 'protocol version');
    ok(exists $init->{result}->{capabilities}->{tools}, 'tools capability');

    is(App::Dapper::MCP::handle($d, { jsonrpc => '2.0', method => 'notifications/initialized' }), undef, 'notifications get no reply');

    my $list = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 2, method => 'tools/list' });
    is_deeply([ map { $_->{name} } @{ $list->{result}->{tools} } ], [qw(site_info list_pages read_page write_page build check)], 'tools');

    my $unknown = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 3, method => 'nope' });
    is($unknown->{error}->{code}, -32601, 'unknown method');

    my $tool = call($d, 'nope');
    ok($tool->{isError}, 'unknown tool is a tool error');
};

subtest 'site_info and list_pages' => sub {
    my $info = call($d, 'site_info')->{structuredContent};
    is($info->{name}, 'Test', 'name');
    is($info->{pages}, 2, 'pages');
    is_deeply($info->{categories}, { blog => 1 }, 'categories');
    is($info->{schemas}->[0]->{applies_to}, '_source/blog', 'schema location');
    is_deeply($info->{schemas}->[0]->{required}, ['title', 'date'], 'schema required fields');

    my $pages = call($d, 'list_pages', { tag => 'a' })->{structuredContent}->{pages};
    is(scalar @$pages, 1, 'filtered by tag');
    is($pages->[0]->{source}, 'blog/first.md', 'source relative to the source directory');
    is($pages->[0]->{url}, '/blog/2020/01/first/', 'url');
};

subtest 'read_page' => sub {
    my $page = call($d, 'read_page', { source => 'blog/first.md' })->{structuredContent};
    is($page->{front_matter}->{title}, 'First', 'front matter');
    is($page->{body}, "Hello.\n", 'body');
    ok(call($d, 'read_page', { source => 'missing.md' })->{isError}, 'missing file is an error');
};

subtest 'write_page' => sub {
    my $bad = call($d, 'write_page', { source => 'blog/bad.md', front_matter => { title => 'Bad', categories => ['news'] }, body => 'x' });
    ok($bad->{isError}, 'refused');
    is_deeply($bad->{structuredContent}->{problems}, ['"date" is required', '"categories" has "news", which is not one of: blog'], 'with the problems');
    ok(!-e '_source/blog/bad.md', 'and not written');

    for my $path ('../outside.md', '/etc/passwd', 'blog/../../x.md', '.hidden.md') {
        my $result = call($d, 'write_page', { source => $path, front_matter => {}, body => 'x' });
        ok($result->{isError}, "refuses $path");
    }

    my $good = call($d, 'write_page', { source => 'blog/new.md',
        front_matter => { title => 'Nouveau café', date => '2020-02-01', categories => ['blog'], draft => JSON::false }, body => 'Écrit.' });
    ok(!$good->{isError}, 'written') or diag explain $good;
    my $text = slurp('_source/blog/new.md');
    like($text, qr/^---\n.*title: Nouveau café\n.*---\n\nÉcrit\.\n\z/s, 'front matter and body');
    like($text, qr/draft: false/, 'booleans written as booleans');

    ok(call($d, 'write_page', { source => 'blog/new.md', front_matter => { title => 'x', date => '2020-01-01' }, body => 'x' })->{isError},
        'will not overwrite without overwrite: true');
    ok(!call($d, 'write_page', { source => 'blog/new.md', front_matter => { title => 'x', date => '2020-01-01' }, body => 'x', overwrite => JSON::true })->{isError},
        'overwrites when asked');
};

subtest 'check and build' => sub {
    my $check = call($d, 'check');
    ok(!$check->{isError}, 'check is not a tool error');
    ok($check->{structuredContent}->{ok}, 'site is ok');

    my $build = call($d, 'build')->{structuredContent};
    ok($build->{built}, 'built');
    ok(-f '_output/blog/2020/01/first/index.html', 'output written');
};

subtest 'over standard input and output' => sub {
    my $dir = getcwd();
    my $requests = join('', map { JSON->new->encode($_) . "\n" }
        { jsonrpc => '2.0', id => 1, method => 'initialize', params => {} },
        { jsonrpc => '2.0', method => 'notifications/initialized' },
        { jsonrpc => '2.0', id => 2, method => 'tools/call', params => { name => 'build', arguments => {} } });
    spew('requests.jsonl', $requests);
    my $output = `"$^X" "-I$lib" "$dapper_bin" -C "$dir" mcp < requests.jsonl 2>/dev/null`;
    my @lines = split /\n/, $output;
    is(scalar @lines, 2, 'one line per request, nothing else on standard output');
    my @responses = map { JSON->new->decode($_) } @lines;
    is($responses[0]->{result}->{serverInfo}->{name}, 'dapper', 'initialize answered');
    ok($responses[1]->{result}->{structuredContent}->{built}, 'build answered');
};

done_testing();
