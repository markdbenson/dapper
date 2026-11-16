use 5.010;
use strict;
use warnings;
use Test::More;
use JSON ();

use lib 't/lib';
use DapperTest;
use App::Dapper::Schema;

# Unit tests for App::Dapper::Schema: load, validate, check_value and
# is_boolean, with every rule and every message.

make_site({});

sub load_yaml {
    my ($yaml) = @_;
    spew('schema.yml', $yaml);
    my $schema = eval { App::Dapper::Schema::load('schema.yml') };
    return ($schema, $@);
}

sub problems_of {
    my ($error) = @_;
    my @lines = split /\n/, $error;
    shift @lines;
    s/^  // for @lines;
    return \@lines;
}

sub v {
    my ($schema_yaml, $frontmatter) = @_;
    my ($schema, $error) = load_yaml($schema_yaml);
    die $error if $error;
    return [ App::Dapper::Schema::validate($schema, $frontmatter) ];
}

sub cv {
    my ($value, %rules) = @_;
    return [ App::Dapper::Schema::check_value('f', $value, \%rules) ];
}

subtest 'load: files that cannot be used at all' => sub {
    my ($schema, $error) = load_yaml("required: [a\n");
    ok(!defined $schema, 'nothing returned');
    like($error, qr/\Aerror: could not parse the schema "schema\.yml": /, 'parse error names the file');

    ($schema, $error) = load_yaml("- a\n- b\n");
    is($error, qq{error: the schema "schema.yml" must contain key: value pairs\n}, 'a list is not a schema');

    ($schema, $error) = load_yaml("just a string\n");
    is($error, qq{error: the schema "schema.yml" must contain key: value pairs\n}, 'a string is not a schema');

    ok(!eval { App::Dapper::Schema::load('no-such-schema.yml'); 1 }, 'a missing file dies');
    like($@, qr/\Aerror: could not parse the schema "no-such-schema\.yml": /, 'and names it');
};

subtest 'load: an empty file is an empty schema' => sub {
    my ($schema, $error) = load_yaml('');
    is($error, '', 'no error');
    is_deeply($schema, { required => [], fields => {}, additional => 1, file => 'schema.yml' }, 'defaults filled in');

    ($schema, $error) = load_yaml("---\n");
    is_deeply($schema, { required => [], fields => {}, additional => 1, file => 'schema.yml' }, 'a document marker alone');
};

subtest 'load: normalizing what is given' => sub {
    my ($schema) = load_yaml("required: title\n");
    is_deeply($schema->{required}, ['title'], 'a single required name becomes a list');

    ($schema) = load_yaml("required: [title, date]\n");
    is_deeply($schema->{required}, ['title', 'date'], 'a list is kept in order');

    ($schema) = load_yaml("fields:\n  title: string\n  body:\n  n:\n    max: 3\n");
    is_deeply($schema->{fields}->{title}, { type => 'string' }, 'a bare type name becomes { type => ... }');
    is_deeply($schema->{fields}->{body}, { type => 'any' }, 'a field with no rules is any');
    is_deeply($schema->{fields}->{n}, { type => 'any', max => 3 }, 'a missing type defaults to any');

    ($schema) = load_yaml("fields:\n  c:\n    type: list\n    values: blog\n");
    is_deeply($schema->{fields}->{c}->{values}, ['blog'], 'a single allowed value becomes a list');

    ($schema) = load_yaml("additional: false\n");
    ok(!$schema->{additional}, 'additional: false is kept');
    ($schema) = load_yaml("additional: true\n");
    ok($schema->{additional}, 'additional: true is kept');
    is($schema->{file}, 'schema.yml', 'file recorded');
};

subtest 'load: every type is accepted' => sub {
    for my $type (qw/ string number integer boolean date list map any /) {
        my ($schema, $error) = load_yaml("fields:\n  f:\n    type: $type\n");
        is($error, '', "type $type");
    }
};

