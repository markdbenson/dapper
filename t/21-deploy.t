use 5.010;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;
use Cwd qw(getcwd);

use lib 't/lib';
use DapperTest;
use App::Dapper;

sub deploy {
    my ($target, %options) = @_;
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    return $d->deploy($target, %options);
}

my $has_git = grep { -x "$_/git" } File::Spec->path();

# A stand-in for the AWS CLI that records how it was called
my $bin = tempdir(CLEANUP => 1);
my $log = "$bin/aws.log";
spew("$bin/aws", "#!$^X\nopen my \$f, '>>', '$log'; print \$f join(' ', \@ARGV), \"\\n\";\n");
chmod 0755, "$bin/aws";

my %site = (
    '_source/index.md' => "---\ntitle: Home\n---\nHello\n",
    '_source/about.md' => "---\ntitle: About\n---\n[Home](/)\n",
);

subtest 'S3' => sub {
    local $ENV{PATH} = "$bin:$ENV{PATH}";
    unlink $log;
    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  s3:\n    bucket: example.com\n    region: us-east-1\n    profile: me\n    cloudfront: E123\n    cache_control: max-age=60\n" });
    ok(deploy(), 'deployed');
    my @calls = split /\n/, slurp($log);
    is($calls[0], 's3 sync _output s3://example.com --delete --exclude .dapper-reload --region us-east-1 --profile me --cache-control max-age=60', 'sync');
    is($calls[1], 'cloudfront create-invalidation --distribution-id E123 --paths /* --region us-east-1 --profile me', 'invalidation');
    ok(-f '_output/index.html', 'built first');

    unlink $log;
    ok(deploy(undef, dry_run => 1), 'dry run');
    @calls = split /\n/, slurp($log);
    like($calls[0], qr/ --dryrun$/, 'sync with --dryrun');
    is(scalar @calls, 1, 'no invalidation on a dry run');
};

subtest 'S3 without the AWS CLI' => sub {
    local $ENV{PATH} = '/nonexistent';
    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  s3:\n    bucket: example.com\n" });
    eval { deploy(undef, no_build => 1) };
    like($@, qr/needs the AWS CLI/, 'clear error') if -d '_output';
    eval { deploy() };
    like($@, qr/needs the AWS CLI/, 'clear error after building');
};

subtest 'a command' => sub {
    make_site({ %site,
        '_deploy.pl'  => "open my \$f, '>', 'deployed.txt'; print \$f \$ENV{DAPPER_OUTPUT};\n",
        '_config.yml' => "---\nname: x\ndeploy:\n  command: '$^X _deploy.pl'\n" });
    ok(deploy(), 'deployed');
    is(slurp('deployed.txt'), '_output', 'ran with DAPPER_OUTPUT');

    unlink 'deployed.txt';
    deploy(undef, dry_run => 1);
    ok(!-e 'deployed.txt', 'a dry run does not run it');
};

subtest 'GitHub Pages' => sub {
    plan skip_all => 'git is not installed' unless $has_git;
    my $remote = tempdir(CLEANUP => 1) . '/site.git';
    system('git', 'init', '--quiet', '--bare', $remote) == 0 or plan skip_all => 'git init failed';
    local $ENV{GIT_AUTHOR_NAME} = 'Test';
    local $ENV{GIT_AUTHOR_EMAIL} = 'test@example.com';
    local $ENV{GIT_COMMITTER_NAME} = 'Test';
    local $ENV{GIT_COMMITTER_EMAIL} = 'test@example.com';

    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  github_pages:\n    repo: $remote\n    cname: www.example.com\n" });
    ok(deploy(), 'first deploy');

    my $files = `git --git-dir='$remote' ls-tree -r --name-only gh-pages`;
    like($files, qr/^index\.html$/m, 'pages pushed to gh-pages');
    like($files, qr/^\.nojekyll$/m, '.nojekyll added');
    is(`git --git-dir='$remote' show gh-pages:CNAME`, "www.example.com\n", 'CNAME added');
    unlike($files, qr/\.dapper/, 'nothing from .dapper');

    ok(deploy(), 'deploy with nothing changed');
    is(`git --git-dir='$remote' rev-list --count gh-pages` + 0, 1, 'no empty commit');

    spew('_source/new.md', "---\ntitle: New\n---\nNew page\n");
    unlink '_source/about.md';
    ok(deploy(undef, dry_run => 1), 'dry run');
    is(`git --git-dir='$remote' rev-list --count gh-pages` + 0, 1, 'a dry run pushes nothing');

    ok(deploy(), 'second deploy');
    is(`git --git-dir='$remote' rev-list --count gh-pages` + 0, 2, 'history kept');
    $files = `git --git-dir='$remote' ls-tree -r --name-only gh-pages`;
    like($files, qr/^new\.html$/m, 'new page published');
    unlike($files, qr/^about\.html$/m, 'removed page removed');
};

subtest 'check guards the deploy' => sub {
    local $ENV{PATH} = "$bin:$ENV{PATH}";
    unlink $log;
    make_site({ %site, '_source/broken.md' => "---\ntitle: Broken\n---\n[x](/nowhere/)\n",
                '_config.yml' => "---\nname: x\ndeploy:\n  s3:\n    bucket: example.com\n" });
    eval { deploy() };
    like($@, qr/dapper check found 1 error\(s\), so the site was not deployed.*links to \/nowhere\//s, 'refused, with the reason');
    ok(!-e $log, 'nothing uploaded');

    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    ok(deploy(undef, force => 1), '--force deploys anyway');
    like(join('', @warnings), qr/deploying even though/, 'with a warning');
};

subtest 'choosing a target' => sub {
    make_site({ %site, '_config.yml' => "---\nname: x\n" });
    eval { deploy() };
    like($@, qr/there is nowhere to deploy to/, 'no settings');

    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  s3:\n    bucket: a\n  command: 'true'\n" });
    eval { deploy() };
    like($@, qr/several deploy targets \(s3, command\); say which/, 'several targets need a name');
    eval { deploy('github_pages') };
    like($@, qr/there are no "github_pages" deploy settings/, 'missing target');

    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  ftp: x\n" });
    eval { deploy() };
    like($@, qr/unknown deploy target "ftp"/, 'unknown target');
};

done_testing();
