package App::Dapper::Filters;

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.006;
use strict;
use warnings FATAL => 'all';

use Data::Dumper;
use CGI qw(:standard escapeHTML);

=head2 import

Called when this module is 'used' from somewhere else. This subroutine
registers Liquid filters contained in this file.

=cut

sub import {
    Template::Liquid::register_filter(qw[
        xml_escape
        date_to_xmlschema
        replace_last
        smart
    ]);
}

=head2 xml_escape

Liquid filter to escape strings into formats that can be included
in XML files.

=cut

sub xml_escape {
    my $str = shift;
    my $q = new CGI;
    return $q->escapeHTML( $str );
}

=head2 date_to_xmlschema

Convert a date to an XML-formattted version of the date that also includes
the timezone.

=cut

sub date_to_xmlschema {
    my $str = shift;
    #return $str->strftime('%Y-%m-%dT%H:%M:%S%z');

    use DateTime;
    use DateTime::Format::XSD;

    return DateTime::Format::XSD->format_datetime($str);

    #my $f = DateTime::Format::RFC3339->new();
    #return $f->format_datetime($str);
}

=head2 replace_last

Liquid filter to replace the last occurrance of a string with another string.

=cut

sub replace_last {
    my ($input, $string, $replacement) = @_;

    $replacement = defined $replacement ? $replacement : '';
    $input =~ s/^(.*)$string(.*)$/$1$replacement$2/s;
    return $input;
}

=head2 smart 

Replace dashes with mdashes and ndashes.

=cut

sub smart {
    my $input = shift;

    $input =~ s/([^-])--([^-])/$1\&ndash;$2/g;
    $input =~ s/([^-])---([^-])/$1\&mdash;$2/g;

    return $input;

    #use Text::SmartyPants;

    #my $s = Text::SmartyPants->new();
    #return $s->process($input);
}

1;
