package App::Dapper::Schema;

=head1 NAME

App::Dapper::Schema - Check front matter against a C<_schema.yml> file.

=head1 DESCRIPTION

A C<_schema.yml> file in a source directory describes the front matter that
pages in that directory (and the directories below it, unless they have a
schema of their own) must have. For example:

    required: [title, date]
    fields:
      title:
        type: string
        max_length: 70
      date:
        type: date
      categories:
        type: list
        values: [blog, notes]
      description:
        type: string
        max_length: 160
      draft:
        type: boolean
    additional: true

C<required> lists the fields every page must set. C<fields> describes each
field:

    type        string, number, integer, boolean, date, list, map or any
    values      the allowed values (for a list: the allowed items)
    pattern     a regular expression a string must match
    min_length, max_length   limits on the length of a string
    min, max    limits on a number

C<additional: false> makes any field not listed in C<fields> an error.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use Scalar::Util qw/ looks_like_number blessed /;
use YAML::PP qw/ LoadFile /;

use App::Dapper::Utils;

my %TYPES = map { $_ => 1 } qw/ string number integer boolean date list map any /;
my %RULES = map { $_ => 1 } qw/ type values pattern min_length max_length min max /;

=head2 load

Takes the path of a schema file, reads it, checks that it is a valid schema,
and returns it. Dies with a message naming the file if it is not.

=cut

sub load {
    my ($file) = @_;

    my $schema = eval { LoadFile($file) };
    die "error: could not parse the schema \"$file\": $@" if $@;
    $schema = {} unless defined $schema;
    die "error: the schema \"$file\" must contain key: value pairs\n" unless ref $schema eq 'HASH';

    my @problems;

    for my $key (sort keys %$schema) {
        push @problems, "unknown setting \"$key\" (use required, fields or additional)"
            unless $key =~ /^(?:required|fields|additional)$/;
    }

    my $required = $schema->{required};
    $required = [] unless defined $required;
    $required = [$required] unless ref $required;
    push @problems, "\"required\" must be a list of field names" unless ref $required eq 'ARRAY';
    $schema->{required} = $required;

    my $fields = $schema->{fields};
    $fields = {} unless defined $fields;
    push @problems, "\"fields\" must be a set of field names" unless ref $fields eq 'HASH';
    $schema->{fields} = ref $fields eq 'HASH' ? $fields : {};

    for my $name (sort keys %{$schema->{fields}}) {
        my $rules = $schema->{fields}->{$name};
        $rules = { type => $rules } if defined $rules and not ref $rules;
        $rules = {} unless defined $rules;
        if (ref $rules ne 'HASH') {
            push @problems, "the rules for \"$name\" must be a set of key: value pairs";
            next;
        }
        $schema->{fields}->{$name} = $rules;

        $rules->{type} = 'any' unless defined $rules->{type};
        push @problems, "\"$name\" has the unknown type \"$rules->{type}\" (use " . join(', ', sort keys %TYPES) . ")"
            unless $TYPES{$rules->{type}};

        for my $rule (sort keys %$rules) {
            push @problems, "\"$name\" has the unknown rule \"$rule\"" unless $RULES{$rule};
        }

        if (defined $rules->{values}) {
            $rules->{values} = [$rules->{values}] unless ref $rules->{values};
            push @problems, "\"values\" for \"$name\" must be a list" unless ref $rules->{values} eq 'ARRAY';
        }

        if (defined $rules->{pattern}) {
            my $pattern = $rules->{pattern};
            push @problems, "the pattern for \"$name\" is not a valid regular expression"
                unless eval { qr/$pattern/; 1 };
        }
    }

    $schema->{additional} = 1 unless defined $schema->{additional};

    die "error: the schema \"$file\" has problems:\n" . join('', map { "  $_\n" } @problems) if @problems;

    $schema->{file} = $file;
    return $schema;
}

=head2 validate

Takes a schema (from L</load>) and a hash of front matter, and returns a list
of messages describing every way the front matter does not match the schema.
An empty list means it matches.

