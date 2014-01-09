use 5.006;
use strict;
use warnings FATAL => 'all';
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Text::Dapper',
    AUTHOR           => q{Mark Benson <markbenson@vanilladraft.com>},
    VERSION_FROM     => 'lib/Text/Dapper.pm',
    ABSTRACT_FROM    => 'lib/Text/Dapper.pm',
    LICENSE          => 'Artistic_2_0',
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
    clean => { FILES => 'Text-Dapper-*' },
);

