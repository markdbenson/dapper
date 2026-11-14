#!/usr/bin/env perl

# Build dapper as a single file that runs with any Perl 5.10 or newer and
# nothing else installed: every module it uses is bundled inside it with
# App::FatPacker. Run from the top of the repository:
#
#     $ perl packaging/fatpack.pl
#
# It writes dist/dapper. It needs cpanm and network access (to fetch the
# pure-Perl versions of the dependencies into a temporary directory).

use 5.010;
use strict;
use warnings;

use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use File::Copy qw(copy);
use File::Find;
use File::Basename qw(dirname);
use Cwd qw(abs_path getcwd);

my $root = getcwd();
die "Run this from the top of the dapper repository\n" unless -f "$root/bin/dapper" and -d "$root/lib/App";

my $work = tempdir(CLEANUP => !$ENV{KEEP});
my $deps = "$work/deps";
my $tools = "$work/tools";
my $fatlib = "$work/fatlib";

sub run {
    my @command = @_;
    say "+ @command";
    system(@command) == 0 or die "failed: @command\n";
}

# 1. Fetch App::FatPacker, and the dependencies in their pure-Perl form
$ENV{PERL_CPANM_HOME} = "$work/cpanm";
run('cpanm', '--quiet', '--notest', '-L', $tools, 'App::FatPacker');
{
    local $ENV{PUREPERL_ONLY} = 1;
    local $ENV{PERL_ONLY} = 1;
    run('cpanm', '--quiet', '--notest', '--pureperl', '-L', $deps, '--installdeps', '.');
}

# 2. Bundle every module from the dependencies that is plain Perl, skipping
#    those that need compiled code (they all have pure-Perl fallbacks, or a
#    stand-in in packaging/fatpack)
my %skip = map { $_ => 1 } qw(
    Clone.pm XString.pm HTML/Parser.pm HTML/Entities.pm HTML/Filter.pm HTML/HeadParser.pm
    HTML/LinkExtor.pm HTML/PullParser.pm HTML/TokeParser.pm Specio/XS.pm
);
my $count = 0;
for my $base ("$deps/lib/perl5", glob("$deps/lib/perl5/*-*")) {
    next unless -d $base;
    find({ no_chdir => 1, wanted => sub {
        return unless /\.pm$/ and -f $_;
        (my $module = $File::Find::name) =~ s{^\Q$base\E/}{};
        return if $module =~ m{^(?:auto|darwin|x86_64|i[3-6]86|aarch64|arm)} or $module =~ m{-};
        return if $skip{$module};
        my $target = "$fatlib/$module";
        return if -e $target;
        make_path(dirname($target));
        copy($File::Find::name, $target) or die "copy $module: $!";
        $count++;
    } }, $base);
}

# Dapper itself, and the stand-ins
for my $dir ("$root/lib", "$root/packaging/fatpack") {
    find({ no_chdir => 1, wanted => sub {
        return unless /\.pm$/;
        (my $module = $File::Find::name) =~ s{^\Q$dir\E/}{};
        make_path(dirname("$fatlib/$module"));
        copy($File::Find::name, "$fatlib/$module") or die "copy $module: $!";
        $count++;
    } }, $dir);
}
say "Bundling $count modules";

# 3. Pack them into the script
make_path("$root/dist");
chdir $work or die;
copy("$root/bin/dapper", "$work/dapper") or die;
my $packed = `"$^X" -I"$tools/lib/perl5" "$tools/bin/fatpack" file dapper`;
die "fatpack failed\n" if $? or not length $packed;
chdir $root;

# Put the #! line first, and find perl on the PATH
$packed =~ s/\A(.*?)#!\/usr\/bin\/perl[^\n]*\n/#!\/usr\/bin\/env perl\n$1/s;

open(my $fh, '>', "$root/dist/dapper") or die "dist/dapper: $!";
print $fh $packed;
close $fh;
chmod 0755, "$root/dist/dapper";

printf "Wrote dist/dapper (%.1f MB)\n", (-s "$root/dist/dapper") / 1024 / 1024;
