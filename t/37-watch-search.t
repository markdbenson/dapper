use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use Cwd qw(abs_path);

# A stand-in for Pagefind that records how it was called
sub fake_search_command {
    my ($exit) = @_;
    spew('bin/fake-pagefind', "#!/bin/sh\necho \"\$\@\" > search-args.txt\nexit $exit\n");
    chmod 0755, 'bin/fake-pagefind';
    return abs_path('bin/fake-pagefind');
}

subtest 'search index' => sub {
    my $site = sub {
        my ($config) = @_;
        make_site({ '_config.yml' => "---\nname: x\n$config", '_source/a.md' => "---\n---\nx\n" });
    };

    $site->("search: true\nsearch_command: PLACEHOLDER\n");
    my $cmd = fake_search_command(0);
    spew('_config.yml', "---\nname: x\nsearch: true\nsearch_command: $cmd\n");
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    is(slurp('search-args.txt'), "--site _output --quiet\n", 'the command is run over the output directory, quietly');
    is_deeply(\@warnings, [], 'no warnings');

    unlink 'search-args.txt';
    my $d = App::Dapper->new();
    my $out = '';
    {
        open(my $fh, '>', \$out) or die;
        my $old = select $fh;
        $d->build();
        select $old;
    }
    is(slurp('search-args.txt'), "--site _output\n", 'not quiet when the build is not');
    like($out, qr/^Building the search index with \Q$cmd\E$/m, 'logged');

    unlink 'search-args.txt';
    spew('_config.yml', "---\nname: x\nsearch: true\nsearch_command: $cmd --extra  arg\n");
    quiet_build();
    is(slurp('search-args.txt'), "--extra arg --site _output --quiet\n", 'search_command is split on spaces');

    $cmd = fake_search_command(3);
    spew('_config.yml', "---\nname: x\nsearch: true\nsearch_command: $cmd\n");
    @warnings = ();
    quiet_build();
    is_deeply(\@warnings, ["warning: $cmd did not finish (exit status 3)\n"], 'a failing command is a warning');

    @warnings = ();
    spew('_config.yml', "---\nname: x\nsearch: true\nsearch_command: ./no/such/pagefind\n");
    quiet_build();
    is_deeply(\@warnings, ["warning: search: true needs Pagefind; install it (see https://pagefind.app) or set search_command\n"],
        'a missing command with a path');

    @warnings = ();
    spew('_config.yml', "---\nname: x\nsearch: true\nsearch_command: dapper-no-such-command-anywhere\n");
    quiet_build();
    is(scalar @warnings, 1, 'a missing command looked up in PATH');
    like($warnings[0], qr/needs Pagefind/, 'with the same message');

    {
        local $ENV{PATH} = abs_path('bin');
        fake_search_command(0);
        rename 'bin/fake-pagefind', 'bin/pagefind' or die;
        unlink 'search-args.txt';
        @warnings = ();
        spew('_config.yml', "---\nname: x\nsearch: true\n");
        quiet_build();
        is(slurp('search-args.txt'), "--site _output --quiet\n", 'pagefind is found in PATH by default');
        is_deeply(\@warnings, [], 'without warnings');
    }

    for my $off ("search: false\nsearch_command: $cmd\n", "search_command: $cmd\n", "search: 'off'\nsearch_command: $cmd\n") {
        unlink 'search-args.txt';
        spew('_config.yml', "---\nname: x\n$off");
        quiet_build();
        ok(!-e 'search-args.txt', 'not run with ' . join(', ', split /\n/, $off));
    }

    $cmd = fake_search_command(0);
    unlink 'search-args.txt';
    spew('_config.yml', "---\nname: x\nsearch: true\nsearch_command: $cmd\n");
    $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{collect} = 1;
    $d->build();
    ok(!-e 'search-args.txt', 'not run when collecting problems');

    $d = App::Dapper->new();
    $d->{collect} = 1;
    $d->{problems} = [];
    $d->read_project();
    $d->{site}->{search} = 1;
    $d->{site}->{search_command} = '/no/such/thing';
    $d->run_search();
    is_deeply($d->{problems}, [{ severity => 'warning', file => '_config.yml',
        message => 'search: true needs Pagefind; install it (see https://pagefind.app) or set search_command' }],
        'a missing command is a collected warning');
};

