use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::MCP;

subtest 'init writes AGENTS.md and CLAUDE.md' => sub {
    make_site({}, bare => 1);
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{template} = 'blog';
    $d->init();

    my $agents = slurp('AGENTS.md');
    like($agents, qr/^<!-- dapper:begin/, 'generated part is marked');
    like($agents, qr/# Working on My Blog/, 'names the site');
    like($agents, qr/`dapper check --json`/, 'explains check');
    like($agents, qr/### `_source\/blog\/`\n\n- Required: `title`, `date`, `categories`/, 'lists the schema');
    like($agents, qr/- `categories`: list, one of `blog`/, 'with allowed values');
    like($agents, qr/- Tags: `dapper`, `writing`/, 'tags in use');
    like($agents, qr/<!-- dapper:end -->\n\n## About this blog/, 'theme notes after the generated part');
    like(slurp('CLAUDE.md'), qr/^\@AGENTS\.md$/m, 'CLAUDE.md imports AGENTS.md');
};

subtest 'dapper agents keeps what is outside the markers' => sub {
    make_site({
        '_source/index.md'   => "---\ntitle: Home\n---\nx\n",
        '_layout/index.html' => "---\ndescription: The page wrapper\n---\n[% page.content %]",
        'CLAUDE.md'          => "My own Claude notes\n",
    });
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->agents();
    my $first = slurp('AGENTS.md');
    like($first, qr/- `index`: The page wrapper/, 'layouts describe themselves');
    is(slurp('CLAUDE.md'), "My own Claude notes\n", 'an existing CLAUDE.md is left alone');

    spew('AGENTS.md', "# Our notes\n\n$first\nMore notes\n");
    spew('_source/_schema.yml', "required: [title, summary]\n");
    $d->agents();
    my $second = slurp('AGENTS.md');
    like($second, qr/\A# Our notes\n\n<!-- dapper:begin/, 'notes before kept');
    like($second, qr/<!-- dapper:end -->\n\nMore notes\n\z/, 'notes after kept');
    like($second, qr/- Required: `title`, `summary`/, 'generated part updated');
    is(() = $second =~ /dapper:begin/g, 1, 'only one generated part');
};

subtest 'MCP prompts and resources' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });
    my $d = App::Dapper->new();

    my $init = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 1, method => 'initialize', params => {} });
    ok(exists $init->{result}->{capabilities}->{$_}, "$_ capability") for qw(tools prompts resources);

    my $list = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 2, method => 'prompts/list' });
    is_deeply([ map { $_->{name} } @{ $list->{result}->{prompts} } ], [qw(new_site write_post audit_site)], 'prompts');

    my $prompt = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 3, method => 'prompts/get',
        params => { name => 'write_post', arguments => { topic => 'Sourdough', category => 'blog' } } });
    like($prompt->{result}->{messages}->[0]->{content}->{text}, qr/in the "blog" category about:\n\nSourdough/, 'prompt text');

    my $missing = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 4, method => 'prompts/get', params => { name => 'nope' } });
    is($missing->{error}->{code}, -32602, 'unknown prompt');

    my $resources = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 5, method => 'resources/list' });
    is_deeply([ map { $_->{uri} } @{ $resources->{result}->{resources} } ], [qw(dapper://guide dapper://config dapper://schemas)], 'resources');

    my $guide = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 6, method => 'resources/read', params => { uri => 'dapper://guide' } });
    like($guide->{result}->{contents}->[0]->{text}, qr/# Working on Test Site/, 'guide');
    my $config = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 7, method => 'resources/read', params => { uri => 'dapper://config' } });
    like($config->{result}->{contents}->[0]->{text}, qr/name: Test Site/, 'config');
};

done_testing();
