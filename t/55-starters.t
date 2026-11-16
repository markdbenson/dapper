use 5.010;
use strict;
use warnings;
use Test::More;

# Every starter template, end to end: dapper init writes it, it builds the
# pages it promises, and dapper check finds nothing wrong with it.

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Init;
use Cwd qw(abs_path);
use File::Find ();
use File::Spec;
use File::Temp qw(tempdir);

my $dapper = abs_path(File::Spec->catfile('bin', 'dapper'));
my $lib = abs_path('lib');
my $io = tempdir(CLEANUP => 1);

sub sh_quote {
    my ($s) = @_;
    $s =~ s/'/'\\''/g;
    return "'$s'";
}

sub run_dapper {
    my @args = @_;
    system(join(' ', map { sh_quote($_) } $^X, "-I$lib", $dapper, @args)
        . ' >' . sh_quote("$io/out") . ' 2>' . sh_quote("$io/err") . ' <' . File::Spec->devnull);
    return ($? >> 8, slurp("$io/out"), slurp("$io/err"));
}

sub init_template {
    my ($template) = @_;
    make_site({}, bare => 1);
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{template} = $template;
    $d->init();
}

sub output_files {
    my @files;
    File::Find::find({ no_chdir => 1, wanted => sub { push @files, substr($_, length('_output/')) if -f $_ } }, '_output');
    return [ sort grep { !/^(?:AGENTS|CLAUDE)\.md$/ } @files ];
}

my %OUTPUT = (
    default   => [qw(index.html index.md llms-full.txt llms.txt)],
    blog      => [qw(about.html about.md blog/2026/01/welcome-to-your-new-blog/index.html blog/2026/01/welcome-to-your-new-blog/index.md
                     blog/2026/01/writing-posts/index.html blog/2026/01/writing-posts/index.md blog/index.html css/site.css feed.xml
                     index.html llms-full.txt llms.txt sitemap.xml tags/dapper/index.html tags/writing/index.html)],
    portfolio => [qw(about.html about.md contact.html css/site.css images/project-1.svg images/project-2.svg index.html llms-full.txt
                     llms.txt projects/2025/09/night-market-posters/index.html projects/2025/09/night-market-posters/index.md
                     projects/2026/03/riverside-books/index.html projects/2026/03/riverside-books/index.md sitemap.xml)],
    business  => [qw(about.html about.md contact.html css/site.css feed.xml images/storefront.svg index.html llms-full.txt llms.txt
                     news.html news/2026/02/now-open-on-sundays/index.html news/2026/02/now-open-on-sundays/index.md sitemap.xml)],
    docs      => [qw(css/site.css getting-started.html getting-started.md guide/configuration.html guide/configuration.md
                     guide/writing-pages.html guide/writing-pages.md index.html index.md llms-full.txt llms.txt sitemap.xml)],
);
my %PAGES = (default => 1, blog => 7, portfolio => 5, business => 5, docs => 4);

is_deeply([ sort keys %OUTPUT ], [ App::Dapper::Init::templates() ], 'every template is covered here');

