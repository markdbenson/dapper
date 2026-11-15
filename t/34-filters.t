use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Filters;
use DateTime;

binmode(Test::More->builder->$_, ':encoding(UTF-8)') for qw(output failure_output todo_output);

subtest 'filters() registers every filter' => sub {
    my $filters = App::Dapper::Filters::filters();
    is(ref $filters, 'HASH', 'a hash');
    is_deeply([sort keys %$filters], [qw(date_to_xmlschema replace_last smart xml_escape)], 'the four filters');
    is($filters->{xml_escape}, \&App::Dapper::Filters::xml_escape, 'xml_escape is a static filter');
    is($filters->{date_to_xmlschema}, \&App::Dapper::Filters::date_to_xmlschema, 'date_to_xmlschema is static');
    is($filters->{smart}, \&App::Dapper::Filters::smart, 'smart is static');

    my $dynamic = $filters->{replace_last};
    is(ref $dynamic, 'ARRAY', 'replace_last is a dynamic filter');
    is($dynamic->[1], 1, 'flagged dynamic');
    my $factory = $dynamic->[0];
    my $filter = $factory->(undef, ', ', ' & ');
    is(ref $filter, 'CODE', 'factory returns a filter');
    is($filter->('x, y, z'), 'x, y & z', 'with the arguments given to the factory');
    is($factory->(undef, '-')->('a-b-c'), 'a-bc', 'replacement defaults to nothing');
    isnt(App::Dapper::Filters::filters(), $filters, 'a fresh hash every call');
};