=cut

sub validate {
    my ($schema, $frontmatter) = @_;

    my @problems;

    for my $name (@{$schema->{required}}) {
        push @problems, "\"$name\" is required"
            unless defined $frontmatter->{$name} and (ref $frontmatter->{$name} or length $frontmatter->{$name});
    }

    for my $name (sort keys %$frontmatter) {
        my $rules = $schema->{fields}->{$name};
        if (not $rules) {
            push @problems, "\"$name\" is not one of the fields in the schema" unless $schema->{additional};
            next;
        }
        next unless defined $frontmatter->{$name};
        push @problems, check_value($name, $frontmatter->{$name}, $rules);
    }

    return @problems;
}

=head2 check_value

Takes a field name, its value and its rules, and returns a list of messages
for each rule the value breaks.

=cut

sub check_value {
    my ($name, $value, $rules) = @_;

    my $type = $rules->{type};

    if ($type eq 'list') {
        my @items = ref $value eq 'ARRAY' ? @$value : ref $value ? () : ($value);
        return "\"$name\" must be a list" if ref $value and ref $value ne 'ARRAY';
        my @problems;
        if ($rules->{values}) {
            my %allowed = map { $_ => 1 } @{$rules->{values}};
            for my $item (@items) {
                push @problems, "\"$name\" has \"$item\", which is not one of: " . join(', ', @{$rules->{values}})
                    unless defined $item and $allowed{$item};
            }
        }
        return @problems;
    }

    if ($type eq 'map') {
        return ref $value eq 'HASH' ? () : "\"$name\" must be a set of key: value pairs";
    }

    if ($type eq 'boolean') {
        return () if is_boolean($value);
        return "\"$name\" must be true or false";
    }

    return () if $type eq 'any';

    return "\"$name\" must be a single value, not a list or a set" if ref $value;

    my @problems;

    if ($type eq 'number') {
        return "\"$name\" must be a number" unless looks_like_number($value);
    }
    elsif ($type eq 'integer') {
        return "\"$name\" must be a whole number" unless $value =~ /^-?\d+$/;
    }
    elsif ($type eq 'date') {
        return "\"$name\" must be a date, e.g. 2014-05-02T10:30:00"
            unless eval { App::Dapper::Utils::parse_date($value); 1 };
    }

    if ($type eq 'number' or $type eq 'integer') {
        push @problems, "\"$name\" is $value; the smallest allowed is $rules->{min}"
            if defined $rules->{min} and $value < $rules->{min};
        push @problems, "\"$name\" is $value; the largest allowed is $rules->{max}"
            if defined $rules->{max} and $value > $rules->{max};
    }

    if ($type eq 'string') {
        my $length = length $value;
        push @problems, "\"$name\" is $length characters long; the fewest allowed is $rules->{min_length}"
            if defined $rules->{min_length} and $length < $rules->{min_length};
        push @problems, "\"$name\" is $length characters long; the most allowed is $rules->{max_length}"
            if defined $rules->{max_length} and $length > $rules->{max_length};
        if (defined $rules->{pattern}) {
            my $pattern = $rules->{pattern};
            push @problems, "\"$name\" does not match the pattern $pattern" unless $value =~ /$pattern/;
        }
    }

    if ($rules->{values}) {
        my %allowed = map { $_ => 1 } @{$rules->{values}};
        push @problems, "\"$name\" is \"$value\", which is not one of: " . join(', ', @{$rules->{values}})
            unless $allowed{$value};
    }

    return @problems;
}

=head2 is_boolean

Returns true if a value is a YAML or JSON boolean, or one of 1, 0, the empty
string, "true" or "false".

=cut

sub is_boolean {
    my ($value) = @_;

    return 1 if blessed($value) and ($value->isa('JSON::PP::Boolean') or $value->isa('boolean'));
    return 0 if ref $value;
    return $value =~ /^(?:1|0|true|false|)$/i ? 1 : 0;
}

1;
