#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'App::Dapper' ) || print "Bail out!\n";
}

diag( "Testing App::Dapper $App::Dapper::VERSION, Perl $], $^X" );

