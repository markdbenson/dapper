package DapperTest;

# Helpers for building throwaway Dapper sites in temporary directories.

use 5.010;
use strict;
use warnings;

use Exporter qw(import);
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Cwd qw(getcwd);

use App::Dapper;

our @EXPORT = qw(make_site slurp spew quiet_build);

my $ORIGINAL_DIR = getcwd();
END { chdir $ORIGINAL_DIR if defined $ORIGINAL_DIR }

# make_site(\%files) - Create a temporary directory, write each file into it
# (keys are relative paths, values are contents), chdir into it, and return
# the directory. A minimal _config.yml and index layout are added unless
# given.
sub make_site {
    my ($files, %opts) = @_;

    my $dir = tempdir(CLEANUP => 1);
    chdir $dir or die "could not chdir to $dir: $!";

    my %all = %$files;
    unless ($opts{bare}) {
        $all{'_config.yml'} = "---\nname: Test Site\n" unless exists $all{'_config.yml'};
        $all{'_layout/index.html'} = "<title>[% page.title %]</title>\n[% page.content %]"
            unless exists $all{'_layout/index.html'};
    }

    for my $path (keys %all) {
        spew($path, $all{$path});
    }

    return $dir;
}

sub spew {
    my ($path, $content, $layer) = @_;
    $layer = ':encoding(UTF-8)' unless defined $layer;
    my $dir = dirname($path);
    make_path($dir) unless -d $dir;
    open(my $fh, ">$layer", $path) or die "could not write $path: $!";
    print $fh $content;
    close $fh;
}

sub slurp {
    my ($path, $layer) = @_;
    $layer = ':encoding(UTF-8)' unless defined $layer;
    open(my $fh, "<$layer", $path) or return undef;
    local $/;
    my $content = <$fh>;
    close $fh;
    return $content;
}

# quiet_build(@new_args) - Build the site in the current directory without
# progress output and return the Dapper object.
sub quiet_build {
    my $d = App::Dapper->new(@_);
    $d->{quiet} = 1;
    $d->build();
    return $d;
}

1;
