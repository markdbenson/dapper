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
    MIN_PERL_VERSION => '5.14.0',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 6.88,
    },
    CONFIGURE_REQUIRES => {
        'Getopt::Mixed'         => 1.11,
    },
    BUILD_REQUIRES => {
        'Test::More'            => 0.98,
    },
    PREREQ_PM => {
        'CGI'                   => 0,
        'Data::Dumper'          => 0,
        'DateTime'              => 0,
        'DateTime::Format::XSD' => 0,
        'Exporter'              => 0,
        'ExtUtils::MakeMaker'   => 0,
        'File::Find'            => 0,
        'File::Monitor'         => 0,
        'File::Path'            => 0,
        'File::Spec::Functions' => 0,
        'FindBin'               => 0,
        'Getopt::Mixed'         => 0,
        'HTTP::Server::Brick'   => 0,
        'IO::Dir'               => 0,
        'POSIX'                 => 0,
        'Pod::Usage'            => 0,
        'Template::Liquid'      => 0,
        'Test::More'            => 0,
        'Test'                  => 0,
        'Text::Markdown'        => 0,
        'Text::MultiMarkdown'   => 0,
        'Unicode::Normalize'    => 0,
        'YAML::Tiny'            => 0,
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'App-Dapper-*' },
);