{
    package My::WatchedDapper;
    our @ISA = ('App::Dapper');
    our (@snapshots, $builds, @fail);
    sub snapshot {
        die "stop watching\n" unless @snapshots;
        return shift @snapshots;
    }
    sub build {
        $builds++;
        die shift(@fail) if @fail and defined $fail[0];
        shift @fail;
        return $_[0];
    }
}

subtest 'watch' => sub {
    make_site({ '_source/a.md' => "---\n---\nx\n" });
    my $d = bless App::Dapper->new(), 'My::WatchedDapper';

    # build, unchanged, changed (build), unchanged, stop
    @My::WatchedDapper::snapshots = ({ a => 1 }, { a => 1 }, { a => 1 }, { a => 2 }, { a => 2 }, { a => 2 });
    $My::WatchedDapper::builds = 0;
    @My::WatchedDapper::fail = ();
    eval { $d->watch(0.001) };
    is($@, "stop watching\n", 'watch loops until stopped');
    is($My::WatchedDapper::builds, 2, 'builds at the start and after each change only');

    # An error in a build is printed and the watch carries on
    @My::WatchedDapper::snapshots = ({ a => 1 }, { a => 1 }, { b => 1 }, { b => 1 });
    $My::WatchedDapper::builds = 0;
    @My::WatchedDapper::fail = ("error: broken\n", undef);
    my @warnings;
    {
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        eval { $d->watch(0.001) };
    }
    is($@, "stop watching\n", 'still watching after a failed build');
    is($My::WatchedDapper::builds, 2, 'and rebuilds after the next change');
    is_deeply(\@warnings, ["error: broken\n"], 'the error is printed');
};

subtest 'watch with the default interval' => sub {
    make_site({ '_source/a.md' => "---\n---\nx\n" });
    my $d = bless App::Dapper->new(), 'My::WatchedDapper';
    @My::WatchedDapper::snapshots = ({ a => 1 }, { a => 1 });
    $My::WatchedDapper::builds = 0;
    @My::WatchedDapper::fail = ();
    eval { $d->watch() };
    is($@, "stop watching\n", 'stopped');
    is($My::WatchedDapper::builds, 1, 'built once');
};

subtest 'Perl in templates' => sub {
    make_site({ '_source/a.md' => "---\n---\nx", '_layout/index.html' => "[% PERL %]print 6*7;[% END %]" });
    {
        local $ENV{EVAL_PERL};
        delete $ENV{EVAL_PERL};
        eval { quiet_build() };
        is($@, "error: could not process _source/a.md with layout index: perl error - EVAL_PERL not set\n",
            'PERL blocks are refused by default');
        ok(!-e '_output/a.html', 'nothing written');
    }
    {
        local $ENV{EVAL_PERL} = 1;
        quiet_build();
        is(slurp('_output/a.html'), '42', 'and run with EVAL_PERL set');
    }
};

subtest 'odd files in the project' => sub {
    SKIP: {
        skip 'no symbolic links', 4 unless eval { symlink('', ''); 1 };
        make_site({ '_source/a.md' => "---\n---\nx\n" });
        symlink 'nowhere', '_source/broken.txt' or skip 'cannot make a symbolic link', 4;
        my $d = eval { quiet_build() };
        is($@, '', 'a broken link in the source directory is not an error');
        ok(!-e '_output/broken.txt' && !-l '_output/broken.txt', 'and is skipped');

        symlink 'nowhere', 'dangling';
        my @warnings;
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        eval { quiet_build() };
        is($@, '', 'a broken link at the top level is not an error');
        like(join('', @warnings), qr/^warning: dangling is a symbolic link to something that doesn't exist, so it was not copied/, 'it is skipped with a warning');
    }

    make_site({});
    mkdir '_source';
    eval { quiet_build() };
    is($@, '', 'an empty source directory builds');
    ok(!-e '_output', 'and writes nothing');

    make_site({ '_source/a.md' => "---\n---\nx\n" });
    my $snap = App::Dapper->new()->snapshot();
    is_deeply([sort keys %$snap], ['./_config.yml', './_layout/index.html', './_source/a.md'],
        'a snapshot before the output directory exists');
};

done_testing();
