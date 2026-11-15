use 5.010;
use strict;
use warnings;
use Test::More;

# The dapper command: every command that finishes on its own, and every
# option, run as a separate process against throwaway projects.

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Init;
use Cwd qw(abs_path getcwd);
use File::Spec;
use File::Temp qw(tempdir);
use JSON ();

my $dapper = abs_path(File::Spec->catfile('bin', 'dapper'));
my $lib = abs_path('lib');
my $io = tempdir(CLEANUP => 1);

sub sh_quote {
    my ($s) = @_;
    $s =~ s/'/'\\''/g;
    return "'$s'";
}

# dapper(@args) or dapper({ stdin => ... }, @args): run bin/dapper and
# return its exit status, standard output and standard error
sub dapper {
    my @args = @_;
    my %o = ref $args[0] eq 'HASH' ? %{ shift @args } : ();
    my $cmd = join(' ', map { sh_quote($_) } $^X, "-I$lib", $dapper, @args)
        . ' >' . sh_quote("$io/out") . ' 2>' . sh_quote("$io/err");
    if (defined $o{stdin}) {
        spew("$io/in", $o{stdin});
        $cmd .= ' <' . sh_quote("$io/in");
    }
    else {
        $cmd .= ' <' . File::Spec->devnull;
    }
    system($cmd);
    my $status = $? >> 8;
    my ($out, $err) = (slurp("$io/out"), slurp("$io/err"));
    $out = '' unless defined $out;
    $err = '' unless defined $err;
    return ($status, $out, $err);
}

my $templates_text = join('', map { sprintf("%-10s %s\n", $_, App::Dapper::Init::description($_)) } App::Dapper::Init::templates());

subtest '-v and --version' => sub {
    for my $flag ('-v', '--version') {
        my ($status, $out, $err) = dapper($flag);
        is($status, 0, "$flag exits 0");
        is($out, "Dapper version $App::Dapper::VERSION\n", "$flag prints exactly the version");
        is($err, '', "$flag prints nothing on standard error");
    }

    my ($status, $out) = dapper('-v', 'build');
    is($status, 0, '-v wins over a command');
    is($out, "Dapper version $App::Dapper::VERSION\n", 'and nothing is built');

    ($status, $out) = dapper('build', '-v');
    is($out, "Dapper version $App::Dapper::VERSION\n", 'options may follow the command');
};

subtest 'help' => sub {
    for my $args (['-h'], ['--help'], ['help'], []) {
        my $name = @$args ? $args->[0] : 'no command';
        my ($status, $out, $err) = dapper(@$args);
        is($status, 0, "$name exits 0");
        like($out, qr/\AUsage:\n\s+dapper \[options\] <command>\n/, "$name starts with the usage line");
        like($out, qr/^Options:$/m, "$name lists the options");
        like($out, qr/^    -C, --directory=directory$/m, "$name describes -C");
        like($out, qr/^    --dry-run, --force, --no-build$/m, "$name describes the deploy options");
        like($out, qr/\$ dapper import jekyll \.\.\/old-site --dry-run/, "$name shows the examples");
        unlike($out, qr/^AUTHOR/m, "$name leaves out the author section");
        is($err, '', "$name prints nothing on standard error");
    }

    my ($status, $out) = dapper('-h', '-v');
    is($status, 0, '-h with -v exits 0');
    like($out, qr/\AUsage:/, '-h wins over -v');

    ($status, $out) = dapper('help', 'build');
    like($out, qr/\AUsage:/, 'help ignores what follows it');
};