subtest 'load: every rule is accepted' => sub {
    my ($schema, $error) = load_yaml(
        "fields:\n  f:\n    type: string\n    values: [a]\n    pattern: '^a\$'\n    min_length: 1\n    max_length: 2\n    min: 0\n    max: 9\n");
    is($error, '', 'type, values, pattern, min_length, max_length, min and max');
};

subtest 'load: each problem has its own message, and all are reported at once' => sub {
    my ($schema, $error) = load_yaml("requires: [x]\nextra: 1\n");
    is_deeply(problems_of($error), [
        'unknown setting "extra" (use required, fields or additional)',
        'unknown setting "requires" (use required, fields or additional)',
    ], 'unknown top-level settings, sorted');
    like($error, qr/\Aerror: the schema "schema\.yml" has problems:\n/, 'first line names the file');

    ($schema, $error) = load_yaml("required:\n  a: 1\n");
    is_deeply(problems_of($error), ['"required" must be a list of field names'], 'required as a map');

    ($schema, $error) = load_yaml("fields: [title]\n");
    is_deeply(problems_of($error), ['"fields" must be a set of field names'], 'fields as a list');

    ($schema, $error) = load_yaml("fields: title\n");
    is_deeply(problems_of($error), ['"fields" must be a set of field names'], 'fields as a string');

    ($schema, $error) = load_yaml("fields:\n  title: [string]\n");
    is_deeply(problems_of($error), ['the rules for "title" must be a set of key: value pairs'], 'rules as a list');

    ($schema, $error) = load_yaml("fields:\n  title:\n    type: text\n");
    is_deeply(problems_of($error),
        ['"title" has the unknown type "text" (use any, boolean, date, integer, list, map, number, string)'],
        'unknown type lists the known ones, sorted');

    ($schema, $error) = load_yaml("fields:\n  title: text\n");
    is_deeply(problems_of($error),
        ['"title" has the unknown type "text" (use any, boolean, date, integer, list, map, number, string)'],
        'a bare unknown type');

    ($schema, $error) = load_yaml("fields:\n  title:\n    maximum: 3\n    minimum: 1\n");
    is_deeply(problems_of($error), [
        '"title" has the unknown rule "maximum"',
        '"title" has the unknown rule "minimum"',
    ], 'unknown rules, sorted');

    ($schema, $error) = load_yaml("fields:\n  c:\n    values:\n      a: 1\n");
    is_deeply(problems_of($error), ['"values" for "c" must be a list'], 'values as a map');

    ($schema, $error) = load_yaml("fields:\n  s:\n    pattern: '(unclosed'\n");
    is_deeply(problems_of($error), ['the pattern for "s" is not a valid regular expression'], 'bad pattern');

    ($schema, $error) = load_yaml(
        "zzz: 1\nrequired: {a: 1}\nfields:\n  b: [x]\n  a:\n    type: nope\n    pattern: '['\n    bogus: 1\n");
    is_deeply(problems_of($error), [
        'unknown setting "zzz" (use required, fields or additional)',
        '"required" must be a list of field names',
        '"a" has the unknown type "nope" (use any, boolean, date, integer, list, map, number, string)',
        '"a" has the unknown rule "bogus"',
        'the pattern for "a" is not a valid regular expression',
        'the rules for "b" must be a set of key: value pairs',
    ], 'every problem, in order: settings, required, fields, then each field sorted');
    like($error, qr/\n\z/, 'ends with a newline');
};

subtest 'validate: required' => sub {
    my $yaml = "required: [title, date]\n";
    is_deeply(v($yaml, { title => 'T', date => '2020-01-01' }), [], 'all present');
    is_deeply(v($yaml, {}), ['"title" is required', '"date" is required'], 'all missing, in the order listed');
    is_deeply(v($yaml, { title => '', date => undef }), ['"title" is required', '"date" is required'], 'empty and undef count as missing');
    is_deeply(v($yaml, { title => 0, date => '0' }), [], '0 counts as present');
    is_deeply(v($yaml, { title => [], date => {} }), [], 'an empty list or map counts as present');
    is_deeply(v("required: [title]\n", { title => ' ' }), [], 'a space counts as present');
};

