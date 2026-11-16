use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;
binmode(Test::More->builder->$_, q(:encoding(UTF-8))) for qw(output failure_output todo_output);

# A whole session with dapper mcp, the way an AI assistant would use it on
# a new blog: learn the site, write a post (fixing what the schema reports),
# move it, check and build, all over standard input and output.

use lib 't/lib';
use DapperTest;
use App::Dapper;
use Cwd qw(abs_path getcwd);
use File::Spec;
use File::Temp qw(tempdir);
use JSON ();

my $dapper = abs_path(File::Spec->catfile('bin', 'dapper'));
my $lib = abs_path('lib');
my $io = tempdir(CLEANUP => 1);
my $json = JSON->new->utf8->canonical;

sub session {
    my ($dir, @requests) = @_;
    my $id = 0;
    my $input = join('', map { $json->encode({ jsonrpc => '2.0', id => ++$id, %$_ }) . "\n" } @requests);
    spew("$io/in", $input, ':raw');
    my $out = `"$^X" "-I$lib" "$dapper" -C "$dir" mcp < "$io/in" 2>"$io/err"`;
    my @responses = map { $json->decode($_) } split /\n/, $out;
    return @responses;
}

sub tool { my ($name, $args) = @_; return { method => 'tools/call', params => { name => $name, arguments => $args || {} } } }

make_site({}, bare => 1);
my $dir = getcwd();
{
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{template} = 'blog';
    $d->init();
}

my @r = session($dir,
    { method => 'initialize', params => { protocolVersion => '2025-06-18' } },
    tool('site_info'),
    { method => 'resources/read', params => { uri => 'dapper://guide' } },
    { method => 'prompts/get', params => { name => 'write_post', arguments => { topic => 'Sourdough', category => 'blog' } } },
    tool('write_page', { source => 'blog/sourdough.md', front_matter => { title => 'Sourdough', layout => 'post' }, body => 'Flour, water, salt.' }),
    tool('write_page', { source => 'blog/sourdough.md', front_matter => { title => 'Sourdough', layout => 'post', date => '2026-02-01T09:00:00',
        categories => ['blog'], tags => ['bread'], description => 'How I bake a loaf of sourdough every week.' }, body => 'Flour, water, salt.' }),
    tool('list_pages', { category => 'blog' }),
    tool('rename_page', { source => 'about.md', new_source => 'about-me.md' }),
    tool('check'),
    tool('build'),
    tool('read_page', { source => 'blog/sourdough.md' }),
);

is(scalar @r, 11, 'one response per request');
is_deeply([ map { $_->{id} } @r ], [ 1 .. 11 ], 'in order');
ok(!grep({ exists $_->{error} } @r), 'no protocol errors');

my $info = $r[1]->{result}->{structuredContent};
is($info->{name}, 'My Blog', 'site_info names the blog');
is_deeply($info->{schemas}->[0]->{required}, [qw(title date categories)], 'and its schema');
is_deeply($info->{layouts}, [qw(index list post)], 'and its layouts');
is_deeply($info->{tags}, { dapper => 2, writing => 1 }, 'and the tags in use');

like($r[2]->{result}->{contents}->[0]->{text}, qr/^### `_source\/blog\/`$/m, 'the guide explains the blog schema');
like($r[3]->{result}->{messages}->[0]->{content}->{text}, qr/\AWrite a new post in the "blog" category about:\n\nSourdough\n/, 'the prompt');

my $refused = $r[4]->{result};
ok($refused->{isError}, 'a post without a date and category is refused');
is_deeply($refused->{structuredContent}->{problems}, ['"date" is required', '"categories" is required'], 'with what is missing');

ok(!$r[5]->{result}->{isError}, 'the fixed post is written');
is_deeply([ map { $_->{title} } @{ $r[6]->{result}->{structuredContent}->{pages} } ], ['Sourdough', 'Writing Posts', 'Welcome to Your New Blog'], 'and listed first in the blog');

is($r[7]->{result}->{structuredContent}->{redirect}, '/about.html -> /about-me.html (in _data/redirects.yml)', 'moving the about page adds a redirect');

my $report = $r[8]->{result}->{structuredContent};
ok(!$r[8]->{result}->{isError}, 'check runs');
ok($report->{ok}, 'and finds nothing wrong: the menu link to the old address is covered by the redirect');
is_deeply($report->{errors}, [], 'no errors');
is_deeply($report->{warnings}, [], 'no warnings');
is($report->{pages}, 9, 'nine pages, with the new post');

ok($r[9]->{result}->{structuredContent}->{built}, 'built');
ok(-f "$dir/_output/blog/2026/02/sourdough/index.html", 'the post is published');
like(slurp("$dir/_output/blog/2026/02/sourdough/index.html"), qr/Flour, water, salt\./, 'with its text');
ok(-f "$dir/_output/about-me.html", 'the moved page is published');
ok(-f "$dir/_output/about.html", 'and its old address redirects');
like(slurp("$dir/_output/about.html"), qr{/about-me\.html}, 'to the new one');
like(slurp("$dir/_output/feed.xml"), qr/Sourdough/, 'the post is in the feed');
like(slurp("$dir/_output/tags/bread/index.html"), qr/Sourdough/, 'and on its tag page');

is_deeply($r[10]->{result}->{structuredContent}->{front_matter}->{tags}, ['bread'], 'the post reads back');
is(slurp("$io/err"), '', 'nothing on standard error during the session');

done_testing();
