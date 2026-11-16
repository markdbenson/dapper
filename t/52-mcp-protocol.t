use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;
binmode(Test::More->builder->$_, q(:encoding(UTF-8))) for qw(output failure_output todo_output);

# The MCP server's JSON-RPC protocol: initialize, ping, the lists, prompts,
# resources, notifications and errors, through handle() and over standard
# input and output.

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::MCP;
use App::Dapper::Agents;
use Cwd qw(abs_path getcwd);
use File::Spec;
use File::Temp qw(tempdir);
use JSON ();

my $dapper_bin = abs_path(File::Spec->catfile('bin', 'dapper'));
my $lib = abs_path('lib');
my $io = tempdir(CLEANUP => 1);
my $json = JSON->new->utf8->canonical;

sub rpc {
    my ($d, $method, $params, $id) = @_;
    my %request = (jsonrpc => '2.0', id => defined $id ? $id : 1, method => $method);
    $request{params} = $params if defined $params;
    return App::Dapper::MCP::handle($d, \%request);
}

# Run App::Dapper::MCP::serve in this process with the given bytes on
# standard input; return the lines it printed and what went to standard error
sub serve_lines {
    my ($d, $input) = @_;
    spew("$io/in", $input, ':raw');
    open(my $saved_in, '<&', \*STDIN) or die $!;
    open(my $saved_out, '>&', \*STDOUT) or die $!;
    open(my $saved_err, '>&', \*STDERR) or die $!;
    open(STDIN, '<', "$io/in") or die $!;
    open(STDOUT, '>', "$io/out") or die $!;
    open(STDERR, '>', "$io/err") or die $!;
    eval { App::Dapper::MCP::serve($d) };
    my $error = $@;
    open(STDIN, '<&', $saved_in) or die $!;
    open(STDOUT, '>&', $saved_out) or die $!;
    open(STDERR, '>&', $saved_err) or die $!;
    die $error if $error;
    my $out = slurp("$io/out", ':raw');
    return ([ split /\n/, $out ], slurp("$io/err", ':raw'), $out);
}

make_site({
    '_config.yml'              => "---\nname: Protocol\nurl: https://example.com\n",
    '_source/index.md'         => "---\ntitle: Home\n---\nHome.\n",
    '_source/blog/_schema.yml' => "required: [title]\nfields:\n  title:\n    type: string\n    max_length: 50\n",
});
my $d = App::Dapper->new();

subtest 'initialize' => sub {
    my $response = rpc($d, 'initialize', { protocolVersion => '2024-11-05' }, 7);
    is($response->{jsonrpc}, '2.0', 'jsonrpc 2.0');
    is($response->{id}, 7, 'the id is returned');
    ok(!exists $response->{error}, 'no error');
    my $result = $response->{result};
    is($result->{protocolVersion}, '2024-11-05', 'the requested protocol version is accepted');
    is_deeply($result->{capabilities}, { tools => {}, prompts => {}, resources => {} }, 'tools, prompts and resources');
    is_deeply($result->{serverInfo}, { name => 'dapper', version => "$App::Dapper::VERSION" }, 'server name and version');
    ok(!ref $result->{serverInfo}->{version}, 'the version is a string');
    like($result->{instructions}, qr/^Dapper builds a static website from Markdown and HTML files with YAML front matter\. /, 'instructions say what Dapper is');
    like($result->{instructions}, qr/Use site_info first/, 'and to start with site_info');
    like($result->{instructions}, qr/then check to find problems and build to publish\.$/, 'and to check and build');

    is(rpc($d, 'initialize', {})->{result}->{protocolVersion}, '2025-06-18', 'without a version: 2025-06-18');
    is(rpc($d, 'initialize')->{result}->{protocolVersion}, '2025-06-18', 'without params');
    is(rpc($d, 'initialize', [ 'x' ])->{result}->{protocolVersion}, '2025-06-18', 'params that are not an object are ignored');
    is(rpc($d, 'initialize', 'x')->{result}->{protocolVersion}, '2025-06-18', 'a string too');
};

