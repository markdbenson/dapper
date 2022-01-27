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

use base qw(HTTP::Server::Simple::CGI);
use HTTP::Server::Simple::Static;

=head2 handle_request

Handle a CGI request

=cut

my $webroot = '.';
my $dirindex = 'index.html';
 
sub handle_request {
    my ($self, $cgi) = @_;

    print "HTTP/1.0 200 OK\r\n";
    print $cgi->header,
	  $cgi->start_html('Debug'),
          $cgi->h1("Path: $cgi->path()\n"),
          dumper_html($cgi),
	  $cgi->end_html;

    #$webroot =~ s/(.*\/)$/$1$dirindex/;

    if (!$self->serve_static($cgi, $webroot)) {
        print "HTTP/1.0 404 Not found\r\n";
        print $cgi->header, 
              $cgi->start_html('Not found'),
              $cgi->h1('Not found'),
              $cgi->h1($webroot),
              $cgi->end_html;
    }
} 

sub kyloren {
    my ($self, $path) = @_;

    $webroot = $path;
    print "Webroot is: " . $webroot . "\n";
}

1;
