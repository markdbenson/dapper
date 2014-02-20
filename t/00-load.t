#!perl -T
use 5.14.0;
use strict;
use warnings FATAL => 'all';
use Test::More;
use App::Dapper;

plan tests => 1;

BEGIN {
    use_ok( 'App::Dapper' ) || print "Bail out!\n";
}

diag( "Testing App::Dapper $App::Dapper::VERSION, Perl $], $^X" );

