package App::Dapper::Filters;

=head1 NAME

App::Dapper::Filters - Default Liquid filters available to all projects.

=head1 DESCRIPTION

Filters contained here can be called from Liquid template files using
the filter/pipe mechanism built in to Liquid. Example:

    {{ site.time | date_to_xmlschema }}

=cut

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.8.0;
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
        json
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

    use DateTime;
    use DateTime::Format::XSD;

    return DateTime::Format::XSD->format_datetime($str);
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
}

=head2 json

Turn string into json-formatted string.

=cut 

use JSON;
sub json {
    my $input = shift;

    my $flags = {
        allow_blessed => 1,
        allow_barekey => 1,
        allow_nonref => 1,
        utf8 => 1,
        pretty => 1
    };

    return to_json($input, $flags);
}

1;
