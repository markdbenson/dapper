use 5.010;
use strict;
use warnings;
use Test::More;

unless ( $ENV{RELEASE_TESTING} ) {
    plan( skip_all => "Author tests not required for installation" );
}

eval "use Test::Pod 1.22";
plan skip_all => "Test::Pod 1.22 required for testing POD" if $@;

all_pod_files_ok();