subtest 'ids and notifications' => sub {
    is_deeply(rpc($d, 'ping'), { jsonrpc => '2.0', id => 1, result => {} }, 'ping returns an empty result');
    is(rpc($d, 'ping', undef, 'abc')->{id}, 'abc', 'string ids');
    is(rpc($d, 'ping', undef, 0)->{id}, 0, 'an id of 0 is not a notification');
    ok(rpc($d, 'ping', undef, 0)->{result}, 'and is answered');

    for my $method (qw(notifications/initialized notifications/cancelled ping nope tools/list)) {
        is(App::Dapper::MCP::handle($d, { jsonrpc => '2.0', method => $method }), undef, "$method without an id gets no reply");
    }
    is(App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => undef, method => 'ping' }), undef, 'an id of null gets no reply');

    my $none = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', method => 'tools/call',
        params => { name => 'write_page', arguments => { source => 'notified.md', front_matter => { title => 'x' }, body => 'x' } } });
    is($none, undef, 'a tool call without an id gets no reply');
    ok(!-e '_source/notified.md', 'and is not run');
};

subtest 'unknown methods' => sub {
    my $response = rpc($d, 'resources/subscribe', {}, 5);
    is_deeply($response, { jsonrpc => '2.0', id => 5, error => { code => -32601, message => 'Method not found: resources/subscribe' } }, 'exact error');

    $response = App::Dapper::MCP::handle($d, { jsonrpc => '2.0', id => 6 });
    is_deeply($response->{error}, { code => -32601, message => 'Method not found: ' }, 'a missing method');
    is($response->{id}, 6, 'with the id');

    $response = rpc($d, 'Initialize');
    is($response->{error}->{code}, -32601, 'methods are case sensitive');
};

subtest 'tools/list' => sub {
    my $tools = rpc($d, 'tools/list')->{result}->{tools};
    is_deeply([ map { $_->{name} } @$tools ], [qw(site_info list_pages read_page write_page rename_page read_layout write_layout build check)], 'every tool, in order');
    for my $tool (@$tools) {
        ok(length $tool->{description} > 20, "$tool->{name} has a description");
        is($tool->{inputSchema}->{type}, 'object', "$tool->{name} takes an object");
        is(ref $tool->{inputSchema}->{properties}, 'HASH', "$tool->{name} lists its properties");
        for my $required (@{ $tool->{inputSchema}->{required} || [] }) {
            ok(exists $tool->{inputSchema}->{properties}->{$required}, "$tool->{name}: required $required is a property");
        }
    }
    my %tool = map { $_->{name} => $_ } @$tools;
    is_deeply($tool{site_info}->{inputSchema}->{properties}, {}, 'site_info takes nothing');
    is_deeply([ sort keys %{ $tool{list_pages}->{inputSchema}->{properties} } ], [qw(category tag)], 'list_pages takes category and tag');
    ok(!exists $tool{list_pages}->{inputSchema}->{required}, 'neither required');
    is_deeply($tool{read_page}->{inputSchema}->{required}, ['source'], 'read_page needs source');
    is_deeply($tool{write_page}->{inputSchema}->{required}, [qw(source front_matter body)], 'write_page needs source, front_matter and body');
    is($tool{write_page}->{inputSchema}->{properties}->{front_matter}->{type}, 'object', 'front_matter is an object');
    is($tool{write_page}->{inputSchema}->{properties}->{overwrite}->{type}, 'boolean', 'overwrite is a boolean');
    is_deeply($tool{rename_page}->{inputSchema}->{required}, [qw(source new_source)], 'rename_page needs source and new_source');
    is_deeply($tool{read_layout}->{inputSchema}->{required}, ['name'], 'read_layout needs name');
    is_deeply($tool{write_layout}->{inputSchema}->{required}, [qw(name content)], 'write_layout needs name and content');
    is($tool{write_layout}->{inputSchema}->{properties}->{overwrite}->{type}, 'boolean', 'write_layout overwrite is a boolean');
    for my $name (qw(build check)) {
        is_deeply($tool{$name}->{inputSchema}->{properties}->{drafts}->{type}, 'boolean', "$name takes drafts");
    }
    like($tool{write_page}->{description}, qr/_schema\.yml/, 'write_page mentions the schema');
    like($tool{rename_page}->{description}, qr/_data\/redirects\.yml/, 'rename_page mentions redirects');
};

