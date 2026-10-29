use 5.010;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'App::Dapper',
    AUTHOR           => q{Mark Benson <mark@jayber.org>},
    VERSION_FROM     => 'lib/App/Dapper.pm',
    ABSTRACT_FROM    => 'lib/App/Dapper.pm',
    LICENSE          => 'mit',
    PL_FILES         => {},
    EXE_FILES        => ['bin/dapper'],
    MIN_PERL_VERSION => '5.010',
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => '6.64',
    },
    TEST_REQUIRES => {
        'File::Temp'                   => 0,
        'Test::More'                   => '0.98',
    },
    PREREQ_PM => {
        'Cwd'                          => 0,
        'DateTime'                     => '1.52',
        'DateTime::Format::XSD'        => 0,
        'DateTime::TimeZone'           => 0,
        'Exporter'                     => 0,
        'File::Basename'               => 0,
        'File::Copy'                   => 0,
        'File::Find'                   => 0,
        'File::Path'                   => 0,
        'File::Spec'                   => 0,
        'File::Spec::Functions'        => 0,
        'FindBin'                      => 0,
        'Getopt::Long'                 => 0,
        'JSON'                         => 0,
        'Net::HTTPServer'              => 0,
        'POSIX'                        => 0,
        'Pod::Usage'                   => 0,
        'Template::Alloy'              => 0,
        'Text::MultiMarkdown'          => 0,
        'Unicode::Normalize'           => 0,
        'YAML::PP'                     => 0,
    },
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url  => 'https://github.com/markdbenson/dapper.git',
                web  => 'https://github.com/markdbenson/dapper',
            },
            bugtracker => {
                web => 'https://github.com/markdbenson/dapper/issues',
            },
        },
        prereqs => {
            develop => {
                requires => {
                    'Test::Pod' => '1.22',
                },
            },
        },
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'App-Dapper-* distcheck.log' },
);
