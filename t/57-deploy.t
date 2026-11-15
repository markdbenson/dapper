use 5.010;
use strict;
use warnings;
use Test::More;

# App::Dapper::Deploy: choosing a target, building and checking first, and
# every target (S3, GitHub Pages and a command) with every option and every
# error. The AWS CLI is a stand-in on the PATH and GitHub is a local bare
# repository, so nothing here touches the network.

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Deploy;
use File::Temp qw(tempdir);
use File::Spec;
use File::Path ();

my $has_git = grep { -x "$_/git" } File::Spec->path();

# A stand-in for the AWS CLI that records how it was called, and fails when
# asked to
my $bin = tempdir(CLEANUP => 1);
my $log = "$bin/aws.log";
spew("$bin/aws", <<"PERL");
#!$^X
open my \$f, '>>', '$log';
print \$f join(' ', \@ARGV), "\\n";
close \$f;
exit(\$ENV{AWS_SYNC_EXIT} || 0) if \$ARGV[0] eq 's3';
exit(\$ENV{AWS_CLOUDFRONT_EXIT} || 0);
PERL
chmod 0755, "$bin/aws";

sub calls { my $text = slurp($log); return defined $text ? [ split /\n/, $text ] : [] }

# deploy($target, %options): deploy quietly; returns what deploy returned
sub deploy {
    my ($target, %options) = @_;
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    return $d->deploy($target, %options);
}

# deploy_output($target, %options): deploy with progress messages; returns
# (result, standard output, warnings, error)
sub deploy_output {
    my ($target, %options) = @_;
    my $d = delete $options{dapper} || App::Dapper->new();
    my ($result, $out, @warnings) = (undef, '');
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my $ok;
    {
        local *STDOUT;
        open(STDOUT, '>', \$out);
        $ok = eval { $result = $d->deploy($target, %options); 1 };
    }
    return ($result, $out, join('', @warnings), $ok ? '' : $@);
}

sub error_of {
    my ($code) = @_;
    return eval { $code->(); 1 } ? '' : $@;
}

my %site = (
    '_source/index.md' => "---\ntitle: Home\n---\nHello\n",
    '_source/about.md' => "---\ntitle: About\n---\n[Home](/)\n",
);

subtest 'choosing a target' => sub {
    make_site({ %site });
    is(error_of(sub { deploy() }), "error: there is nowhere to deploy to; add deploy settings to _config.yml (see \"Deploying with dapper deploy\" in the README)\n", 'no deploy settings');

    for my $settings ('deploy: s3', 'deploy: {}', 'deploy: []', 'deploy: ~') {
        make_site({ %site, '_config.yml' => "---\nname: x\n$settings\n" });
        like(error_of(sub { deploy() }), qr/^error: there is nowhere to deploy to;/, "$settings is nowhere to deploy to");
    }

    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  zeta: 1\n  ftp: x\n  command: 'true'\n" });
    is(error_of(sub { deploy() }), "error: unknown deploy target \"ftp\" in _config.yml; use s3, github_pages, command\n", 'unknown targets are reported first, the first in order');
    is(error_of(sub { deploy('command') }), "error: unknown deploy target \"ftp\" in _config.yml; use s3, github_pages, command\n", 'even when a good target is named');

    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  command: 'true'\n  github_pages:\n    repo: x\n  s3:\n    bucket: a\n" });
    is(error_of(sub { deploy() }), "error: _config.yml has several deploy targets (s3, github_pages, command); say which: dapper deploy <target>\n", 'several targets, listed in a fixed order');
    is(error_of(sub { deploy('ftp') }), "error: there are no \"ftp\" deploy settings in _config.yml\n", 'naming a target that is not set');

    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  command: 'true'\n" });
    is(error_of(sub { deploy('s3') }), "error: there are no \"s3\" deploy settings in _config.yml\n", 'naming another target than the one set');
    ok(deploy('command'), 'naming the one that is set');
    ok(deploy(), 'or not naming it');

    make_site({ %site, 'site.yml' => "---\nname: x\n" });
    my $d = App::Dapper->new(undef, undef, undef, 'site.yml');
    $d->{quiet} = 1;
    like(error_of(sub { $d->deploy() }), qr/add deploy settings to site\.yml /, 'messages name the project file in use');

    make_site({ %site });
    unlink '_config.yml';
    like(error_of(sub { deploy() }), qr/^error: could not find the project file "_config\.yml"/, 'no project file');
};

