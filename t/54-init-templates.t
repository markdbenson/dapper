use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;
binmode(Test::More->builder->$_, q(:encoding(UTF-8))) for qw(output failure_output todo_output);

# App::Dapper::Init and the theme modules: the list of templates, their
# files and notes, how init maps them onto a project, and templates from a
# directory or a git repository.

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Init;
use App::Dapper::Theme::Portfolio;
use App::Dapper::Theme::Business;
use App::Dapper::Theme::Docs;
use File::Spec;
use File::Temp qw(tempdir);

my $has_git = grep { -x "$_/git" } File::Spec->path();

# Run code with standard output captured; return what it printed
sub capture_stdout {
    my ($code) = @_;
    my $out = '';
    {
        local *STDOUT;
        open(STDOUT, '>', \$out) or die $!;
        $code->();
    }
    return $out;
}

# Run code with standard error thrown away (git warns about shallow local clones)
sub without_stderr {
    my ($code) = @_;
    open(my $stderr, '>&', \*STDERR) or die $!;
    open(STDERR, '>', File::Spec->devnull) or die $!;
    my @result = eval { $code->() };
    my $error = $@;
    open(STDERR, '>&', $stderr) or die $!;
    die $error if $error;
    return wantarray ? @result : $result[0];
}

sub init_quietly {
    my (@args) = @_;
    local $App::Dapper::Utils::QUIET = 1;
    return App::Dapper::Init::init(@args);
}

my %THEME_FILES = (
    portfolio => [qw(_config.yml _data/profile.yml _layout/index.html _layout/project.html _source/about.md _source/contact.html
                     _source/index.html _source/projects/_schema.yml _source/projects/night-market.md _source/projects/riverside-books.md
                     css/site.css images/project-1.svg images/project-2.svg)],
    business  => [qw(_config.yml _data/business.yml _layout/index.html _layout/post.html _source/about.md _source/contact.html
                     _source/index.html _source/news.html _source/news/_schema.yml _source/news/now-open-sundays.md css/site.css
                     images/storefront.svg)],
    docs      => [qw(_config.yml _data/nav.yml _layout/index.html _source/_schema.yml _source/getting-started.md
                     _source/guide/configuration.md _source/guide/writing-pages.md _source/index.md css/site.css)],
    blog      => [qw(_config.yml _data/menu.yml _layout/index.html _layout/list.html _layout/post.html _source/about.md
                     _source/blog/_schema.yml _source/blog/welcome.md _source/blog/writing-posts.md _source/index.html css/site.css)],
    default   => [qw(_config.yml _layout/index.html _source/index.md)],
);

subtest 'templates and descriptions' => sub {
    is_deeply([ App::Dapper::Init::templates() ], [qw(blog business default docs portfolio)], 'the built-in templates, sorted');
    is(App::Dapper::Init::description('default'), 'The smallest project: a project file, one layout and one page', 'default');
    is(App::Dapper::Init::description('blog'), 'A blog: paginated home page, posts, category and tag pages, feed, a schema for posts', 'blog');
    is(App::Dapper::Init::description('portfolio'), 'A portfolio: a grid of projects with images, and about and contact pages', 'portfolio');
    is(App::Dapper::Init::description('business'), 'A small business: services, opening hours, contact details and news, from one data file', 'business');
    is(App::Dapper::Init::description('docs'), 'Documentation: a sidebar from a data file, previous and next links, code highlighting and search', 'docs');
    is(App::Dapper::Init::description('nope'), undef, 'an unknown template has no description');

    is(App::Dapper::Init::description('portfolio'), App::Dapper::Theme::Portfolio->description(), 'portfolio comes from its theme');
    is(App::Dapper::Init::description('business'), App::Dapper::Theme::Business->description(), 'business comes from its theme');
    is(App::Dapper::Init::description('docs'), App::Dapper::Theme::Docs->description(), 'docs comes from its theme');
    for my $name (App::Dapper::Init::templates()) {
        my $description = App::Dapper::Init::description($name);
        ok(length $description < 100, "$name: the description fits on a line");
        unlike($description, qr/\.$/, "$name: without a full stop");
    }
};

