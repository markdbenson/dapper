use 5.010;
use strict;
use warnings;
use Test::More;

# dapper deploy from the command line: the target argument and the
# --dry-run, --force, --no-build and --drafts options, with a stand-in for
# the AWS CLI on the PATH.

use lib 't/lib';
use DapperTest;
use App::Dapper;
use Cwd qw(abs_path);
use File::Spec;
use File::Path ();
use File::Temp qw(tempdir);

my $dapper = abs_path(File::Spec->catfile('bin', 'dapper'));
my $lib = abs_path('lib');
my $io = tempdir(CLEANUP => 1);

my $bin = tempdir(CLEANUP => 1);
my $log = "$bin/aws.log";
spew("$bin/aws", "#!$^X\nopen my \$f, '>>', '$log'; print \$f join(' ', \@ARGV), \"\\n\"; close \$f; exit(\$ENV{AWS_EXIT} || 0);\n");
chmod 0755, "$bin/aws";

sub calls { my $text = slurp($log); return defined $text ? [ split /\n/, $text ] : [] }

sub sh_quote {
    my ($s) = @_;
    $s =~ s/'/'\\''/g;
    return "'$s'";
}

sub dapper {
    my @args = @_;
    local $ENV{PATH} = "$bin:$ENV{PATH}";
    system(join(' ', map { sh_quote($_) } $^X, "-I$lib", $dapper, @args)
        . ' >' . sh_quote("$io/out") . ' 2>' . sh_quote("$io/err") . ' <' . File::Spec->devnull);
    my $status = $? >> 8;
    my ($out, $err) = (slurp("$io/out"), slurp("$io/err"));
    return ($status, defined $out ? $out : '', defined $err ? $err : '');
}

my %site = (
    '_config.yml'      => "---\nname: x\ndeploy:\n  s3:\n    bucket: example.com\n    cloudfront: E1\n",
    '_source/index.md' => "---\ntitle: Home\n---\nHello\n",
    '_source/draft.md' => "---\ntitle: Draft\ndraft: true\n---\nDraft\n",
);

subtest 'deploy' => sub {
    make_site({ %site });
    unlink $log;
    my ($status, $out, $err) = dapper('deploy');
    is($status, 0, 'exits 0');
    like($out, qr/^Project built\.$/m, 'builds first');
    like($out, qr/^\+ aws s3 sync _output s3:\/\/example\.com --delete --exclude \.dapper-reload$/m, 'shows the sync');
    like($out, qr/^\+ aws cloudfront create-invalidation --distribution-id E1 --paths \/\*$/m, 'and the invalidation');
    like($out, qr/Deployed to s3:\/\/example\.com\n\z/, 'and says where it deployed');
    is($err, '', 'nothing on standard error');
    is_deeply(calls(), ['s3 sync _output s3://example.com --delete --exclude .dapper-reload',
                        'cloudfront create-invalidation --distribution-id E1 --paths /*'], 'the AWS CLI was called twice');

    unlink $log;
    ($status, $out, $err) = dapper('-q', 'deploy');
    is($status, 0, '-q exits 0');
    is($out, '', '-q prints nothing');

    unlink $log;
    ($status, $out) = dapper('deploy', '--dry-run');
    is($status, 0, '--dry-run exits 0');
    is_deeply(calls(), ['s3 sync _output s3://example.com --delete --exclude .dapper-reload --dryrun'], 'syncs with --dryrun and does not invalidate');
    like($out, qr/^Would run: aws cloudfront create-invalidation --distribution-id E1 --paths \/\*\nDry run: nothing was uploaded\.\n\z/m, 'says what it would do');

    unlink $log;
    ($status, $out) = dapper('-q', 'deploy', 's3');
    is($status, 0, 'naming the target exits 0');
    is(scalar @{ calls() }, 2, 'and deploys');

    unlink $log;
    File::Path::remove_tree('_output');
    ($status, $out) = dapper('-q', '--drafts', 'deploy');
    is($status, 0, '--drafts exits 0');
    ok(-f '_output/index.html', 'the site is built');
    ok(!-e '_output/draft.html', 'but drafts are never deployed');

    unlink $log;
    ($status, $out) = dapper('-q', '-o', 'public', 'deploy');
    is($status, 0, '-o exits 0');
    like(calls()->[0], qr/^s3 sync public s3:\/\/example\.com /, 'and syncs the output directory given');

    {
        local $ENV{AWS_EXIT} = 2;
        unlink $log;
        my ($s, $o, $e) = dapper('-q', 'deploy');
        is($s, 1, 'a failing AWS CLI exits 1');
        is($e, "error: aws s3 failed (exit status 2)\n", 'and says which command failed');
    }
};