subtest 'templates' => sub {
    my ($status, $out, $err) = dapper('templates');
    is($status, 0, 'exits 0');
    is($out, $templates_text, 'one line per template, name padded to 10 columns');
    my @lines = split /\n/, $out;
    is(scalar @lines, 5, 'five templates');
    like($lines[0], qr/^blog       A blog: /, 'blog first');
    like($lines[1], qr/^business   A small business/, 'then business');
    like($lines[2], qr/^default    The smallest project/, 'then default');
    like($lines[3], qr/^docs       Documentation/, 'then docs');
    like($lines[4], qr/^portfolio  A portfolio/, 'then portfolio');
    is($err, '', 'nothing on standard error');

    make_site({}, bare => 1);
    ($status, $out) = dapper('templates');
    is($status, 0, 'works outside a project');
};

subtest 'init' => sub {
    make_site({}, bare => 1);
    my ($status, $out, $err) = dapper('init');
    is($status, 0, 'exits 0');
    is($out, join('', map { "$_\n" }
        'Creating _config.yml', 'Creating _layout/index.html', 'Creating _source/index.md',
        'Creating .gitignore', 'Creating AGENTS.md', 'Creating CLAUDE.md', 'Project initialized.'),
        'reports each file it creates, in order');
    is($err, '', 'nothing on standard error');
    ok(-f $_, "$_ exists") for qw(_config.yml _layout/index.html _source/index.md .gitignore AGENTS.md CLAUDE.md);
    is(slurp('.gitignore'), "_output/\n.dapper/\n", '.gitignore ignores the output and .dapper');
    like(slurp('_config.yml'), qr/^name : My Site$/m, 'the default project file');
    is(slurp('_source/index.md'), "---\nlayout: index\ntitle: Welcome\n---\n\nHello world.\n\n", 'the default page');

    make_site({}, bare => 1);
    ($status, $out, $err) = dapper('-q', 'init');
    is($status, 0, '-q init exits 0');
    is($out, '', '-q init prints nothing');
    ok(-f '_config.yml', '-q init still writes the project');

    make_site({}, bare => 1);
    ($status, $out) = dapper('--quiet', 'init');
    is($out, '', '--quiet works too');
};

subtest 'init --template' => sub {
    for my $args (['-t', 'blog'], ['--template', 'blog'], ['--template=blog'], ['-tblog']) {
        make_site({}, bare => 1);
        my ($status, $out) = dapper('-q', @$args, 'init');
        is($status, 0, "@$args exits 0");
        ok(-f '_source/blog/_schema.yml', "@$args writes the blog");
    }

    for my $template (App::Dapper::Init::templates()) {
        make_site({}, bare => 1);
        my ($status, $out) = dapper('-t', $template, 'init');
        is($status, 0, "$template exits 0");
        like($out, qr/^Creating _config\.yml$/m, "$template reports the project file");
        like($out, qr/Project initialized\.\n\z/, "$template finishes with Project initialized.");
        my ($files) = App::Dapper::Init::template_files($template);
        my @missing = grep { !-f $_ } keys %$files;
        is_deeply(\@missing, [], "$template writes every file of the template");
    }

    make_site({}, bare => 1);
    my ($status, $out, $err) = dapper('-t', 'nope', 'init');
    is($status, 1, 'an unknown template exits 1');
    is($err, "error: there is no template called \"nope\"; use one of: blog, business, default, docs, portfolio, a directory, or a git URL\n", 'and says which there are');
    is($out, '', 'without printing anything else');
    ok(!-e '_config.yml', 'and writes nothing');
};