subtest 'template files and notes' => sub {
    for my $name (sort keys %THEME_FILES) {
        my ($files, $notes) = App::Dapper::Init::template_files($name);
        is(ref $files, 'HASH', "$name: a hash of files");
        is_deeply([ sort keys %$files ], $THEME_FILES{$name}, "$name: exactly these files");
        ok(!grep({ ref $_ } values %$files), "$name: contents are text");
        like($files->{'_config.yml'}, qr/^#deploy:$/m, "$name: the project file shows how to deploy");
        like($files->{'_config.yml'}, qr/^#  command: rsync -av --delete _output\/ me\@example\.com:\/var\/www\/site\/$/m, "$name: including a command");
        if ($name eq 'default') {
            is($notes, undef, 'default: no notes');
        }
        else {
            like($notes, qr/\A## About (?:this|these) /, "$name: notes for AGENTS.md");
            like($files->{'_config.yml'}, qr/^url: https:\/\/example\.com$/m, "$name: a url");
        }
    }

    my ($files, $notes) = App::Dapper::Init::template_files('portfolio');
    is($notes, App::Dapper::Theme::Portfolio->notes(), 'portfolio notes come from its theme');
    is_deeply($files, App::Dapper::Theme::Portfolio->files(), 'and its files');
    ($files, $notes) = App::Dapper::Init::template_files('business');
    is($notes, App::Dapper::Theme::Business->notes(), 'business notes come from its theme');
    ($files, $notes) = App::Dapper::Init::template_files('docs');
    is($notes, App::Dapper::Theme::Docs->notes(), 'docs notes come from its theme');
    ($files, $notes) = App::Dapper::Init::template_files('blog');
    like($notes, qr/^- Posts go in `_source\/blog\/`/m, 'blog notes say where posts go');
    like($notes, qr/^- The menu is `_data\/menu\.yml`\.$/m, 'and where the menu is');

    eval { App::Dapper::Init::template_files('nope') };
    is($@, "error: there is no template called \"nope\"; use one of: blog, business, default, docs, portfolio, a directory, or a git URL\n", 'an unknown template');
};

subtest 'the default template' => sub {
    my ($files) = App::Dapper::Init::template_files('default');
    like($files->{'_config.yml'}, qr/\A# Dapper configuration file\n---\nname : My Site\n/, 'the project file');
    is($files->{'_source/index.md'}, "---\nlayout: index\ntitle: Welcome\n---\n\nHello world.\n\n", 'one page');
    like($files->{'_layout/index.html'}, qr/\A<!DOCTYPE html>\n<html lang="en">\n/, 'one layout');
    like($files->{'_layout/index.html'}, qr/<title>\[% page\.title %\]<\/title>/, 'with the title');
    like($files->{'_layout/index.html'}, qr/^\[% page\.content %\]$/m, 'and the content');
};

subtest 'the blog template' => sub {
    my ($files) = App::Dapper::Init::template_files('blog');
    my $config = $files->{'_config.yml'};
    like($config, qr/^name: My Blog$/m, 'named My Blog');
    like($config, qr/^timezone: America\/Chicago$/m, 'a time zone');
    like($config, qr/^feed:\n  category: blog\n  limit: 20$/m, 'a feed of the blog');
    like($config, qr/^category_pages:\n  layout: list\ntag_pages:\n  layout: list$/m, 'category and tag pages');
    like($config, qr/^search: false$/m, 'search off');
    like($files->{'_source/blog/_schema.yml'}, qr/^required: \[title, date, categories\]$/m, 'posts need a title, date and categories');
    like($files->{'_source/blog/_schema.yml'}, qr/^  categories:\n    type: list\n    values: \[blog\]$/m, 'in the blog category');
    like($files->{'_source/index.html'}, qr/^template: true$/m, 'the home page is a template');
    like($files->{'_source/index.html'}, qr/^paginate:\n  category: blog\n  per_page: 10$/m, 'paginated ten to a page');
    like($files->{'_layout/post.html'}, qr/\A---\nlayout: index\ndescription: A blog post, with its date and tags\n---\n/, 'posts are wrapped in the index layout');
    like($files->{'_layout/index.html'}, qr/\[% page\.seo %\]/, 'SEO tags');
    like($files->{'_layout/index.html'}, qr/\[% FOR item IN site\.data\.menu %\]/, 'a menu from data');
    like($files->{'_data/menu.yml'}, qr/^- label: About\n  url: \/about\.html$/m, 'the menu links to about');
    like($files->{'_source/blog/welcome.md'}, qr/^date: 2026-01-01T09:00:00$/m, 'a dated first post');
    like($files->{'_source/blog/welcome.md'}, qr/^```perl$/m, 'with code');
};

subtest 'the portfolio theme' => sub {
    my $files = App::Dapper::Theme::Portfolio->files();
    like($files->{'_config.yml'}, qr/^name: Alex Rivera$/m, 'named');
    like($files->{'_config.yml'}, qr/^image: \/images\/project-1\.svg$/m, 'a default image');
    like($files->{'_source/projects/_schema.yml'}, qr/^required: \[title, date, categories, description, image, image_alt\]$/m, 'projects need images with alt text');
    like($files->{'_source/projects/_schema.yml'}, qr/^  image:\n    type: string\n    pattern: '\^\/'$/m, 'images are paths from the root');
    like($files->{'_source/projects/_schema.yml'}, qr/^  image_alt:\n    type: string\n    min_length: 5$/m, 'alt text of at least five characters');
    like($files->{'_data/profile.yml'}, qr/^email: hello\@example\.com$/m, 'a profile');
    like($files->{'images/project-1.svg'}, qr/<svg/, 'placeholder images');
    my $notes = App::Dapper::Theme::Portfolio->notes();
    like($notes, qr/\A## About this portfolio\n/, 'notes');
    like($notes, qr/`role`, `client` and `link` are optional/, 'optional fields');
    like(App::Dapper::Theme::Portfolio->description(), qr/^A portfolio/, 'description');
};

subtest 'the business theme' => sub {
    my $files = App::Dapper::Theme::Business->files();
    like($files->{'_config.yml'}, qr/^name: Hearth & Crumb Bakery$/m, 'named');
    like($files->{'_config.yml'}, qr/^feed:\n  category: news$/m, 'a feed of the news');
    like($files->{'_data/business.yml'}, qr/^hours:\n  - days: Tuesday to Friday\n    hours: 7am to 3pm$/m, 'opening hours');
    like($files->{'_data/business.yml'}, qr/^  postcode: "60642"$/m, 'a postcode kept as text');
    like($files->{'_data/business.yml'}, qr/^notice: ""$/m, 'an empty notice');
    like($files->{'_source/news/_schema.yml'}, qr/^required: \[title, date, categories, description\]$/m, 'news needs a description');
    like($files->{'_layout/index.html'}, qr/'\@type' => 'PostalAddress'/, 'structured data for the address');
    my $notes = App::Dapper::Theme::Business->notes();
    like($notes, qr/\A## About this business site\n/, 'notes');
    like($notes, qr/Don't copy these\n  details into pages\./, 'keep details in the data file');
};

subtest 'the docs theme' => sub {
    my $files = App::Dapper::Theme::Docs->files();
    like($files->{'_config.yml'}, qr/^name: Widget Docs$/m, 'named');
    like($files->{'_source/_schema.yml'}, qr/^required: \[title, description\]$/m, 'every page needs a title and description');
    like($files->{'_source/_schema.yml'}, qr/^  title:\n    type: string\n    max_length: 70$/m, 'titles up to 70 characters');
    like($files->{'_data/nav.yml'}, qr/^- section: Introduction\n  pages:\n    - title: Overview\n      url: \/$/m, 'the sidebar');
    like($files->{'_data/nav.yml'}, qr/^      url: \/guide\/writing-pages\.html$/m, 'linking every page');
    my $notes = App::Dapper::Theme::Docs->notes();
    like($notes, qr/\A## About these docs\n/, 'notes');
    like($notes, qr/\*\*The sidebar is `_data\/nav\.yml`\.\*\*/, 'the sidebar');
};

subtest 'init writes the template' => sub {
    make_site({}, bare => 1);
    my $out = capture_stdout(sub {
        local $App::Dapper::Utils::QUIET = 0;
        my $notes = App::Dapper::Init::init('_source', '_output', '_layout', '_config.yml', undef);
        is($notes, undef, 'default: no notes returned');
    });
    is($out, "Creating _config.yml\nCreating _layout/index.html\nCreating _source/index.md\nCreating .gitignore\n", 'reports each file');
    is(slurp('.gitignore'), "_output/\n.dapper/\n", '.gitignore');
    my ($files) = App::Dapper::Init::template_files('default');
    is(slurp($_), $files->{$_}, "$_ written as in the template") for sort keys %$files;
    ok(!-e 'AGENTS.md', 'AGENTS.md is not written by Init itself');

    make_site({}, bare => 1);
    $out = capture_stdout(sub {
        my $notes = init_quietly('_source', '_output', '_layout', '_config.yml', 'blog');
        like($notes, qr/\A## About this blog/, 'blog: its notes are returned');
    });
    is($out, '', 'quiet prints nothing');
    ok(-f '_source/blog/welcome.md', 'blog written');
};

subtest 'init maps directories' => sub {
    make_site({}, bare => 1);
    init_quietly('content', 'site', 'templates', 'dapper.yml', 'docs');
    ok(-f 'dapper.yml', 'the project file name');
    ok(-f 'content/guide/configuration.md', 'pages in the source directory, with their folders');
    ok(-f 'content/_schema.yml', 'schemas too');
    ok(-f 'templates/index.html', 'layouts in the layout directory');
    ok(-f '_data/nav.yml' && -f 'css/site.css', 'other files where they are');
    ok(!-e '_source' && !-e '_layout' && !-e '_config.yml', 'not the default names');
    is(slurp('.gitignore'), "site/\n.dapper/\n", '.gitignore names the output directory');

    make_site({}, bare => 1);
    init_quietly('a/b', '_output', 'c/d', 'conf/site.yml', 'default');
    ok(-f 'a/b/index.md' && -f 'c/d/index.html' && -f 'conf/site.yml', 'nested directories are made');
};

subtest 'init never overwrites' => sub {
    make_site({ '_source/index.md' => "mine\n", '.gitignore' => "my-ignores\n" }, bare => 1);
    eval { init_quietly('_source', '_output', '_layout', '_config.yml', 'default') };
    is($@, "error: refusing to initialize, these files already exist: _source/index.md\n", 'one existing file refuses the lot');
    ok(!-e '_config.yml' && !-e '_layout', 'nothing written');
    is(slurp('_source/index.md'), "mine\n", 'the file is untouched');

    unlink '_source/index.md';
    init_quietly('_source', '_output', '_layout', '_config.yml', 'default');
    is(slurp('.gitignore'), "my-ignores\n", 'an existing .gitignore is kept');

    make_site({ 'css/site.css' => "mine\n", '_data/menu.yml' => "mine\n" }, bare => 1);
    eval { init_quietly('_source', '_output', '_layout', '_config.yml', 'blog') };
    is($@, "error: refusing to initialize, these files already exist: _data/menu.yml css/site.css\n", 'files outside the source and layout directories count too, sorted');

    make_site({ 'content/index.md' => "mine\n" }, bare => 1);
    eval { init_quietly('_source', '_output', '_layout', '_config.yml', 'default') };
    is($@, '', 'a file in another directory does not count');
    make_site({ 'content/index.md' => "mine\n" }, bare => 1);
    eval { init_quietly('content', '_output', '_layout', '_config.yml', 'default') };
    is($@, "error: refusing to initialize, these files already exist: content/index.md\n", 'but does when that directory is the source');

    make_site({ '_source' => "a file where a directory goes\n" }, bare => 1);
    eval { init_quietly('_source', '_output', '_layout', '_config.yml', 'default') };
    ok($@, 'a file in the way of a directory is an error');
};

subtest 'a template from a directory' => sub {
    my $theme = tempdir(CLEANUP => 1);
    spew("$theme/_config.yml", "---\nname: Theme\n");
    spew("$theme/_layout/index.html", "[% page.content %]");
    spew("$theme/_source/index.md", "---\ntitle: Home\n---\nHello, café.\n");
    spew("$theme/_source/deep/er/page.md", "---\ntitle: Deep\n---\nx\n");
    spew("$theme/.gitignore", "public/\n");
    spew("$theme/README.md", "# Theme\n");
    spew("$theme/bin.dat", join('', map { chr } 0 .. 255), ':raw');
    spew("$theme/.git/config", "[core]\n");
    spew("$theme/_output/old.html", "old\n");
    spew("$theme/.dapper/state", "x\n");
    spew("$theme/node_modules/x/index.js", "x\n");
    spew("$theme/.DS_Store", "x");
    spew("$theme/images/.DS_Store", "x");
    spew("$theme/images/logo.svg", "<svg/>");
    spew("$theme/sub/_output/kept.html", "kept\n");

    my ($files, $notes) = App::Dapper::Init::template_files($theme);
    is($notes, undef, 'no notes');
    is_deeply([ sort keys %$files ], [qw(.gitignore README.md _config.yml _layout/index.html _source/deep/er/page.md _source/index.md bin.dat images/logo.svg sub/_output/kept.html)],
        'every file, without .git, _output, .dapper, node_modules or .DS_Store (only skipped at the top for directories)');
    is_deeply($files->{'bin.dat'}, { raw => join('', map { chr } 0 .. 255) }, 'contents are raw bytes');

    my ($slash) = App::Dapper::Init::template_files("$theme/");
    is_deeply([ sort keys %$slash ], [ sort keys %$files ], 'a trailing slash makes no difference');

    make_site({}, bare => 1);
    my $out = capture_stdout(sub {
        local $App::Dapper::Utils::QUIET = 0;
        App::Dapper::Init::init('src', '_output', 'lay', 'site.yml', $theme);
    });
    like($out, qr/^Creating lay\/index\.html$/m, 'reports the files it copies');
    unlike($out, qr/Creating \.gitignore\n.*Creating \.gitignore/s, 'once each');
    ok(-f 'site.yml' && -f 'src/index.md' && -f 'lay/index.html' && -f 'src/deep/er/page.md', 'mapped onto the directories given');
    is(slurp('src/index.md'), "---\ntitle: Home\n---\nHello, café.\n", 'text copied');
    is(slurp('bin.dat', ':raw'), join('', map { chr } 0 .. 255), 'binary copied byte for byte');
    is(slurp('.gitignore'), "public/\n", "the theme's .gitignore is used rather than Dapper's");
    ok(!-e '.git' && !-e '_output' && !-e '.dapper' && !-e 'node_modules' && !-e '.DS_Store' && !-e 'images/.DS_Store', 'skipped files are not copied');

    make_site({ 'README.md' => "mine\n" }, bare => 1);
    eval { init_quietly('_source', '_output', '_layout', '_config.yml', $theme) };
    is($@, "error: refusing to initialize, these files already exist: README.md\n", "a theme's files are not written over either");

    my $empty = tempdir(CLEANUP => 1);
    eval { App::Dapper::Init::template_files($empty) };
    is($@, "error: the template $empty has no files\n", 'an empty directory');
    my $only_skipped = tempdir(CLEANUP => 1);
    spew("$only_skipped/.git/HEAD", "x\n");
    spew("$only_skipped/.DS_Store", "x");
    eval { App::Dapper::Init::template_files($only_skipped) };
    is($@, "error: the template $only_skipped has no files\n", 'a directory with only skipped files');

    eval { App::Dapper::Init::template_files("$empty/missing") };
    like($@, qr/^error: there is no template called "\Q$empty\E\/missing"/, 'a missing directory');
};

subtest 'App::Dapper init with a directory template keeps its AGENTS.md and CLAUDE.md' => sub {
    my $theme = tempdir(CLEANUP => 1);
    spew("$theme/_config.yml", "---\nname: Noted\n");
    spew("$theme/_layout/index.html", "[% page.content %]");
    spew("$theme/_source/index.md", "---\ntitle: Home\n---\nx\n");
    spew("$theme/AGENTS.md", "# Theme notes\n");
    spew("$theme/CLAUDE.md", "Theme Claude notes\n");
    make_site({}, bare => 1);
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{template} = $theme;
    capture_stdout(sub { $d->init() });
    like(slurp('AGENTS.md'), qr/\A# Theme notes\n\n<!-- dapper:begin .*<!-- dapper:end -->\n\z/s, "the theme's AGENTS.md comes first, then the guide");
    like(slurp('AGENTS.md'), qr/# Working on Noted/, 'the guide is about the new site');
    is(slurp('CLAUDE.md'), "Theme Claude notes\n", "the theme's CLAUDE.md is kept");
};

subtest 'a template from git' => sub {
    plan skip_all => 'git is not installed' unless $has_git;
    local $ENV{GIT_AUTHOR_NAME} = 'Test';
    local $ENV{GIT_AUTHOR_EMAIL} = 'test@example.com';
    local $ENV{GIT_COMMITTER_NAME} = 'Test';
    local $ENV{GIT_COMMITTER_EMAIL} = 'test@example.com';

    my $base = tempdir(CLEANUP => 1);
    my $work = "$base/work";
    system('git', 'init', '-q', $work) == 0 or plan skip_all => 'git init failed';
    spew("$work/_config.yml", "---\nname: From git\n");
    spew("$work/_layout/index.html", "[% page.content %]");
    spew("$work/_source/index.md", "---\ntitle: Home\n---\nHello from git.\n");
    spew("$work/images/a.bin", "\x00\x01\x02\xff", ':raw');
    system("cd '$work' && git add -A && git commit -q -m theme") == 0 or plan skip_all => 'git commit failed';
    my $bare = "$base/theme.git";
    system('git', 'clone', '-q', '--bare', $work, $bare) == 0 or plan skip_all => 'git clone --bare failed';

    my ($files, $notes) = without_stderr(sub { App::Dapper::Init::template_files($bare) });
    is_deeply([ sort keys %$files ], [qw(_config.yml _layout/index.html _source/index.md images/a.bin)], 'a bare repository ending in .git is cloned; .git is left out');
    is($files->{'images/a.bin'}->{raw}, "\x00\x01\x02\xff", 'bytes kept');
    is($notes, undef, 'no notes');

    ($files) = without_stderr(sub { App::Dapper::Init::template_files("file://$bare") });
    ok($files->{'_source/index.md'}, 'a file:// URL ending in .git');

    make_site({}, bare => 1);
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{template} = $bare;
    without_stderr(sub { capture_stdout(sub { $d->init() }) });
    is(slurp('_source/index.md'), "---\ntitle: Home\n---\nHello from git.\n", 'init copies the clone');
    ok(!-e '.git', 'without .git');
    ok(-f 'AGENTS.md', 'and adds AGENTS.md');
    like(slurp('AGENTS.md'), qr/# Working on From git/, 'about the site');

    my $error;
    {
        open(my $stderr, '>&', \*STDERR);
        open(STDERR, '>', File::Spec->devnull);
        eval { App::Dapper::Init::template_files("$base/missing.git") };
        $error = $@;
        open(STDERR, '>&', $stderr);
    }
    is($error, "error: could not clone the template from $base/missing.git (is git installed, and is the URL right?)\n", 'a repository that is not there');

    my ($plain) = eval { without_stderr(sub { App::Dapper::Init::template_files("file://$work") }) };
    ok($plain && $plain->{'_source/index.md'}, 'a file:// URL without .git is cloned');
};

subtest 'a git URL without git' => sub {
    local $ENV{PATH} = tempdir(CLEANUP => 1);
    my $error;
    {
        open(my $stderr, '>&', \*STDERR);
        open(STDERR, '>', File::Spec->devnull);
        eval { App::Dapper::Init::template_files('/nowhere/theme.git') };
        $error = $@;
        open(STDERR, '>&', $stderr);
    }
    is($error, "error: could not clone the template from /nowhere/theme.git (is git installed, and is the URL right?)\n", 'asks whether git is installed');
};

done_testing();