subtest '--no-build' => sub {
    make_site({ %site });
    unlink $log;
    my ($status, $out, $err) = dapper('deploy', '--no-build');
    is($status, 1, 'without an output directory exits 1');
    is($err, "error: the output directory \"_output\" doesn't exist; build the site first\n", 'and says to build');
    ok(!-e $log, 'nothing uploaded');

    dapper('-q', 'build');
    spew('_source/new.md', "---\ntitle: New\n---\nNew\n");
    ($status, $out, $err) = dapper('deploy', '--no-build');
    is($status, 0, 'with one exits 0');
    unlike($out, qr/Project built/, 'without building');
    ok(!-e '_output/new.html', 'so the new page is not in it');
    is(scalar @{ calls() }, 2, 'and uploads');
};

subtest '--force' => sub {
    make_site({ %site, '_source/broken.md' => "---\ntitle: Broken\n---\n[x](/nowhere/)\n" });
    unlink $log;
    my ($status, $out, $err) = dapper('-q', 'deploy');
    is($status, 1, 'errors from check exit 1');
    is($err, "error: dapper check found 1 error(s), so the site was not deployed (use --force to deploy anyway):\n  _source/broken.md: links to /nowhere/, which is not in the site\n", 'and say why');
    ok(!-e $log, 'nothing uploaded');

    ($status, $out, $err) = dapper('-q', 'deploy', '--force');
    is($status, 0, '--force exits 0');
    is($err, "warning: deploying even though dapper check found errors:\n  _source/broken.md: links to /nowhere/, which is not in the site\n", 'with a warning');
    is(scalar @{ calls() }, 2, 'and uploads');

    unlink $log;
    ($status, $out, $err) = dapper('-q', 'deploy', '--force', '--dry-run');
    is($status, 0, '--force --dry-run exits 0');
    like(calls()->[0], qr/ --dryrun$/, 'and only pretends');
};

subtest 'choosing a target' => sub {
    make_site({ %site, '_config.yml' => "---\nname: x\ndeploy:\n  s3:\n    bucket: example.com\n  command: '$^X -e \"open my \\\$f, q(>), q(ran.txt)\"'\n" });
    my ($status, $out, $err) = dapper('deploy');
    is($status, 1, 'two targets and no name exits 1');
    is($err, "error: _config.yml has several deploy targets (s3, command); say which: dapper deploy <target>\n", 'and asks which');

    ($status, $out, $err) = dapper('-q', 'deploy', 'command');
    is($status, 0, 'naming one exits 0');
    ok(-e 'ran.txt', 'and runs it');

    ($status, $out, $err) = dapper('-q', 'deploy', 'command', '--dry-run');
    is($status, 0, 'a dry run of a command exits 0');
    ($status, $out, $err) = dapper('deploy', 'command', '--dry-run', '--no-build');
    like($out, qr/\ADry run: would run: \Q$^X\E -e /, 'says what it would run, without building');

    ($status, $out, $err) = dapper('deploy', 'github_pages');
    is($status, 1, 'a target that is not set exits 1');
    is($err, "error: there are no \"github_pages\" deploy settings in _config.yml\n", 'and says so');
};

done_testing();