for my $template (App::Dapper::Init::templates()) {
    subtest "the $template starter" => sub {
        init_template($template);

        my ($files) = App::Dapper::Init::template_files($template);
        for my $file (sort keys %$files) {
            is(slurp($file), $files->{$file}, "$file is written as in the template");
        }
        is(slurp('.gitignore'), "_output/\n.dapper/\n", '.gitignore');
        ok(-f 'AGENTS.md', 'AGENTS.md');
        is(slurp('CLAUDE.md'), "This site is built with Dapper. Read AGENTS.md before making changes.\n\n\@AGENTS.md\n", 'CLAUDE.md');

        my $report = App::Dapper->new()->check();
        is_deeply($report->{errors}, [], 'check finds no errors') or diag explain $report->{errors};
        ok($report->{ok}, 'check is ok');
        is($report->{pages}, $PAGES{$template}, "$PAGES{$template} pages checked");
        is_deeply($report->{held}, [], 'nothing held back');
        if ($template eq 'default') {
            is_deeply([ map { $_->{type} } @{$report->{warnings}} ], ['setting'], 'default: only the warning that url is not set');
        }
        else {
            is_deeply($report->{warnings}, [], 'no warnings');
        }

        my $built = quiet_build();
        is_deeply([ @{$built->{problems}} ], [], 'builds without problems');
        is_deeply(output_files(), $OUTPUT{$template}, 'writes exactly the pages it promises');

        my $agents = slurp('AGENTS.md');
        my ($name) = $files->{'_config.yml'} =~ /^name\s*:\s*(.+)$/m;
        like($agents, qr/^# Working on \Q$name\E$/m, 'AGENTS.md names the site');
        my (undef, $notes) = App::Dapper::Init::template_files($template);
        if (defined $notes) {
            like($agents, qr/<!-- dapper:end -->\n\n\Q$notes\E\z/, 'the template notes follow the generated part');
        }
        else {
            like($agents, qr/<!-- dapper:end -->\n\z/, 'nothing follows the generated part');
        }
        for my $schema (grep { /_schema\.yml$/ } keys %$files) {
            (my $dir = $schema) =~ s{/_schema\.yml$}{};
            like($agents, qr/^### `\Q$dir\E\/`$/m, "AGENTS.md explains $schema");
        }
    };
}

subtest 'what the starters build' => sub {
    init_template('blog');
    quiet_build();
    my $home = slurp('_output/index.html');
    like($home, qr{<title>Home - My Blog</title>}, 'blog: the home page title');
    like($home, qr{<a href="/blog/2026/01/writing-posts/">Writing Posts</a>.*<a href="/blog/2026/01/welcome-to-your-new-blog/">Welcome to Your New Blog</a>}s, 'blog: the home page lists posts, newest first');
    like($home, qr{<a href="/about\.html">About</a>}, 'blog: the menu');
    unlike($home, qr{Older posts}, 'blog: one page of posts, so no older posts link');
    my $feed = slurp('_output/feed.xml');
    is(() = $feed =~ /<entry>/g, 2, 'blog: two entries in the feed');
    like(slurp('_output/sitemap.xml'), qr{<loc>https://example\.com/tags/writing/</loc>}, 'blog: the sitemap has absolute addresses');
    like(slurp('_output/tags/dapper/index.html'), qr{<h1>dapper</h1>}, 'blog: a page per tag');
    like(slurp('_output/blog/2026/01/welcome-to-your-new-blog/index.html'), qr{<a href="/tags/dapper/">#dapper</a>}, 'blog: posts link to their tags');
    like(slurp('_output/blog/2026/01/welcome-to-your-new-blog/index.html'), qr{01 January 2026}, 'blog: posts show their date');

    init_template('portfolio');
    quiet_build();
    $home = slurp('_output/index.html');
    like($home, qr{href="/projects/2026/03/riverside-books/".*href="/projects/2025/09/night-market-posters/"}s, 'portfolio: projects, newest first');
    like($home, qr{<img src="/images/project-1\.svg" alt="The Riverside Books logo in blue on a cream background" loading="lazy">}, 'portfolio: cards with images and alt text');

    init_template('business');
    quiet_build();
    $home = slurp('_output/index.html');
    like($home, qr{7am to 3pm}, 'business: opening hours from the data file');
    like($home, qr{PostalAddress}, 'business: structured data');
    like(slurp('_output/news.html'), qr{Now Open on Sundays}, 'business: the news page lists the news');

    init_template('docs');
    quiet_build();
    my $page = slurp('_output/getting-started.html');
    like($page, qr{<a href="/getting-started\.html" aria-current="page">Getting Started</a>}, 'docs: the sidebar marks the current page');
    like($page, qr{<a class="prev" href="/">&larr; Overview</a>}, 'docs: a previous link');
    like($page, qr{<a class="next" href="/guide/configuration\.html">Configuration &rarr;</a>}, 'docs: a next link');
    unlike(slurp('_output/index.html'), qr{class="prev"}, 'docs: no previous link on the first page');
    unlike(slurp('_output/guide/writing-pages.html'), qr{class="next"}, 'docs: no next link on the last page');
};

subtest 'every starter through the dapper command' => sub {
    for my $template (App::Dapper::Init::templates()) {
        make_site({}, bare => 1);
        my ($status, $out, $err) = run_dapper('-q', '-t', $template, 'init');
        is($status, 0, "$template: init exits 0");
        is($err, '', "$template: init prints nothing on standard error");
        ($status, $out, $err) = run_dapper('-q', 'build');
        is($status, 0, "$template: build exits 0");
        is($err, '', "$template: build prints nothing on standard error");
        ($status, $out) = run_dapper('check');
        is($status, 0, "$template: check exits 0");
        like($out, qr/^Checked $PAGES{$template} pages?: 0 errors, ${\ ($template eq 'default' ? 1 : 0)} warnings?\.$/m, "$template: check summary");
    }
};

subtest 'starters do not publish the notes for agents' => sub {
    init_template('blog');
    quiet_build();
    ok(!-e '_output/AGENTS.md', 'AGENTS.md is not published');
    ok(!-e '_output/CLAUDE.md', 'CLAUDE.md is not published');
};

done_testing();