subtest 'xml_escape' => sub {
    my %cases = (
        '&'                         => '&amp;',
        '<'                         => '&lt;',
        '>'                         => '&gt;',
        '"'                         => '&quot;',
        "'"                         => '&#39;',
        q{<a href="x">Tom & Jerry's</a>} => '&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&#39;s&lt;/a&gt;',
        '&amp;'                     => '&amp;amp;',
        'plain text'                => 'plain text',
        ''                          => '',
        '0'                         => '0',
        'Café 日本 ☃'                => 'Café 日本 ☃',
        "line\nbreak\ttab"          => "line\nbreak\ttab",
        '<<>>'                      => '&lt;&lt;&gt;&gt;',
        '&#39;'                     => '&amp;#39;',
    );
    for my $in (sort keys %cases) {
        is(App::Dapper::Filters::xml_escape($in), $cases{$in}, "xml_escape('$in')");
    }
    is(App::Dapper::Filters::xml_escape(undef), '', 'undef is an empty string');
    is(App::Dapper::Filters::xml_escape(42), '42', 'a number');
};

subtest 'date_to_xmlschema' => sub {
    is(App::Dapper::Filters::date_to_xmlschema(undef), '', 'undef is an empty string');
    is(App::Dapper::Filters::date_to_xmlschema('2014-05-02T10:30:00-05:00'), '2014-05-02T10:30:00-05:00', 'offset kept');
    is(App::Dapper::Filters::date_to_xmlschema('2014-05-02T10:30:00Z'), '2014-05-02T10:30:00+00:00', 'Z');
    is(App::Dapper::Filters::date_to_xmlschema('2014-05-02'), '2014-05-02T00:00:00+00:00', 'date only');
    is(App::Dapper::Filters::date_to_xmlschema('2014-05-02 10:30'), '2014-05-02T10:30:00+00:00', 'old format');
    is(App::Dapper::Filters::date_to_xmlschema(
        DateTime->new(year => 2001, month => 2, day => 3, hour => 4, minute => 5, second => 6, time_zone => '+0130')),
        '2001-02-03T04:05:06+01:30', 'a DateTime');
    my $date = App::Dapper::Utils::parse_date('2020-12-31T23:59:59+14:00');
    is(App::Dapper::Filters::date_to_xmlschema($date), '2020-12-31T23:59:59+14:00', 'an App::Dapper::Date');
    eval { App::Dapper::Filters::date_to_xmlschema('soon') };
    like($@, qr/^error: could not understand the date "soon"/, 'a bad date dies');
};

subtest 'replace_last' => sub {
    my $rl = \&App::Dapper::Filters::replace_last;
    is($rl->('a, b, c', ', ', ' and '), 'a, b and c', 'last of several');
    is($rl->('a, b', ', ', ' and '), 'a and b', 'the only one');
    is($rl->('abc', 'x', 'y'), 'abc', 'no match');
    is($rl->('1.2.3', '.', ''), '1.23', 'literal dot, empty replacement');
    is($rl->('1.2.3', '.'), '1.23', 'missing replacement is empty');
    is($rl->('1.2.3', '.', undef), '1.23', 'undef replacement is empty');
    is($rl->('a.b.c', '.*', '!'), 'a.b.c', 'regex characters are literal');
    is($rl->('a.*b.*c', '.*', '!'), 'a.*b!c', 'and matched literally');
    is($rl->('xxx', 'xx', 'y'), 'xy', 'overlapping: the last start position wins');
    is($rl->('end', 'end', 'END'), 'END', 'whole string');
    is($rl->('start-mid-start', 'start', 'S'), 'start-mid-S', 'at the end');
    is($rl->('Zoë & Zoë', 'Zoë', 'Zed'), 'Zoë & Zed', 'Unicode');
    is($rl->('abc', '', 'y'), 'abc', 'empty search string: unchanged');
    is($rl->('abc', undef, 'y'), 'abc', 'undef search string: unchanged');
    is($rl->(undef, 'a', 'b'), undef, 'undef input is returned as undef');
    is($rl->('', 'a', 'b'), '', 'empty input');
    is($rl->('a0', '0', 'zero'), 'azero', 'a search string of 0 is used');
};

subtest 'smart' => sub {
    my %cases = (
        'a--b'           => 'a&ndash;b',
        'a---b'          => 'a&mdash;b',
        'a----b'         => 'a----b',
        'a-----b'        => 'a-----b',
        'a-b'            => 'a-b',
        '--start'        => '&ndash;start',
        'end--'          => 'end&ndash;',
        '---'            => '&mdash;',
        '--'             => '&ndash;',
        '-- and ---'     => '&ndash; and &mdash;',
        'a -- b --- c ---- d' => 'a &ndash; b &mdash; c ---- d',
        '--x--'          => '&ndash;x&ndash;',
        'no dashes'      => 'no dashes',
        ''               => '',
        "--\n---"        => "&ndash;\n&mdash;",
    );
    for my $in (sort keys %cases) {
        is(App::Dapper::Filters::smart($in), $cases{$in}, "smart('$in')");
    }
    is(App::Dapper::Filters::smart(undef), '', 'undef is an empty string');
};

subtest 'filters in templates' => sub {
    make_site({
        '_source/a.md' => join("\n",
            '---',
            q{title: "Tom & <Jerry> \"q\" it's"},
            'list: [1, 2]',
            'hash: {a: 1}',
            'num: 5',
            'date: 2014-05-02T10:30:00',
            'timezone: UTC',
            'names: "Ann, Bob, Cy"',
            '---',
            'body', ''),
        '_layout/index.html' => join("\n",
            '[% page.title | xml_escape %]',
            '[% page.list | xml_escape %]|',
            '[% page.hash | xml_escape %]|',
            '[% page.num | xml_escape %]',
            '[% "2014-05-02T10:30:00-05:00" | date_to_xmlschema %]',
            '[% page.date | date_to_xmlschema %]|',
            '[% page.names | replace_last(", ", " and ") %]',
            '[% "a.b.c" | replace_last(".") %]',
            '[% "abc" | replace_last("z", "y") %]',
            '[% "a -- b --- c ---- d" | smart %]',
            '[% page.missing | smart %]|',
            '[% page.missing | xml_escape %]|',
            '[% page.missing | date_to_xmlschema %]|',
            '[% page.date.xmlschema %]',
            '[% page.title | xml_escape | smart %]',
            '[% "x -- y" | smart | xml_escape %]',
            '[% FILTER xml_escape %]<b>block</b>[% END %]',
            '[% "a, b, c" | replace_last(", ", ", and ") | upper %]',
            ''),
    });
    quiet_build();
    my @lines = split /\n/, slurp('_output/a.html'), -1;
    is($lines[0], 'Tom &amp; &lt;Jerry&gt; &quot;q&quot; it&#39;s', 'xml_escape');
    is($lines[1], '|', 'xml_escape on a list prints nothing');
    is($lines[2], '|', 'xml_escape on a hash prints nothing');
    is($lines[3], '5', 'xml_escape on a number');
    is($lines[4], '2014-05-02T10:30:00-05:00', 'date_to_xmlschema on a string');
    is($lines[5], '|', 'date_to_xmlschema on a date object prints nothing');
    is($lines[6], 'Ann, Bob and Cy', 'replace_last with two arguments');
    is($lines[7], 'a.bc', 'replace_last with one argument');
    is($lines[8], 'abc', 'replace_last without a match');
    is($lines[9], 'a &ndash; b &mdash; c ---- d', 'smart');
    is($lines[10], '|', 'smart on an undefined value');
    is($lines[11], '|', 'xml_escape on an undefined value');
    is($lines[12], '|', 'date_to_xmlschema on an undefined value');
    is($lines[13], '2014-05-02T10:30:00+00:00', 'the xmlschema method');
    is($lines[14], 'Tom &amp; &lt;Jerry&gt; &quot;q&quot; it&#39;s', 'chained filters');
    is($lines[15], 'x &amp;ndash; y', 'order of chained filters matters');
    is($lines[16], '&lt;b&gt;block&lt;/b&gt;', 'FILTER block');
    is($lines[17], 'A, B, AND C', 'with a built-in filter');
};

subtest 'a bad date in date_to_xmlschema stops the build' => sub {
    make_site({
        '_source/a.md' => "---\ntitle: x\n---\nx\n",
        '_layout/index.html' => '[% "someday" | date_to_xmlschema %]',
    });
    eval { quiet_build() };
    like($@, qr{could not process _source/a\.md with layout index}, 'names the page and layout');
    like($@, qr{could not understand the date "someday"}, 'and the date');
};

done_testing();