subtest 'build and check first' => sub {
    make_site({ %site,
        '_source/draft.md' => "---\ntitle: Draft\ndraft: true\n---\nDraft\n",
        '_deploy.pl'       => "open my \$f, '>', 'deployed.txt'; print \$f 'yes';\n",
        '_config.yml'      => "---\nname: x\ndeploy:\n  command: '$^X _deploy.pl'\n",
    });
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{drafts} = 1;
    ok($d->deploy(), 'deployed');
    ok(-f '_output/index.html', 'the site is built first');
    ok(!-e '_output/draft.html', 'drafts are never deployed, even when asked for');
    is($d->{drafts}, 1, 'and the setting is put back');
    is(slurp('deployed.txt'), 'yes', 'the command ran');

    spew('_source/new.md', "---\ntitle: New\n---\nNew\n");
    unlink 'deployed.txt';
    ok(deploy(undef, no_build => 1), '--no-build');
    ok(!-e '_output/new.html', 'does not build');
    is(slurp('deployed.txt'), 'yes', 'but deploys');

    spew('_source/broken.md', "---\ntitle: Broken\n---\n[x](/nowhere/)\n");
    unlink 'deployed.txt';
    ok(deploy(undef, no_build => 1), '--no-build does not check either');
    ok(-e 'deployed.txt', 'so a site with errors is deployed');

    unlink 'deployed.txt';
    spew('_source/broken2.md', "---\ntitle: Broken too\n---\n[y](/missing/)\n");
    my $error = error_of(sub { deploy() });
    like($error, qr/\Aerror: dapper check found 2 error\(s\), so the site was not deployed \(use --force to deploy anyway\):\n/, 'errors stop the deploy, counted');
    like($error, qr/^  _source\/broken\.md: links to \/nowhere\/, which is not in the site$/m, 'listing the first');
    like($error, qr/^  _source\/broken2\.md: links to \/missing\/, which is not in the site$/m, 'and the second');
    ok(!-e 'deployed.txt', 'nothing deployed');

    my ($result, $out, $warnings) = deploy_output(undef, force => 1, dapper => do { my $q = App::Dapper->new(); $q->{quiet} = 1; $q });
    ok($result, '--force deploys anyway');
    like($warnings, qr/\Awarning: deploying even though dapper check found errors:\n  _source\/broken\.md: links to \/nowhere\/, which is not in the site\n/, 'with a warning listing the errors');
    ok(-e 'deployed.txt', 'deployed');

    File::Path::remove_tree('_output');
    unlink '_source/broken.md', '_source/broken2.md';
    is(error_of(sub { deploy(undef, no_build => 1) }), "error: the output directory \"_output\" doesn't exist; build the site first\n", '--no-build without an output directory');

    my $other = App::Dapper->new(undef, 'public');
    $other->{quiet} = 1;
    is(error_of(sub { $other->deploy(undef, no_build => 1) }), "error: the output directory \"public\" doesn't exist; build the site first\n", 'naming the output directory in use');
};

subtest 'find_command and run_command' => sub {
    local $ENV{PATH} = $bin;
    ok(App::Dapper::Deploy::find_command('aws'), 'a command on the PATH is found');
    ok(!App::Dapper::Deploy::find_command('no-such-command'), 'a missing one is not');
    ok(!App::Dapper::Deploy::find_command('aws.log'), 'a file that is not executable is not');

    make_site({ %site });
    my $d = App::Dapper->new();
    my $out = '';
    {
        local *STDOUT;
        open(STDOUT, '>', \$out);
        App::Dapper::Deploy::run_command($d, $^X, '-e', 'exit 0', 'two words');
    }
    is($out, "+ $^X -e 'exit 0' 'two words'\n", 'the command is shown, arguments with spaces quoted');

    my $error = error_of(sub {
        local *STDOUT;
        open(STDOUT, '>', \my $ignored);
        App::Dapper::Deploy::run_command($d, $^X, '-e', 'exit 7');
    });
    is($error, "error: $^X -e failed (exit status 7)\n", 'a failure names the first two words and the exit status');

    $d->{quiet} = 1;
    $out = '';
    {
        local *STDOUT;
        open(STDOUT, '>', \$out);
        App::Dapper::Deploy::run_command($d, $^X, '-e', '1');
    }
    is($out, '', 'nothing shown when quiet');
};