subtest 'validate: additional' => sub {
    my $open   = "fields:\n  title: string\n";
    my $closed = "fields:\n  title: string\nadditional: false\n";
    is_deeply(v($open, { title => 'T', colour => 'blue' }), [], 'extra fields allowed by default');
    is_deeply(v($closed, { title => 'T', zeta => 1, alpha => 2 }), [
        '"alpha" is not one of the fields in the schema',
        '"zeta" is not one of the fields in the schema',
    ], 'additional: false rejects each extra field, sorted');
    is_deeply(v($closed, { title => 'T', extra => undef }), ['"extra" is not one of the fields in the schema'],
        'even when its value is empty');
};

subtest 'validate: undefined values skip the field rules' => sub {
    is_deeply(v("fields:\n  n: integer\n", { n => undef }), [], 'undef is not checked against the type');
};

subtest 'validate: reports every problem at once, in a stable order' => sub {
    my $yaml = "required: [title, date]\nfields:\n  title:\n    type: string\n    max_length: 3\n  rating:\n    type: integer\n    max: 5\n  draft: boolean\nadditional: false\n";
    is_deeply(v($yaml, { title => 'Too long', rating => 9, draft => 'maybe', other => 1 }), [
        '"date" is required',
        '"draft" must be true or false',
        '"other" is not one of the fields in the schema',
        '"rating" is 9; the largest allowed is 5',
        '"title" is 8 characters long; the most allowed is 3',
    ], 'required first, then each field sorted by name');
};

subtest 'check_value: string' => sub {
    is_deeply(cv('abc', type => 'string'), [], 'a string');
    is_deeply(cv(42, type => 'string'), [], 'a number is fine as a string');
    is_deeply(cv(['a'], type => 'string'), ['"f" must be a single value, not a list or a set'], 'a list');
    is_deeply(cv({ a => 1 }, type => 'string'), ['"f" must be a single value, not a list or a set'], 'a map');
    is_deeply(cv('ab', type => 'string', min_length => 3), ['"f" is 2 characters long; the fewest allowed is 3'], 'min_length');
    is_deeply(cv('abc', type => 'string', min_length => 3), [], 'min_length is inclusive');
    is_deeply(cv('abcd', type => 'string', max_length => 3), ['"f" is 4 characters long; the most allowed is 3'], 'max_length');
    is_deeply(cv('abc', type => 'string', max_length => 3), [], 'max_length is inclusive');
    is_deeply(cv("\x{e9}t\x{e9}", type => 'string', max_length => 3), [], 'length counts characters, not bytes');
    is_deeply(cv('', type => 'string', min_length => 1), ['"f" is 0 characters long; the fewest allowed is 1'], 'empty string');
    is_deeply(cv('Not_Valid', type => 'string', pattern => '^[a-z-]+$'), ['"f" does not match the pattern ^[a-z-]+$'], 'pattern');
    is_deeply(cv('fine-slug', type => 'string', pattern => '^[a-z-]+$'), [], 'pattern matches');
    is_deeply(cv('xx-abc-xx', type => 'string', pattern => 'abc'), [], 'a pattern is not anchored unless it says so');
    is_deeply(cv('ABCDEF', type => 'string', max_length => 3, pattern => '^[a-z]+$', values => ['x']), [
        '"f" is 6 characters long; the most allowed is 3',
        '"f" does not match the pattern ^[a-z]+$',
        '"f" is "ABCDEF", which is not one of: x',
    ], 'every broken rule is reported, in order');
};

