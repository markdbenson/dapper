use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Init;
use File::Temp ();
use File::Spec;

make_site({}, bare => 1);

my $d = App::Dapper->new();
$d->{quiet} = 1;
{
    local *STDOUT;
    open(STDOUT, '>', \my $ignored);
    $d->init();
}

ok(-f "_config.yml", "init creates _config.yml");
ok(-f "_source/index.md", "init creates _source/index.md");
ok(-f "_layout/index.html", "init creates _layout/index.html");
like(slurp("_layout/index.html"), qr/<meta charset="utf-8">/, "starter layout declares UTF-8");

my $before = slurp("_config.yml");
eval {
    local *STDOUT;
    open(STDOUT, '>', \my $ignored);
    App::Dapper->new()->init();
};
like($@, qr/already exist/, "init refuses to overwrite an existing project");
is(slurp("_config.yml"), $before, "existing config file is untouched");

quiet_build();
my $index = slurp("_output/index.html");
like($index, qr{<title>Welcome</title>}, "built page has the title");
like($index, qr{<p>Hello world.</p>}, "built page has the rendered markdown");
ok(-f '.gitignore', 'a .gitignore is added');

subtest 'the blog template' => sub {
    make_site({}, bare => 1);
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{template} = 'blog';
    $d->init();
    ok(-f '_source/blog/_schema.yml', 'has a schema');
    ok(-f '_data/menu.yml', 'has a data file');

    my $report = App::Dapper->new()->check();
    ok($report->{ok}, 'checks clean') or diag explain $report;
    is_deeply($report->{warnings}, [], 'without warnings');

    my $built = quiet_build();
    ok(-f "_output/$_", "writes $_") for qw(index.html about.html feed.xml sitemap.xml llms.txt blog/index.html tags/dapper/index.html);
    like(slurp('_output/blog/2026/01/welcome-to-your-new-blog/index.html'), qr{<pre><code class="language-perl">}, 'highlightable code');
    like(slurp('_output/index.html'), qr{<script type="application/ld\+json">}, 'SEO tags');
};

subtest 'an unknown template' => sub {
    make_site({}, bare => 1);
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{template} = 'nope';
    eval { $d->init() };
    like($@, qr/there is no template called "nope"; use one of: blog, business, default, docs, portfolio, a directory, or a git URL/, 'lists the templates');
};


subtest 'every built-in template checks clean' => sub {
    for my $template (App::Dapper::Init::templates()) {
        make_site({}, bare => 1);
        my $d = App::Dapper->new();
        $d->{quiet} = 1;
        $d->{template} = $template;
        $d->init();
        my $report = App::Dapper->new()->check();
        ok($report->{ok}, "$template: no errors") or diag explain $report->{errors};
        is_deeply($report->{warnings}, [], "$template: no warnings") if $template ne 'default';
        ok(-f 'AGENTS.md', "$template: AGENTS.md written");
    }
};

subtest 'a template from a directory or a git repository' => sub {
    my $theme = File::Temp::tempdir(CLEANUP => 1);
    spew("$theme/_config.yml", "---\nname: From a directory\n");
    spew("$theme/_layout/index.html", "[% page.content %]");
    spew("$theme/_source/index.md", "---\ntitle: Home\n---\nHello from a theme.\n");
    spew("$theme/images/dot.png", "\x89PNG\r\n\x1a\n" . join('', map { chr } 0 .. 255), ':raw');
    spew("$theme/AGENTS.md", "# Theme notes\n\nKeep it short.\n");
    spew("$theme/.git/HEAD", "ref: refs/heads/main\n");
    spew("$theme/_output/stale.html", "old\n");

    make_site({}, bare => 1);
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{template} = $theme;
    $d->init();
    like(slurp('_source/index.md'), qr/Hello from a theme/, 'files copied');
    is(slurp('images/dot.png', ':raw'), "\x89PNG\r\n\x1a\n" . join('', map { chr } 0 .. 255), 'binary files copied byte for byte');
    ok(!-e '.git' && !-e '_output/stale.html', '.git and the output directory are not copied');
    like(slurp('AGENTS.md'), qr/\A# Theme notes\n\nKeep it short\.\n.*<!-- dapper:begin/s, "the theme's AGENTS.md is kept, with the guide added");
    ok(App::Dapper->new()->check()->{ok}, 'checks clean');

    SKIP: {
        skip 'git is not installed', 2 unless grep { -x "$_/git" } File::Spec->path();
        my $repo = File::Temp::tempdir(CLEANUP => 1) . '/theme.git';
        system('git', 'init', '-q', $repo) == 0 or skip 'git init failed', 2;
        spew("$repo/_config.yml", "---\nname: From git\n");
        spew("$repo/_layout/index.html", "[% page.content %]");
        spew("$repo/_source/index.md", "---\ntitle: Home\n---\nHello from git.\n");
        system("cd '$repo' && git add -A && git -c user.name=t -c user.email=t\@example.com commit -q -m theme") == 0 or skip 'git commit failed', 2;

        make_site({}, bare => 1);
        my $g = App::Dapper->new();
        $g->{quiet} = 1;
        $g->{template} = "file://$repo";
        $g->init();
        like(slurp('_source/index.md'), qr/Hello from git/, 'cloned and copied');
        ok(!-e '.git', 'without its .git directory');
    }
};

subtest 'templates are listed with descriptions' => sub {
    is_deeply([ App::Dapper::Init::templates() ], [qw(blog business default docs portfolio)], 'names');
    like(App::Dapper::Init::description('business'), qr/opening hours/, 'description');
    eval { App::Dapper::Init::template_files('no-such-template') };
    like($@, qr/there is no template called "no-such-template"/, 'unknown template');
};

done_testing();