subtest 'S3' => sub {
    local $ENV{PATH} = "$bin:$ENV{PATH}";
    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  s3:\n    bucket: s3://example.com\n" });
    unlink $log;
    my ($result, $out) = deploy_output();
    is($result, 1, 'returns 1');
    is_deeply(calls(), ['s3 sync _output s3://example.com --delete --exclude .dapper-reload'], 'one sync: s3:// is not doubled, no region, profile or cache control');
    like($out, qr/^\+ aws s3 sync _output s3:\/\/example\.com --delete --exclude \.dapper-reload\nDeployed to s3:\/\/example\.com\n\z/m, 'shows the command and where it deployed');
    like($out, qr/\AProcessing /, 'after building');

    unlink $log;
    ($result, $out) = deploy_output(undef, dry_run => 1);
    is($result, 1, 'a dry run returns 1');
    is_deeply(calls(), ['s3 sync _output s3://example.com --delete --exclude .dapper-reload --dryrun'], 'syncs with --dryrun');
    like($out, qr/Dry run: nothing was uploaded\.\n\z/, 'and says nothing was uploaded');

    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  s3:\n    bucket: example.com\n    region: eu-west-2\n    profile: work\n    cloudfront: EABC\n    cache_control: 'max-age=60, public'\n" });
    unlink $log;
    ($result, $out) = deploy_output();
    is_deeply(calls(), [
        's3 sync _output s3://example.com --delete --exclude .dapper-reload --region eu-west-2 --profile work --cache-control max-age=60, public',
        'cloudfront create-invalidation --distribution-id EABC --paths /* --region eu-west-2 --profile work',
    ], 'sync, then a CloudFront invalidation, each with the region and profile');
    like($out, qr/^\+ aws s3 sync .* --cache-control 'max-age=60, public'$/m, 'a cache control with spaces is quoted when shown');
    like($out, qr/^\+ aws cloudfront create-invalidation --distribution-id EABC --paths \/\* --region eu-west-2 --profile work$/m, 'the invalidation is shown');

    unlink $log;
    ($result, $out) = deploy_output(undef, dry_run => 1);
    is(scalar @{ calls() }, 1, 'a dry run does not invalidate');
    like($out, qr/^Would run: aws cloudfront create-invalidation --distribution-id EABC --paths \/\* --region eu-west-2 --profile work$/m, 'but says it would');

    {
        local $ENV{AWS_SYNC_EXIT} = 3;
        unlink $log;
        my ($r, $o, $w, $error) = deploy_output();
        is($error, "error: aws s3 failed (exit status 3)\n", 'a failed sync');
        is(scalar @{ calls() }, 1, 'stops before the invalidation');
    }
    {
        local $ENV{AWS_CLOUDFRONT_EXIT} = 4;
        my ($r, $o, $w, $error) = deploy_output();
        is($error, "error: aws cloudfront failed (exit status 4)\n", 'a failed invalidation');
    }
};

subtest 'S3 settings' => sub {
    local $ENV{PATH} = "$bin:$ENV{PATH}";
    for my $settings ("s3: example.com", "s3:\n    region: x", "s3:\n    bucket: ''", "s3:\n    bucket: ~") {
        make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  $settings\n" });
        is(error_of(sub { deploy() }), "error: deploy.s3 in _config.yml needs a bucket\n", "\"$settings\" needs a bucket");
    }

    local $ENV{PATH} = tempdir(CLEANUP => 1);
    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  s3:\n    bucket: b\n" });
    is(error_of(sub { deploy() }), "error: deploying to S3 needs the AWS CLI (https://aws.amazon.com/cli/); install it and run \"aws configure\"\n", 'without the AWS CLI');
};

