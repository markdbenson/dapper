package App::Dapper::Serve;

=head1 NAME

App::Dapper::Serve - Simple threaded webserver that serves static files

=cut

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.8.0;
use strict;
use warnings FATAL => 'all';

use POSIX;
use Unicode::Normalize;

use Data::Dumper::HTML qw(dumper_html);

my $webroot = '.';
my $dirindex = 'index.html';
 
sub kyloren {
    my ($self, $path) = @_;

    $webroot = $path;
    print "Webroot is: " . $webroot . "\n";
}

1;