subtest 'check_value: values' => sub {
    is_deeply(cv('draft', type => 'string', values => ['draft', 'live']), [], 'allowed');
    is_deeply(cv('gone', type => 'string', values => ['draft', 'live']), ['"f" is "gone", which is not one of: draft, live'], 'not allowed');
    is_deeply(cv('Draft', type => 'string', values => ['draft']), ['"f" is "Draft", which is not one of: draft'], 'case matters');
    is_deeply(cv(2, type => 'integer', values => [1, 2, 3]), [], 'numbers');
    is_deeply(cv(4, type => 'integer', values => [1, 2, 3]), ['"f" is "4", which is not one of: 1, 2, 3'], 'numbers not allowed');
    is_deeply(cv('x', type => 'any', values => ['a']), [], 'any ignores values');
};

subtest 'check_value: number' => sub {
    is_deeply(cv(3.5, type => 'number'), [], 'a decimal');
    is_deeply(cv('-2', type => 'number'), [], 'a negative number as a string');
    is_deeply(cv('1e3', type => 'number'), [], 'exponent notation');
    is_deeply(cv('three', type => 'number'), ['"f" must be a number'], 'a word');
    is_deeply(cv('', type => 'number'), ['"f" must be a number'], 'empty');
    is_deeply(cv([1], type => 'number'), ['"f" must be a single value, not a list or a set'], 'a list');
    is_deeply(cv(0.5, type => 'number', min => 1), ['"f" is 0.5; the smallest allowed is 1'], 'min');
    is_deeply(cv(1, type => 'number', min => 1, max => 1), [], 'min and max are inclusive');
    is_deeply(cv(10.25, type => 'number', max => 10), ['"f" is 10.25; the largest allowed is 10'], 'max');
    is_deeply(cv('three', type => 'number', min => 5), ['"f" must be a number'], 'a non-number stops before the limits');
    is_deeply(cv(-1, type => 'number', min => 0), ['"f" is -1; the smallest allowed is 0'], 'a minimum of 0');
};

subtest 'check_value: integer' => sub {
    is_deeply(cv(7, type => 'integer'), [], 'a whole number');
    is_deeply(cv('-7', type => 'integer'), [], 'a negative whole number');
    is_deeply(cv('007', type => 'integer'), [], 'leading zeros');
    is_deeply(cv(7.5, type => 'integer'), ['"f" must be a whole number'], 'a decimal');
    is_deeply(cv('+7', type => 'integer'), ['"f" must be a whole number'], 'a plus sign');
    is_deeply(cv('1e3', type => 'integer'), ['"f" must be a whole number'], 'exponent notation');
    is_deeply(cv('seven', type => 'integer'), ['"f" must be a whole number'], 'a word');
    is_deeply(cv(0, type => 'integer', min => 1), ['"f" is 0; the smallest allowed is 1'], 'min');
    is_deeply(cv(6, type => 'integer', max => 5), ['"f" is 6; the largest allowed is 5'], 'max');
    is_deeply(cv(6, type => 'integer', min_length => 3, pattern => 'x'), [], 'string rules do not apply to numbers');
};

subtest 'check_value: boolean' => sub {
    for my $value (1, 0, '', 'true', 'false', 'TRUE', 'False', JSON::true, JSON::false) {
        my $label = ref $value ? 'JSON ' . ($value ? 'true' : 'false') : "'$value'";
        is_deeply(cv($value, type => 'boolean'), [], "$label is a boolean");
    }
    for my $value ('yes', 'no', 'maybe', 2, 'on', ' true') {
        is_deeply(cv($value, type => 'boolean'), ['"f" must be true or false'], "'$value' is not a boolean");
    }
    is_deeply(cv([1], type => 'boolean'), ['"f" must be true or false'], 'a list is not a boolean');
    is_deeply(cv('x', type => 'boolean', values => ['y']), ['"f" must be true or false'], 'values are not checked for booleans');
};