subtest 'a command' => sub {
    make_site({ %site,
        '_deploy.pl'  => "open my \$f, '>', 'deployed.txt'; print \$f \"\$ENV{DAPPER_OUTPUT}|\@ARGV\";\n",
        '_config.yml' => "---\nname: x\ndeploy:\n  command: '$^X _deploy.pl one two'\n" });
    my ($result, $out) = deploy_output();
    is($result, 1, 'returns 1');
    is(slurp('deployed.txt'), '_output|one two', 'runs through the shell, with DAPPER_OUTPUT set');
    like($out, qr/^\+ \Q$^X\E _deploy\.pl one two\nDeployed\.\n\z/m, 'shows the command and that it deployed');
    ok(!defined $ENV{DAPPER_OUTPUT}, 'DAPPER_OUTPUT is not left set');

    unlink 'deployed.txt';
    ($result, $out) = deploy_output(undef, dry_run => 1);
    is($result, 1, 'a dry run returns 1');
    ok(!-e 'deployed.txt', 'and does not run it');
    like($out, qr/^Dry run: would run: \Q$^X\E _deploy\.pl one two\n\z/m, 'but says what it would run');

    my $d = App::Dapper->new(undef, 'public');
    ($result) = deploy_output(undef, dapper => $d);
    is(slurp('deployed.txt'), 'public|one two', 'DAPPER_OUTPUT is the output directory in use');

    spew('_config.yml', "---\nname: x\ndeploy:\n  command: '$^X -e \"exit 5\"'\n");
    is(error_of(sub { deploy() }), "error: the deploy command failed (exit status 5)\n", 'a failing command');

    for my $setting ("command: ''", "command:\n    run: x", "command: [a, b]", "command: ~") {
        spew('_config.yml', "---\nname: x\ndeploy:\n  $setting\n");
        is(error_of(sub { deploy() }), "error: deploy.command in _config.yml must be a command to run\n", "\"$setting\" is not a command");
    }
};

subtest 'GitHub Pages' => sub {
    plan skip_all => 'git is not installed' unless $has_git;
    local $ENV{GIT_AUTHOR_NAME} = 'Test';
    local $ENV{GIT_AUTHOR_EMAIL} = 'test@example.com';
    local $ENV{GIT_COMMITTER_NAME} = 'Test';
    local $ENV{GIT_COMMITTER_EMAIL} = 'test@example.com';
    my $remote = tempdir(CLEANUP => 1) . '/site.git';
    system('git', 'init', '--quiet', '--bare', $remote) == 0 or plan skip_all => 'git init failed';
    my $git = sub { my $out = `git --git-dir='$remote' @_`; return $out };

    make_site({ %site, '_config.yml' => "---\nname: Pages Site\ndeploy:\n  github_pages:\n    repo: $remote\n    branch: site\n" });
    spew('_output/.dapper-reload', "1\n");
    my ($result, $out) = deploy_output();
    is($result, 1, 'returns 1');
    like($out, qr/^Starting a new site branch$/m, 'says it starts a new branch');
    like($out, qr/^\+ git init --quiet /m, 'shows the git commands');
    like($out, qr/^Deployed (\d+) changed file\(s\) to site of \Q$remote\E\n\z/m, 'says how many files it deployed, and where');
    my $files = $git->('ls-tree -r --name-only site');
    like($files, qr/^index\.html$/m, 'pushed to the branch named');
    like($files, qr/^\.nojekyll$/m, '.nojekyll added');
    unlike($files, qr/^CNAME$/m, 'no CNAME without cname');
    unlike($files, qr/dapper-reload/, '.dapper-reload is not published');
    is($git->('log -1 --format=%s site'), "Deploy Pages Site (" . (() = $files =~ /\n/g) . " file(s) changed)\n", 'the commit says what changed');
    is($git->('log -1 --format=%an site'), "Test\n", "committed as git's user");
    is($git->('branch --list gh-pages'), '', 'gh-pages is not made');

    ($result, $out) = deploy_output();
    like($out, qr/^Nothing changed since the last deploy to site\.\n\z/m, 'nothing to deploy');
    is($git->('rev-list --count site') + 0, 1, 'and no commit');

    spew('_source/new.md', "---\ntitle: New\n---\nNew\n");
    ($result, $out) = deploy_output(undef, dry_run => 1);
    like($out, qr/^Dry run: would commit \d+ changed file\(s\) to site of \Q$remote\E:$/m, 'a dry run says what it would commit');
    like($out, qr/^A  new\.html$/m, 'listing the changes');
    is($git->('rev-list --count site') + 0, 1, 'and commits nothing');
    like($out, qr/^\+ git clone --quiet --branch site -- \Q$remote\E /m, 'the existing branch is cloned in full from a local path');

    ($result, $out) = deploy_output(undef, no_build => 1);
    is($git->('rev-list --count site') + 0, 2, 'a second deploy adds a commit');
    like($git->('ls-tree -r --name-only site'), qr/^new\.html$/m, 'with the new page');
};

