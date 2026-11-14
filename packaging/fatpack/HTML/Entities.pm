package HTML::Entities;

# A pure-Perl stand-in for HTML::Entities, bundled only in the single-file
# build of dapper. Text::MultiMarkdown loads HTML::Entities for
# encode_entities, but the real module needs HTML::Parser, which is compiled
# C and can't be bundled. The single file looks for its bundled modules after
# the installed ones, so where HTML::Entities is installed, the real one is
# used instead.

use strict;
use warnings;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(encode_entities decode_entities);
our $VERSION = '0';

my %char2entity = ('&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', "'" => '&#39;');
my %entity2char = reverse %char2entity;

sub encode_entities {
    my ($text, $unsafe) = @_;
    return undef unless defined $text;
    my $class = defined $unsafe ? qr/[$unsafe]/ : qr/[&<>"']/;
    (my $copy = $text) =~ s/($class)/exists $char2entity{$1} ? $char2entity{$1} : sprintf('&#x%X;', ord $1)/ge;
    $_[0] = $copy if !defined wantarray;
    return $copy;
}

sub decode_entities {
    my ($text) = @_;
    return undef unless defined $text;
    (my $copy = $text) =~ s/(&(?:amp|lt|gt|quot|#39);|&#(\d+);|&#x([0-9a-fA-F]+);)/
        defined $2 ? chr($2) : defined $3 ? chr(hex $3) : $entity2char{$1}/ge;
    $_[0] = $copy if !defined wantarray;
    return $copy;
}

1;