subtest 'tools/call' => sub {
    my $result = rpc($d, 'tools/call', { name => 'nope', arguments => {} })->{result};
    is_deeply($result->{structuredContent}, { error => 'There is no tool called "nope".' }, 'an unknown tool');
    ok($result->{isError}, 'is a tool error');
    ok(JSON::is_bool($result->{isError}), 'isError is a JSON boolean');

    $result = rpc($d, 'tools/call', {})->{result};
    is($result->{structuredContent}->{error}, 'There is no tool called "".', 'no tool name');

    $result = rpc($d, 'tools/call')->{result};
    is($result->{structuredContent}->{error}, 'There is no tool called "".', 'no params');

    $result = rpc($d, 'tools/call', { name => 'read_page', arguments => [ 'index.md' ] })->{result};
    is($result->{structuredContent}->{error}, 'give the source file, e.g. blog/my-post.md', 'arguments that are not an object are ignored');

    $result = rpc($d, 'tools/call', { name => 'read_page' })->{result};
    is($result->{structuredContent}->{error}, 'give the source file, e.g. blog/my-post.md', 'and so are missing arguments');

    $result = rpc($d, 'tools/call', { name => 'read_page', arguments => { source => 'index.md' } })->{result};
    ok(JSON::is_bool($result->{isError}) && !$result->{isError}, 'success: isError is false');
    is(scalar @{$result->{content}}, 1, 'one content item');
    is($result->{content}->[0]->{type}, 'text', 'of type text');
    is_deeply(JSON->new->decode($result->{content}->[0]->{text}), JSON->new->decode(JSON->new->encode($result->{structuredContent})), 'whose text is the structured content as JSON');
    like($result->{content}->[0]->{text}, qr/\A\{\n   "body" : /, 'pretty and canonical');

    my $error = App::Dapper::MCP::tool_result({ error => 'x' }, 1);
    ok($error->{isError}, 'tool_result marks errors');
    is($error->{content}->[0]->{text}, qq({\n   "error" : "x"\n}\n), 'with the text');
    ok(!App::Dapper::MCP::tool_result({}, 0)->{isError}, 'and not otherwise');
    ok(!App::Dapper::MCP::tool_result({})->{isError}, 'by default');
};

subtest 'tool errors are stripped of "error: " and trailing space' => sub {
    no warnings 'redefine';
    local *App::Dapper::MCP::site_info = sub { die "error: something broke\n\n" };
    my $result = App::Dapper::MCP::call_tool($d, 'site_info', {});
    is_deeply($result->{structuredContent}, { error => 'something broke' }, 'message cleaned');
    ok($result->{isError}, 'and an error');

    local *App::Dapper::MCP::site_info = sub { die "plain failure at somewhere line 3.\n" };
    $result = App::Dapper::MCP::call_tool($d, 'site_info', {});
    is($result->{structuredContent}->{error}, 'plain failure at somewhere line 3.', 'messages without the prefix are kept');

    local *App::Dapper::MCP::site_info = sub { return ({ fine => 1 }, 1) };
    $result = App::Dapper::MCP::call_tool($d, 'site_info', {});
    ok($result->{isError}, 'a tool can return an error without dying');
    is_deeply($result->{structuredContent}, { fine => 1 }, 'with its own data');
};

subtest 'prompts/list' => sub {
    my $prompts = rpc($d, 'prompts/list')->{result}->{prompts};
    is_deeply([ map { $_->{name} } @$prompts ], [qw(new_site write_post audit_site)], 'every prompt');
    my %prompt = map { $_->{name} => $_ } @$prompts;
    is_deeply([ map { $_->{name} } @{$prompt{new_site}->{arguments}} ], ['description'], 'new_site takes a description');
    ok($prompt{new_site}->{arguments}->[0]->{required}, 'which is required');
    is_deeply([ map { $_->{name} } @{$prompt{write_post}->{arguments}} ], [qw(topic category)], 'write_post takes a topic and a category');
    ok($prompt{write_post}->{arguments}->[0]->{required}, 'topic is required');
    ok(JSON::is_bool($prompt{write_post}->{arguments}->[1]->{required}) && !$prompt{write_post}->{arguments}->[1]->{required}, 'category is not');
    is_deeply($prompt{audit_site}->{arguments}, [], 'audit_site takes nothing');
    is($prompt{new_site}->{description}, 'Turn this project into a new site from a description of what it is for.', 'new_site description');
    is($prompt{write_post}->{description}, "Write a new post or page that matches the site's schemas.", 'write_post description');
    is($prompt{audit_site}->{description}, 'Check the whole site for problems and fix them.', 'audit_site description');
};

subtest 'prompts/get' => sub {
    my $steps = "Work through the dapper MCP tools: start with site_info to learn the schemas, "
              . "categories and layouts; use write_page for every page (it refuses pages that don't match "
              . "their schema, so fix what it reports); run check until it reports no errors; then build.";

    my $result = rpc($d, 'prompts/get', { name => 'new_site', arguments => { description => 'A bakery in Chicago' } })->{result};
    is($result->{description}, 'Turn this project into a new site from a description of what it is for.', 'new_site: description');
    is(scalar @{$result->{messages}}, 1, 'one message');
    is($result->{messages}->[0]->{role}, 'user', 'from the user');
    is($result->{messages}->[0]->{content}->{type}, 'text', 'as text');
    my $text = $result->{messages}->[0]->{content}->{text};
    like($text, qr/\ATurn this Dapper project into this site:\n\nA bakery in Chicago\n\n/, 'with the description');
    like($text, qr/Read the dapper:\/\/guide resource for this project's conventions\. \Q$steps\E\z/, 'the guide and the steps');
    like($text, qr/replace any placeholder text from the starter template/, 'and placeholders');

    $text = rpc($d, 'prompts/get', { name => 'new_site' })->{result}->{messages}->[0]->{content}->{text};
    like($text, qr/\ATurn this Dapper project into this site:\n\n\n\n/, 'new_site without a description');

    $text = rpc($d, 'prompts/get', { name => 'write_post', arguments => { topic => 'Rye bread', category => 'news' } })->{result}->{messages}->[0]->{content}->{text};
    like($text, qr/\AWrite a new post in the "news" category about:\n\nRye bread\n\n/, 'write_post with a category');
    like($text, qr/Use today's date, a clear title, a description of about 150 characters/, 'the details');
    like($text, qr/\Q$steps\E\z/, 'and the steps');

    $text = rpc($d, 'prompts/get', { name => 'write_post', arguments => { topic => 'Rye bread' } })->{result}->{messages}->[0]->{content}->{text};
    like($text, qr/\AWrite a new post about:\n\nRye bread\n\n/, 'write_post without a category');
    $text = rpc($d, 'prompts/get', { name => 'write_post', arguments => { topic => 'Rye', category => '' } })->{result}->{messages}->[0]->{content}->{text};
    like($text, qr/\AWrite a new post about:/, 'an empty category is no category');
    $text = rpc($d, 'prompts/get', { name => 'write_post', arguments => 'Rye' })->{result}->{messages}->[0]->{content}->{text};
    like($text, qr/\AWrite a new post about:\n\n\n\n/, 'arguments that are not an object are ignored');

    $result = rpc($d, 'prompts/get', { name => 'audit_site' })->{result};
    is($result->{description}, 'Check the whole site for problems and fix them.', 'audit_site: description');
    like($result->{messages}->[0]->{content}->{text}, qr/\AAudit this Dapper site\. Run check and fix every error it reports\./, 'audit_site text');
    like($result->{messages}->[0]->{content}->{text}, qr/summarize what you changed\. \Q$steps\E\z/, 'and the steps');

    my $response = rpc($d, 'prompts/get', { name => 'nope' }, 9);
    is_deeply($response, { jsonrpc => '2.0', id => 9, error => { code => -32602, message => 'There is no prompt called "nope"' } }, 'an unknown prompt');
    $response = rpc($d, 'prompts/get', {});
    is_deeply($response->{error}, { code => -32602, message => 'There is no prompt called ""' }, 'no prompt name');
    $response = rpc($d, 'prompts/get');
    is($response->{error}->{code}, -32602, 'no params');

    is(App::Dapper::MCP::get_prompt($d, undef, {}), undef, 'get_prompt without a name returns nothing');
    is(App::Dapper::MCP::get_prompt($d, 'nope', {}), undef, 'and with an unknown name');
};

subtest 'resources/list' => sub {
    my $resources = rpc($d, 'resources/list')->{result}->{resources};
    is_deeply([ map { $_->{uri} } @$resources ], [qw(dapper://guide dapper://config dapper://schemas)], 'every resource');
    is_deeply([ map { $_->{mimeType} } @$resources ], [qw(text/markdown text/yaml application/json)], 'their types');
    is_deeply([ map { $_->{name} } @$resources ], ['Guide to this site', 'Project file', 'Schemas'], 'their names');
    ok(length $_->{description}, "$_->{uri} has a description") for @$resources;
};

subtest 'resources/read' => sub {
    my $response = rpc($d, 'resources/read', { uri => 'dapper://guide' }, 3);
    is($response->{id}, 3, 'the id');
    my $contents = $response->{result}->{contents};
    is(scalar @$contents, 1, 'one item');
    is($contents->[0]->{uri}, 'dapper://guide', 'its uri');
    is($contents->[0]->{mimeType}, 'text/markdown', 'its type');
    is($contents->[0]->{text}, App::Dapper::Agents::guide(App::Dapper->new()), 'the guide, as in AGENTS.md');
    like($contents->[0]->{text}, qr/\A# Working on Protocol\n/, 'for this site');

    $contents = rpc($d, 'resources/read', { uri => 'dapper://config' })->{result}->{contents};
    is_deeply($contents, [ { uri => 'dapper://config', mimeType => 'text/yaml', text => "---\nname: Protocol\nurl: https://example.com\n" } ], 'the project file, as it is');

    $contents = rpc($d, 'resources/read', { uri => 'dapper://schemas' })->{result}->{contents};
    is($contents->[0]->{mimeType}, 'application/json', 'schemas are JSON');
    my $schemas = JSON->new->decode($contents->[0]->{text});
    is(scalar @$schemas, 1, 'one schema');
    is($schemas->[0]->{applies_to}, '_source/blog', 'where it applies');
    is($schemas->[0]->{file}, '_source/blog/_schema.yml', 'its file');
    is_deeply($schemas->[0]->{required}, ['title'], 'required fields');
    is_deeply($schemas->[0]->{fields}, { title => { type => 'string', max_length => 50 } }, 'field rules');
    ok($schemas->[0]->{additional}, 'other fields allowed');

    my $other = App::Dapper->new(undef, undef, undef, 'missing.yml');
    $contents = App::Dapper::MCP::read_resource($other, 'dapper://config');
    is_deeply($contents, { uri => 'dapper://config', mimeType => 'text/yaml', text => '' }, 'a missing project file reads as empty');

    $response = rpc($d, 'resources/read', { uri => 'dapper://nope' }, 4);
    is_deeply($response, { jsonrpc => '2.0', id => 4, error => { code => -32002, message => 'Resource not found: dapper://nope' } }, 'an unknown resource');
    $response = rpc($d, 'resources/read', {});
    is_deeply($response->{error}, { code => -32002, message => 'Resource not found: ' }, 'no uri');
    is(App::Dapper::MCP::read_resource($d, undef), undef, 'read_resource without a uri returns nothing');
    is(App::Dapper::MCP::read_resource($d, 'file:///etc/passwd'), undef, 'files are not resources');
};

subtest 'schemas resource without schemas' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nHome.\n" });
    my $plain = App::Dapper->new();
    my $contents = rpc($plain, 'resources/read', { uri => 'dapper://schemas' })->{result}->{contents};
    is($contents->[0]->{text}, "[]\n", 'an empty list');
};

subtest 'serve: one line per response' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nHome.\n" });
    my $s = App::Dapper->new();
    my ($lines, $err) = serve_lines($s, join("\n",
        '{"jsonrpc":"2.0","id":1,"method":"ping"}',
        '',
        '   ',
        '{"jsonrpc":"2.0","method":"notifications/initialized"}',
        'this is not json',
        '[1,2,3]',
        '"a string"',
        '{"jsonrpc":"2.0","id":"x","method":"nope"}',
        '{"jsonrpc":"2.0","id":2,"method":"ping"}',
    ) . "\n");
    is(scalar @$lines, 6, 'blank lines and notifications get nothing; everything else a line');
    is($lines->[0], '{"id":1,"jsonrpc":"2.0","result":{}}', 'ping, as canonical JSON');
    is($lines->[1], '{"error":{"code":-32700,"message":"Parse error"},"id":null,"jsonrpc":"2.0"}', 'text that is not JSON: a parse error with a null id');
    is($lines->[2], '{"error":{"code":-32600,"message":"Invalid Request"},"id":null,"jsonrpc":"2.0"}', 'a JSON array is an invalid request');
    is($lines->[3], $lines->[2], 'and so is a JSON string');
    is($lines->[4], '{"error":{"code":-32601,"message":"Method not found: nope"},"id":"x","jsonrpc":"2.0"}', 'an unknown method');
    is($lines->[5], '{"id":2,"jsonrpc":"2.0","result":{}}', 'the server carries on after errors');
    is($err, '', 'nothing on standard error');

    is(JSON->new->decode($lines->[2])->{error}->{code}, -32600, 'an array is an invalid request');
};

subtest 'serve: UTF-8 in and out' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nHome.\n" });
    my $s = App::Dapper->new();
    my $request = $json->encode({ jsonrpc => '2.0', id => 1, method => 'tools/call',
        params => { name => 'write_page', arguments => { source => 'café.md', front_matter => { title => 'Crème brûlée' }, body => 'Délicieux — 美味しい' } } });
    my $read = $json->encode({ jsonrpc => '2.0', id => 2, method => 'tools/call', params => { name => 'read_page', arguments => { source => 'café.md' } } });
    my ($lines, $err, $raw) = serve_lines($s, "$request\n$read\n");
    is(scalar @$lines, 2, 'two responses');
    ok(utf8::decode(my $copy = $raw), 'the output is valid UTF-8');
    my $written = $json->decode($lines->[0]);
    ok(!$written->{result}->{isError}, 'written') or diag explain $written;
    my $page = $json->decode($lines->[1])->{result}->{structuredContent};
    is($page->{front_matter}->{title}, 'Crème brûlée', 'the title survives the round trip');
    is($page->{body}, "Délicieux — 美味しい\n", 'and the body');
    like($raw, qr/Cr\xc3\xa8me/, 'non-ASCII is sent as UTF-8 bytes, not escapes');
};

subtest 'serve: what tools print goes to standard error' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nHome.\n" });
    my $s = App::Dapper->new();
    no warnings 'redefine';
    local *App::Dapper::MCP::site_info = sub { print "noise on standard output\n"; return { quiet => 1 } };
    my ($lines, $err) = serve_lines($s, qq({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"site_info"}}\n));
    is(scalar @$lines, 1, 'only the response is on standard output');
    is($json->decode($lines->[0])->{result}->{structuredContent}->{quiet}, 1, 'and it is the response');
    is($err, "noise on standard output\n", 'the noise went to standard error');
};

subtest 'serve: input without a final newline, and an empty input' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nHome.\n" });
    my $s = App::Dapper->new();
    my ($lines) = serve_lines($s, '{"jsonrpc":"2.0","id":1,"method":"ping"}');
    is_deeply($lines, ['{"id":1,"jsonrpc":"2.0","result":{}}'], 'the last line is answered');
    ($lines) = serve_lines($s, '');
    is_deeply($lines, [], 'nothing in, nothing out');
};

subtest 'dapper mcp as a process' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nHome.\n" });
    my $dir = getcwd();
    my $input = join("\n",
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}',
        '{"jsonrpc":"2.0","method":"notifications/initialized"}',
        '{"jsonrpc":"2.0","id":2,"method":"tools/list"}',
        'garbage',
        '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"build","arguments":{}}}',
        '{"jsonrpc":"2.0","id":4,"method":"resources/read","params":{"uri":"dapper://config"}}',
    ) . "\n";
    spew("$io/requests", $input, ':raw');
    my $other = tempdir(CLEANUP => 1);
    chdir $other;
    my $out = `"$^X" "-I$lib" "$dapper_bin" -C "$dir" mcp < "$io/requests" 2>"$io/stderr"`;
    my $status = $? >> 8;
    chdir $dir;
    is($status, 0, 'exits 0 at the end of the input');
    my @lines = split /\n/, $out;
    is(scalar @lines, 5, 'five responses');
    my @responses = map { $json->decode($_) } @lines;
    is_deeply([ map { $_->{id} } @responses ], [1, 2, undef, 3, 4], 'in order, with their ids');
    is($responses[0]->{result}->{protocolVersion}, '2025-03-26', 'initialize');
    is(scalar @{ $responses[1]->{result}->{tools} }, 9, 'tools/list');
    is($responses[2]->{error}->{code}, -32700, 'the parse error');
    ok($responses[3]->{result}->{structuredContent}->{built}, 'build');
    ok(-f "$dir/_output/index.html", 'built in the -C directory');
    like($responses[4]->{result}->{contents}->[0]->{text}, qr/name: Test Site/, 'the project file from the -C directory');
    is(slurp("$io/stderr"), '', 'a quiet build prints nothing on standard error');
};

subtest 'dapper mcp outside a project' => sub {
    make_site({}, bare => 1);
    my $dir = getcwd();
    spew("$io/requests", qq({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"site_info"}}\n{"jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"dapper://config"}}\n), ':raw');
    my $out = `"$^X" "-I$lib" "$dapper_bin" -C "$dir" mcp < "$io/requests" 2>/dev/null`;
    my @responses = map { $json->decode($_) } split /\n/, $out;
    is(scalar @responses, 2, 'still answers');
    ok($responses[0]->{result}->{isError}, 'tools report the missing project file as an error');
    is($responses[0]->{result}->{structuredContent}->{error}, 'could not find the project file "_config.yml". Run "dapper init" to create a new project.', 'with the message');
    is($responses[1]->{result}->{contents}->[0]->{text}, '', 'the config resource is empty');
};

done_testing();
