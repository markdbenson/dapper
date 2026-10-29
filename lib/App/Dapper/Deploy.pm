package App::Dapper::Deploy;

=head1 NAME

App::Dapper::Deploy - Publish a site to Amazon S3, GitHub Pages, or anywhere.

=head1 DESCRIPTION

C<dapper deploy> builds the site, checks it, and publishes the output
directory. Where it goes is set under C<deploy> in C<_config.yml>:

    deploy:
      s3:
        bucket: example.com
        region: us-east-1           # optional
        profile: personal           # optional: an AWS CLI profile
        cloudfront: E1A2B3C4D5E6F7  # optional: a distribution to refresh
        cache_control: max-age=300  # optional
      github_pages:
        repo: git@github.com:me/site.git  # default: this repository's origin
        branch: gh-pages                  # the default
        cname: www.example.com            # optional
      command: rsync -av --delete _output/ me@example.com:/var/www/site/

With one target, C<dapper deploy> uses it; with several, name one:
C<dapper deploy s3>. Credentials are never stored in C<_config.yml>: S3 uses
the AWS CLI's own configuration (C<aws configure>), and GitHub Pages uses
git's.

=over 4

=item B<s3>

Runs C<aws s3 sync --delete>, which uploads only files that changed and
removes files that are gone, then (with C<cloudfront>) asks CloudFront to
refresh its copies.

=item B<github_pages>

Commits the output to a branch (adding C<.nojekyll>, and C<CNAME> if set)
and pushes it. The branch keeps its history.

=item B<command>

Runs a command of your own. C<DAPPER_OUTPUT> holds the output directory.

=back

The site is not deployed if C<dapper check> finds errors, unless
C<--force> is given. C<--dry-run> shows what would happen without changing
anything. C<--no-build> deploys the output directory as it is.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use File::Temp qw/ tempdir /;
use File::Spec;
use File::Spec::Functions qw/ catfile /;
use File::Path ();
use Cwd qw/ abs_path /;

use App::Dapper::Utils;
use App::Dapper::Check;

my @TARGETS = qw/ s3 github_pages command /;

=head2 run

Takes a Dapper object, the target to deploy to (or C<undef> to pick the only
one), and options (C<dry_run>, C<force>, C<no_build>). Builds, checks and
deploys the site.

=cut

sub run {
    my ($dapper, $target, %options) = @_;

    $dapper->read_project();
    my $settings = $dapper->{site}->{deploy};
    die "error: there is nowhere to deploy to; add deploy settings to $dapper->{config} (see \"Deploying with dapper deploy\" in the README)\n"
        unless ref $settings eq 'HASH' and %$settings;

    my @configured = grep { exists $settings->{$_} } @TARGETS;
    my @unknown = grep { my $t = $_; !grep { $_ eq $t } @TARGETS } sort keys %$settings;
    die "error: unknown deploy target \"$unknown[0]\" in $dapper->{config}; use " . join(', ', @TARGETS) . "\n" if @unknown;

    if (not defined $target) {
        die "error: $dapper->{config} has several deploy targets (" . join(', ', @configured)
          . "); say which: dapper deploy <target>\n" if @configured > 1;
        $target = $configured[0];
    }
    die "error: there are no \"$target\" deploy settings in $dapper->{config}\n" unless exists $settings->{$target};

    if (not $options{no_build}) {
        $dapper->build();

        my $report = App::Dapper::Check::run($dapper);
        if (not $report->{ok}) {
            my $errors = join('', map { "  $_->{file}: $_->{message}\n" } @{$report->{errors}});
            die "error: dapper check found " . scalar(@{$report->{errors}}) . " error(s), so the site was not deployed"
              . " (use --force to deploy anyway):\n$errors" unless $options{force};
            warn "warning: deploying even though dapper check found errors:\n$errors";
        }
    }

    die "error: the output directory \"$dapper->{output}\" doesn't exist; build the site first\n" unless -d $dapper->{output};

    my %deploy = (s3 => \&s3, github_pages => \&github_pages, command => \&command);
    return $deploy{$target}->($dapper, $settings->{$target}, \%options);
}

=head2 find_command

Takes a command name and returns true if it is on the C<PATH>.

=cut

sub find_command {
    my ($name) = @_;
    return scalar grep { -x catfile($_, $name) } File::Spec->path();
}

=head2 run_command

Takes a Dapper object and a command (as a list), prints it, and runs it.
Dies if it fails.

=cut

sub run_command {
    my ($dapper, @command) = @_;

    $dapper->_log('+ ' . join(' ', map { /\s/ ? "'$_'" : $_ } @command));
    system(@command) == 0
        or die "error: " . join(' ', @command[0, 1]) . " failed (exit status " . ($? >> 8) . ")\n";
}

=head2 s3

Deploys to Amazon S3 with the AWS CLI.

=cut

