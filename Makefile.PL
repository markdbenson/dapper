use 5.010;
use strict;
use warnings;
use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
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
        'File::Temp'                   => 0,
        'FindBin'                      => 0,
        'Getopt::Long'                 => 0,
        'IO::Handle'                   => 0,
        'JSON'                         => 0,
        'Net::HTTPServer'              => 0,
        'POSIX'                        => 0,
        'Pod::Usage'                   => 0,
        'Scalar::Util'                 => 0,
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
    },
    dist  => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean => { FILES => 'App-Dapper-* distcheck.log' },
);

# Older versions of ExtUtils::MakeMaker (such as those bundled with Perl 5.10
# to 5.16) do not understand some of the arguments above.
unless (eval { ExtUtils::MakeMaker->VERSION('6.64') }) {
    my $test_requires = delete $WriteMakefileArgs{TEST_REQUIRES};
    @{ $WriteMakefileArgs{PREREQ_PM} }{ keys %$test_requires } = values %$test_requires;
}
delete $WriteMakefileArgs{CONFIGURE_REQUIRES} unless eval { ExtUtils::MakeMaker->VERSION('6.52') };
delete $WriteMakefileArgs{MIN_PERL_VERSION}   unless eval { ExtUtils::MakeMaker->VERSION('6.48') };
# Before 6.68, a meta-spec 2 META_MERGE replaces the prerequisites in MYMETA.
delete $WriteMakefileArgs{META_MERGE}         unless eval { ExtUtils::MakeMaker->VERSION('6.68') };

WriteMakefile(%WriteMakefileArgs);