subtest 'init with other directories and project file' => sub {
    make_site({}, bare => 1);
    my ($status, $out) = dapper('-s', 'src', '-l', 'lay', '-c', 'site.yml', '-o', 'public', 'init');
    is($status, 0, 'exits 0');
    is($out, join('', map { "$_\n" }
        'Creating lay/index.html', 'Creating site.yml', 'Creating src/index.md',
        'Creating .gitignore', 'Creating AGENTS.md', 'Creating CLAUDE.md', 'Project initialized.'),
        'the template is mapped onto the directories given');
    ok(!-e '_config.yml' && !-e '_source' && !-e '_layout', 'the default names are not used');
    is(slurp('.gitignore'), "public/\n.dapper/\n", '.gitignore names the output directory given');
    my $agents = slurp('AGENTS.md');
    like($agents, qr/- `src\/`: the pages/, 'AGENTS.md names the source directory');
    like($agents, qr/- `lay\/`: the layouts/, 'and the layout directory');
    like($agents, qr/- `site\.yml`: the site's settings/, 'and the project file');
    like($agents, qr/HTML in `public\/`/, 'and the output directory');

    ($status, $out) = dapper('-q', '--source=src', '--layout=lay', '--config=site.yml', '--output=public', 'build');
    is($status, 0, 'builds with the same options');
    ok(-f 'public/index.html', 'into the output directory given');
    like(slurp('public/index.html'), qr/<title>Welcome<\/title>/, 'from the source and layout given');
};

subtest '-C runs in another directory' => sub {
    my $site = tempdir(CLEANUP => 1);
    make_site({}, bare => 1);
    my $here = getcwd();
    my ($status, $out) = dapper('-C', $site, '-q', 'init');
    is($status, 0, 'init exits 0');
    ok(-f "$site/_config.yml", 'the project is written there');
    ok(!-e "$here/_config.yml", 'and not here');

    ($status, $out) = dapper('--directory', $site, '-q', 'build');
    is($status, 0, 'build exits 0');
    ok(-f "$site/_output/index.html", 'built there');

    ($status, $out) = dapper("--directory=$site", 'check');
    is($status, 0, 'check exits 0');
    like($out, qr/Checked 1 page: 0 errors/, 'checked there');

    my ($s2, $o2, $e2) = dapper('-C', "$site/missing", 'build');
    is($s2, 1, 'a missing directory exits 1');
    like($e2, qr/\Aerror: could not change to "\Q$site\E\/missing": \S/, 'and says so');
    is($o2, '', 'with nothing on standard output');
};

subtest 'build' => sub {
    make_site({
        '_source/index.md'  => "---\ntitle: Home\n---\nHello\n",
        '_source/draft.md'  => "---\ntitle: Draft\ndraft: true\n---\nDraft\n",
        '_source/later.md'  => "---\ntitle: Later\ndate: 2999-01-01\n---\nLater\n",
        'css/site.css'      => "body {}\n",
    });
    my ($status, $out, $err) = dapper('build');
    is($status, 0, 'exits 0');
    like($out, qr/^Processing _source\/index\.md$/m, 'reports what it processes');
    like($out, qr/^Wrote _output\/index\.html$/m, 'reports what it writes');
    like($out, qr/^Copied css$/m, 'reports what it copies');
    like($out, qr/Project built\.\n\z/, 'finishes with Project built.');
    like($out, qr/^Held back _source\/draft\.md \(draft\)$/m, 'says the draft is held back');
    like($out, qr/^Held back _source\/later\.md \(scheduled for 2999-01-01T00:00:00\)$/m, 'and the future page');
    unlike($out, qr/^Wrote _output\/(?:draft|later)/m, 'and does not write them');
    is($err, '', 'nothing on standard error');
    ok(-f '_output/index.html', 'the page is written');
    ok(!-e '_output/draft.html', 'the draft is not');
    ok(!-e '_output/later.html', 'the future page is not');

    ($status, $out) = dapper('-q', 'build', '--drafts');
    is($status, 0, '--drafts exits 0');
    is($out, '', '-q prints nothing');
    ok(-f '_output/draft.html', '--drafts includes drafts');
    ok(-f '_output/later.html', 'and future pages');

    ($status, $out) = dapper('-q', 'build');
    ok(!-e '_output/draft.html', 'a build without --drafts removes them again');

    ($status, $out) = dapper('-qo', 'bundled', 'build');
    is($status, 0, 'bundled short options exit 0');
    is($out, '', 'bundled -q applies');
    ok(-f 'bundled/index.html', 'bundled -o applies');

    ($status, $out) = dapper('-q', '-p', '9000', 'build');
    is($status, 0, '-p is accepted (and ignored) by build');
    ($status, $out) = dapper('-q', '--port=9001', 'build');
    is($status, 0, '--port= is accepted too');

    ($status, $out) = dapper('-q', 'build', 'extra', 'words');
    is($status, 0, 'extra arguments after build are ignored');
};

subtest 'build with a source and layout from the command line' => sub {
    make_site({
        '_config.yml'          => "---\nname: Options\nsource: pages\nlayout: templates\noutput: www\n",
        'pages/index.md'       => "---\ntitle: From pages\n---\nx\n",
        'templates/index.html' => "<h1>[% page.title %]</h1>",
        'other/index.md'       => "---\ntitle: From other\n---\nx\n",
        'alt/index.html'       => "<h2>[% page.title %]</h2>",
    }, bare => 1);
    my ($status) = dapper('-q', 'build');
    is($status, 0, 'builds with directories from the project file');
    is(slurp('www/index.html'), '<h1>From pages</h1>', 'which are used');

    ($status) = dapper('-q', '-s', 'other', '-l', 'alt', '-o', 'out2', 'build');
    is($status, 0, 'builds with directories from the command line');
    is(slurp('out2/index.html'), '<h2>From other</h2>', 'which win over the project file');

    spew('second.yml', "---\nname: Second\nsource: other\nlayout: alt\n");
    ($status) = dapper('-q', '-c', 'second.yml', 'build');
    is($status, 0, '-c chooses another project file');
    is(slurp('_output/index.html'), '<h2>From other</h2>', 'whose settings are used');
};

subtest 'check' => sub {
    make_site({
        '_config.yml'      => "---\nname: Check\nurl: https://example.com\n",
        '_source/index.md' => "---\ntitle: Home\ndescription: The home page of the site.\n---\nHello\n",
    });
    my ($status, $out, $err) = dapper('check');
    is($status, 0, 'a clean site exits 0');
    is($out, "Checked 1 page: 0 errors, 0 warnings.\n", 'exact summary');
    is($err, '', 'nothing on standard error');
    ok(!-e '_output', 'check does not build the output directory');

    ($status, $out) = dapper('check', '--json');
    is($status, 0, '--json exits 0');
    my $report = JSON->new->decode($out);
    is_deeply([ sort keys %$report ], [qw(errors held ok pages warnings)], 'the report has errors, held, ok, pages and warnings');
    ok($report->{ok}, 'ok is true');
    is($report->{pages}, 1, 'one page');
    is_deeply($report->{errors}, [], 'no errors');
    is_deeply($report->{held}, [], 'nothing held');
    like($out, qr/\A\{\n   "errors" : \[\],\n   "held" : \[\],\n   "ok" : true,/, 'pretty, canonical JSON');

    spew('_source/draft.md', "---\ntitle: Draft\ndescription: A draft page of the site.\ndraft: true\n---\nx\n");
    spew('_source/later.md', "---\ntitle: Later\ndescription: A page dated in the future.\ndate: 2999-01-01\n---\nx\n");
    ($status, $out) = dapper('check');
    is($status, 0, 'held pages do not fail the check');
    is($out, "Not published: 1 draft, 1 scheduled (use --drafts to include them).\nChecked 1 page: 0 errors, 0 warnings.\n", 'says what is held');

    ($status, $out) = dapper('check', '--json');
    $report = JSON->new->decode($out);
    is_deeply($report->{held}, [ { file => '_source/draft.md', reason => 'draft' }, { file => '_source/later.md', reason => 'scheduled' } ], 'held in the JSON');

    ($status, $out) = dapper('check', '--drafts');
    is($status, 0, '--drafts exits 0');
    is($out, "Checked 3 pages: 0 errors, 0 warnings.\n", '--drafts checks them too');

    spew('_source/broken.md', "---\ntitle: Broken\ndescription: A page with a broken link.\n---\n[x](/nowhere/)\n");
    ($status, $out, $err) = dapper('check');
    is($status, 1, 'errors exit 1');
    like($out, qr/^error: _source\/broken\.md: links to \/nowhere\/, which is not in the site$/m, 'the error is reported');
    like($out, qr/Checked 2 pages: 1 error, 0 warnings\.\n\z/, 'singular error in the summary');
    is($err, '', 'on standard output, not standard error');

    ($status, $out) = dapper('check', '--json');
    is($status, 1, '--json with errors exits 1');
    $report = JSON->new->decode($out);
    ok(!$report->{ok}, 'ok is false');
    is(scalar @{$report->{errors}}, 1, 'one error');
    is($report->{errors}->[0]->{file}, '_source/broken.md', 'with the file');
    is($report->{errors}->[0]->{type}, 'link', 'and the type');

    ($status, $out) = dapper('-q', 'check');
    is($status, 1, '-q check still exits 1');
    like($out, qr/^error: /m, '-q check still prints the report');
};

subtest 'agents' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });
    my ($status, $out, $err) = dapper('agents');
    is($status, 0, 'exits 0');
    is($out, "Wrote AGENTS.md\nWrote CLAUDE.md\n", 'reports both files');
    is($err, '', 'nothing on standard error');
    like(slurp('AGENTS.md'), qr/# Working on Test Site/, 'AGENTS.md written');

    ($status, $out) = dapper('agents');
    is($out, "Wrote AGENTS.md\n", 'CLAUDE.md is only written once');

    ($status, $out) = dapper('-q', 'agents');
    is($status, 0, '-q exits 0');
    is($out, '', '-q prints nothing');

    unlink '_config.yml';
    ($status, $out, $err) = dapper('agents');
    is($status, 0, 'works without a project file');
    like(slurp('AGENTS.md'), qr/# Working on this site/, 'naming the site generically');
};

subtest 'import' => sub {
    my $jekyll = tempdir(CLEANUP => 1);
    spew("$jekyll/_posts/2019-05-01-old-post.md", "---\ntitle: Old Post\n---\nOld body.\n");
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });

    my ($status, $out, $err) = dapper('import', 'jekyll', $jekyll, '--dry-run', '--to', 'news');
    is($status, 0, '--dry-run exits 0');
    is($out, "Would import 1 post and 0 pages into _source.\n", 'says what it would do');
    is($err, '', 'nothing on standard error');
    ok(!-e '_source/news', 'and writes nothing');

    ($status, $out) = dapper('import', 'jekyll', $jekyll, '--to=/news/');
    is($status, 0, 'exits 0');
    is($out, "Imported 1 post and 0 pages into _source.\nRun \"dapper check\" to find links that need fixing.\n", 'reports what it did');
    ok(-f '_source/news/old-post.md', '--to chooses the directory (slashes trimmed)');

    ($status, $out) = dapper('-q', 'import', 'JEKYLL', $jekyll);
    is($status, 0, 'the kind is not case sensitive');
    is($out, '', '-q prints nothing');
    ok(-f '_source/blog/old-post.md', 'posts go in blog by default');
};

subtest 'mcp' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });
    my $input = join('', map { JSON->new->encode($_) . "\n" }
        { jsonrpc => '2.0', id => 1, method => 'initialize', params => {} },
        { jsonrpc => '2.0', id => 2, method => 'tools/call', params => { name => 'site_info', arguments => {} } });
    my ($status, $out, $err) = dapper({ stdin => $input }, 'mcp');
    is($status, 0, 'exits 0 when standard input closes');
    my @lines = split /\n/, $out;
    is(scalar @lines, 2, 'one response per request');
    is(JSON->new->decode($lines[1])->{result}->{structuredContent}->{name}, 'Test Site', 'answers from the project in the current directory');

    ($status, $out) = dapper({ stdin => '' }, 'mcp');
    is($status, 0, 'no input: exits 0');
    is($out, '', 'and prints nothing');
};

done_testing();