subtest 'check_value: date' => sub {
    is_deeply(cv('2020-01-01', type => 'date'), [], 'a day');
    is_deeply(cv('2020-01-01T10:30:00', type => 'date'), [], 'a time');
    is_deeply(cv('2020-01-01T10:30', type => 'date'), [], 'a time without seconds');
    is_deeply(cv('2020-01-01 10:30:00', type => 'date'), [], 'a space instead of T');
    is_deeply(cv('2020-01-01T10:30:00-05:00', type => 'date'), [], 'a time zone');
    is_deeply(cv('2020-01-01T10:30:00Z', type => 'date'), [], 'UTC');
    is_deeply(cv('someday', type => 'date'), ['"f" must be a date, e.g. 2014-05-02T10:30:00'], 'a word');
    is_deeply(cv('01/02/2020', type => 'date'), ['"f" must be a date, e.g. 2014-05-02T10:30:00'], 'a US date');
    is_deeply(cv('2020-13-01', type => 'date'), ['"f" must be a date, e.g. 2014-05-02T10:30:00'], 'month 13');
    is_deeply(cv(['2020-01-01'], type => 'date'), ['"f" must be a single value, not a list or a set'], 'a list');
};

subtest 'check_value: list' => sub {
    is_deeply(cv(['a', 'b'], type => 'list'), [], 'a list');
    is_deeply(cv('a', type => 'list'), [], 'a single value is a one-item list');
    is_deeply(cv([], type => 'list'), [], 'an empty list');
    is_deeply(cv({ a => 1 }, type => 'list'), ['"f" must be a list'], 'a map');
    is_deeply(cv(['blog', 'news', 'misc'], type => 'list', values => ['blog', 'notes']), [
        '"f" has "news", which is not one of: blog, notes',
        '"f" has "misc", which is not one of: blog, notes',
    ], 'each item that is not allowed, in order');
    is_deeply(cv('news', type => 'list', values => ['blog']), ['"f" has "news", which is not one of: blog'], 'a single value is checked too');
    is_deeply(cv(['blog'], type => 'list', values => ['blog'], max_length => 0), [], 'string rules do not apply to lists');
};

subtest 'check_value: list with an empty item' => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my $problems = cv(['blog', undef], type => 'list', values => ['blog']);
    is(scalar @$problems, 1, 'an empty item is not allowed');
    like($problems->[0], qr/^"f" has "", which is not one of: blog$/, 'message');
    is_deeply(\@warnings, [], 'no "uninitialized value" warning');
};

subtest 'check_value: map and any' => sub {
    is_deeply(cv({ a => 1 }, type => 'map'), [], 'a map');
    is_deeply(cv({}, type => 'map'), [], 'an empty map');
    is_deeply(cv(['a'], type => 'map'), ['"f" must be a set of key: value pairs'], 'a list');
    is_deeply(cv('a', type => 'map'), ['"f" must be a set of key: value pairs'], 'a string');
    is_deeply(cv('a', type => 'any'), [], 'any: a string');
    is_deeply(cv(['a'], type => 'any'), [], 'any: a list');
    is_deeply(cv({ a => 1 }, type => 'any'), [], 'any: a map');
};

subtest 'is_boolean' => sub {
    my $b = \&App::Dapper::Schema::is_boolean;
    is($b->(JSON::true), 1, 'JSON true');
    is($b->(JSON::false), 1, 'JSON false');
    is($b->(bless({}, 'boolean')), 1, 'a boolean.pm object');
    is($b->(bless({}, 'Other')), 0, 'another object');
    is($b->([]), 0, 'a list');
    is($b->({}), 0, 'a map');
    is($b->(1), 1, 'the number 1');
    is($b->(0), 1, 'the number 0');
    is($b->(''), 1, 'empty');
    is($b->('tRuE'), 1, 'any case');
    is($b->('10'), 0, 'the number 10');
    is($b->('truely'), 0, 'not anchored loosely');
};

subtest 'messages from validate use the field name, not "f"' => sub {
    is_deeply(v("fields:\n  my_field:\n    type: integer\n", { my_field => 'x' }), ['"my_field" must be a whole number'], 'named');
};

done_testing();