subtest 'GitHub Pages settings' => sub {
    plan skip_all => 'git is not installed' unless $has_git;
    local $ENV{GIT_AUTHOR_NAME} = 'Test';
    local $ENV{GIT_AUTHOR_EMAIL} = 'test@example.com';
    local $ENV{GIT_COMMITTER_NAME} = 'Test';
    local $ENV{GIT_COMMITTER_EMAIL} = 'test@example.com';
    local $ENV{GIT_CEILING_DIRECTORIES} = File::Spec->tmpdir;
    my $remote = tempdir(CLEANUP => 1) . '/site.git';
    system('git', 'init', '--quiet', '--bare', $remote) == 0 or plan skip_all => 'git init failed';

    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  github_pages: true\n" });
    {
        open(my $stderr, '>&', \*STDERR);
        open(STDERR, '>', File::Spec->devnull);
        my $error = error_of(sub { deploy() });
        open(STDERR, '>&', $stderr);
        is($error, "error: deploy.github_pages in _config.yml needs a repo (or run dapper in a git repository with an origin)\n", 'without a repo or an origin');
    }

    is(system('git', 'init', '--quiet', '.'), 0, 'the site is a git repository');
    is(system('git', 'remote', 'add', 'origin', $remote), 0, 'with an origin');
    ok(deploy(), 'with the origin of the repository dapper runs in');
    like(`git --git-dir='$remote' ls-tree -r --name-only gh-pages`, qr/^index\.html$/m, 'to gh-pages by default');

    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  github_pages:\n    repo: $remote\n    cname: docs.example.com\n" });
    ok(deploy(), 'with a cname');
    is(`git --git-dir='$remote' show gh-pages:CNAME`, "docs.example.com\n", 'CNAME written');
    is(`git --git-dir='$remote' rev-list --count gh-pages` + 0, 2, 'on top of the history that was there');

    my $url = tempdir(CLEANUP => 1) . '/url.git';
    system('git', 'init', '--quiet', '--bare', $url) == 0 or return;
    make_site({ %site, 'css/site.css' => "body {}\n", '_config.yml' => "---\ndeploy:\n  github_pages:\n    repo: file://$url\n" });
    ok(deploy(), 'a repository given as a URL');
    spew('_source/more.md', "---\ntitle: More\n---\nMore\n");
    my ($result, $out) = deploy_output();
    like($out, qr/^\+ git clone --quiet --depth 1 --branch gh-pages -- file:\/\/\Q$url\E /m, 'is cloned shallow');
    is(`git --git-dir='$url' rev-list --count gh-pages` + 0, 2, 'and deployed again');
    like(`git --git-dir='$url' ls-tree -r --name-only gh-pages`, qr/^css\/site\.css$/m, 'folders in the output are replaced too');
    like(`git --git-dir='$url' log -1 --format=%s gh-pages`, qr/^Deploy the site \(\d+ file\(s\) changed\)$/, 'a site without a name is "the site"');

    local $ENV{PATH} = $bin;
    is(error_of(sub { deploy(undef, no_build => 1) }), "error: deploying to GitHub Pages needs git\n", 'without git');
};

done_testing();
