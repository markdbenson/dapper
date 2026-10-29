package App::Dapper::Filters;

=head1 NAME

App::Dapper::Filters - Default template filters available to all projects.

=head1 DESCRIPTION

Filters contained here can be called from layout and source files using the
filter/pipe mechanism of the template language. Example:

    [% site.time | date_to_xmlschema %]

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use JSON ();
use DateTime::Format::XSD;

use App::Dapper::Utils;

=head2 filters

Returns the hash of filters in the form expected by the C<FILTERS> option of
L<Template::Alloy>. Filters that take arguments (like C<replace_last>) are
registered as dynamic filters so the arguments reach them.

=cut

sub filters {
    return {
        'xml_escape'        => \&xml_escape,
        'date_to_xmlschema' => \&date_to_xmlschema,
        'replace_last'      => [ sub {
            my ($context, @args) = @_;
            return sub { replace_last($_[0], @args) };
        }, 1 ],
        'smart'             => \&smart,
        'json'              => \&json,
    };
}

=head2 xml_escape

Escape a string so that it can be included in XML or HTML files. The
characters C<&>, C<< < >>, C<< > >>, C<"> and C<'> are replaced with entities.

=cut

my %XML_ENTITIES = (
    '&' => '&amp;',
    '<' => '&lt;',
    '>' => '&gt;',
    '"' => '&quot;',
    "'" => '&#39;',
);

sub xml_escape {
    my $str = shift;

    return '' unless defined $str;
    $str =~ s/([&<>"'])/$XML_ENTITIES{$1}/g;
    return $str;
}

=head2 date_to_xmlschema

Convert a date to an XML-formattted version of the date that also includes
the timezone. Accepts a L<DateTime> object (such as C<page.date> or
C<site.time>) or a date string.

=cut

sub date_to_xmlschema {
    my $date = shift;

    return '' unless defined $date;
    return DateTime::Format::XSD->format_datetime(App::Dapper::Utils::parse_date($date));
}

=head2 replace_last

Replace the last occurrence of a string with another string. The string is
matched literally, not as a regular expression.

    [% "a, b, c" | replace_last(", ", " and ") %]   # a, b and c

=cut

sub replace_last {
    my ($input, $string, $replacement) = @_;

    return $input unless defined $input and defined $string and length $string;

    $replacement = defined $replacement ? $replacement : '';
    my $index = rindex($input, $string);
    return $input if $index < 0;

    substr($input, $index, length $string) = $replacement;
    return $input;
}

=head2 smart

Replace C<---> with an em dash (C<&mdash;>) and C<--> with an en dash
(C<&ndash;>). Longer runs of dashes are left alone.

=cut

sub smart {
    my $input = shift;

    return '' unless defined $input;
    $input =~ s/(?<!-)---(?!-)/&mdash;/g;
    $input =~ s/(?<!-)--(?!-)/&ndash;/g;

    return $input;
}

=head2 json

Turn a variable into a pretty-printed JSON string. Useful for debugging:

    <pre>[% page | json %]</pre>

=cut

sub json {
    my $input = shift;

    my $json = JSON->new->allow_blessed->allow_nonref->pretty->canonical;
    return $json->encode($input);
}

1;