sub s3 {
    my ($dapper, $settings, $options) = @_;

    die "error: deploy.s3 in $dapper->{config} needs a bucket\n"
        unless ref $settings eq 'HASH' and defined $settings->{bucket} and length $settings->{bucket};
    die "error: deploying to S3 needs the AWS CLI (https://aws.amazon.com/cli/); install it and run \"aws configure\"\n"
        unless find_command('aws');

    my @common;
    push @common, '--region', $settings->{region} if defined $settings->{region};
    push @common, '--profile', $settings->{profile} if defined $settings->{profile};

    (my $bucket = $settings->{bucket}) =~ s{^s3://}{};
    my @sync = ('aws', 's3', 'sync', $dapper->{output}, "s3://$bucket", '--delete', '--exclude', '.dapper-reload', @common);
    push @sync, '--cache-control', $settings->{cache_control} if defined $settings->{cache_control};
    push @sync, '--dryrun' if $options->{dry_run};
    run_command($dapper, @sync);

    if (defined $settings->{cloudfront}) {
        my @invalidate = ('aws', 'cloudfront', 'create-invalidation', '--distribution-id', $settings->{cloudfront},
                          '--paths', '/*', @common);
        if ($options->{dry_run}) {
            $dapper->_log('Would run: ' . join(' ', @invalidate));
        }
        else {
            run_command($dapper, @invalidate);
        }
    }

    $dapper->_log($options->{dry_run} ? "Dry run: nothing was uploaded." : "Deployed to s3://$bucket");
    return 1;
}

=head2 github_pages

Deploys to a GitHub Pages branch with git.

=cut

sub github_pages {
    my ($dapper, $settings, $options) = @_;

    $settings = {} unless ref $settings eq 'HASH';
    die "error: deploying to GitHub Pages needs git\n" unless find_command('git');

    my $repo = $settings->{repo};
    if (not defined $repo) {
        $repo = `git remote get-url origin 2>/dev/null`;
        chomp $repo;
        die "error: deploy.github_pages in $dapper->{config} needs a repo (or run dapper in a git repository with an origin)\n"
            unless length $repo;
    }
    my $branch = defined $settings->{branch} ? $settings->{branch} : 'gh-pages';
    my $output = abs_path($dapper->{output});

    my $work = tempdir(CLEANUP => 1) . '/site';

    # Start from the branch as it is, to keep its history; or a new branch
    my $cloned = system('git', 'clone', '--quiet', '--depth', '1', '--branch', $branch, '--', $repo, $work) == 0;
    if (not $cloned) {
        $dapper->_log("Starting a new $branch branch");
        run_command($dapper, 'git', 'init', '--quiet', $work);
        run_command($dapper, 'git', '-C', $work, 'checkout', '--quiet', '--orphan', $branch);
        run_command($dapper, 'git', '-C', $work, 'remote', 'add', 'origin', $repo);
    }

    # Replace the branch's files with the output
    for my $entry (App::Dapper::Utils::read_dir($work)) {
        next if $entry eq '.git';
        my $path = "$work/$entry";
        if (-d $path) { File::Path::remove_tree($path) } else { unlink $path }
    }
    for my $entry (App::Dapper::Utils::read_dir($output)) {
        next if $entry eq '.dapper-reload';
        App::Dapper::Utils::copy_recursive("$output/$entry", "$work/$entry");
    }
    App::Dapper::Utils::write_file("$work/.nojekyll", '');
    App::Dapper::Utils::write_file("$work/CNAME", "$settings->{cname}\n") if defined $settings->{cname};

    system('git', '-C', $work, 'add', '--all') == 0 or die "error: git add failed\n";
    my $changes = `git -C '$work' status --porcelain`;
    if (not length $changes) {
        $dapper->_log("Nothing changed since the last deploy to $branch.");
        return 1;
    }

    my $count = () = $changes =~ /\n/g;
    if ($options->{dry_run}) {
        $dapper->_log("Dry run: would commit $count changed file(s) to $branch of $repo:");
        $dapper->_log($changes);
        return 1;
    }

    my $name = defined $dapper->{site}->{name} ? $dapper->{site}->{name} : 'the site';
    run_command($dapper, 'git', '-C', $work, 'commit', '--quiet', '-m', "Deploy $name ($count file(s) changed)");
    run_command($dapper, 'git', '-C', $work, 'push', '--quiet', 'origin', "HEAD:$branch");

    $dapper->_log("Deployed $count changed file(s) to $branch of $repo");
    return 1;
}

=head2 command

Deploys by running a command from C<_config.yml>.

=cut

sub command {
    my ($dapper, $command, $options) = @_;

    die "error: deploy.command in $dapper->{config} must be a command to run\n"
        unless defined $command and !ref $command and length $command;

    if ($options->{dry_run}) {
        $dapper->_log("Dry run: would run: $command");
        return 1;
    }

    local $ENV{DAPPER_OUTPUT} = $dapper->{output};
    $dapper->_log("+ $command");
    system($command) == 0 or die "error: the deploy command failed (exit status " . ($? >> 8) . ")\n";
    $dapper->_log('Deployed.');
    return 1;
}

1;
