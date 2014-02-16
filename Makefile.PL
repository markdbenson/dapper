use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'App::Dapper',
    AUTHOR           => q{Mark Benson <markbenson@vanilladraft.com>},
    VERSION_FROM     => 'lib/App/Dapper.pm',
    ABSTRACT_FROM    => 'lib/App/Dapper.pm',
    LICENSE          => 'mit',
    PL_FILES         => {},
    EXE_FILES         => ['bin/dapper'],
    MIN_PERL_VERSION => 5.006,
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
        'FindBin'               => 0,
        'Pod::Usage'            => 0,
        'HTTP::Server::Brick'   => 0,
        'Getopt::Mixed'         => 0,
        'IO::Dir'               => 0,
        'File::Spec::Functions' => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'App-Dapper-*' },
);

