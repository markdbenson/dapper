package App::Dapper::Filters;

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.006;
use strict;
use warnings FATAL => 'all';

use Data::Dumper;
use CGI qw(:standard escapeHTML);

sub import {
    Template::Liquid::register_filter(qw[
        xml_escape
        date_to_xmlschema
        replace_last
        smart
    ]);
}

sub xml_escape {
    my $str = shift;
    my $q = new CGI;
    return $q->escapeHTML( $str );
}

sub date_to_xmlschema {
    my $str = shift;
    #return $str->strftime('%Y-%m-%dT%H:%M:%S%z');

    use DateTime;
    use DateTime::Format::XSD;

    return DateTime::Format::XSD->format_datetime($str);

    #my $f = DateTime::Format::RFC3339->new();
    #return $f->format_datetime($str);
}

sub replace_last {
    my ($input, $string, $replacement) = @_;

    $replacement = defined $replacement ? $replacement : '';
    $input =~ s/^(.*)$string(.*)$/$1$replacement$2/s;
    return $input;
}

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
