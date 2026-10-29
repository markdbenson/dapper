use 5.010;
use strict;
use warnings;
use Test::More;

my @modules = qw(
    App::Dapper
    App::Dapper::Check
    App::Dapper::Collections
    App::Dapper::Defaults
    App::Dapper::Filters
    App::Dapper::Init
    App::Dapper::Markdown
    App::Dapper::MCP
    App::Dapper::Publish
    App::Dapper::Schema
    App::Dapper::Utils
);

plan tests => scalar @modules;

for my $module (@modules) {
    use_ok($module) || print "Bail out!\n";
}

diag( "Testing App::Dapper $App::Dapper::VERSION, Perl $], $^X" );
