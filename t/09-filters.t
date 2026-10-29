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

is(App::Dapper::Filters::xml_escape(q{<a href="x">Tom & Jerry's</a>}),
    '&lt;a href=&quot;x&quot;&gt;Tom &amp; Jerry&#39;s&lt;/a&gt;', 'xml_escape');

is(App::Dapper::Filters::smart('a--b--c'), 'a&ndash;b&ndash;c', 'smart: adjacent en dashes');
is(App::Dapper::Filters::smart('a---b'), 'a&mdash;b', 'smart: em dash');
is(App::Dapper::Filters::smart('--start'), '&ndash;start', 'smart: at the start');
is(App::Dapper::Filters::smart('a----b'), 'a----b', 'smart: longer runs untouched');

is(App::Dapper::Filters::replace_last('a, b, c', ', ', ' and '), 'a, b and c', 'replace_last');
is(App::Dapper::Filters::replace_last('1.2.3', '.', ''), '1.23', 'replace_last is literal, not a regex');
is(App::Dapper::Filters::replace_last('abc', 'x', 'y'), 'abc', 'replace_last without a match');

my $dt = DateTime->new(year => 2014, month => 5, day => 2, hour => 10, minute => 30, time_zone => 'UTC');
is(App::Dapper::Filters::date_to_xmlschema($dt), '2014-05-02T10:30:00+00:00', 'date_to_xmlschema with a DateTime');
is(App::Dapper::Filters::date_to_xmlschema('2014-05-02T10:30:00-05:00'), '2014-05-02T10:30:00-05:00', 'date_to_xmlschema with a string');

like(App::Dapper::Filters::json({ name => 'Café' }), qr/"name" : "Café"/, 'json keeps characters, not bytes');

make_site({
    '_source/index.md'   => "---\ntitle: Café & Co\nlist: a, b, c\ndate: 2014-05-02T10:30:00\n---\nHi\n",
    '_layout/index.html' => join("\n",
        '[% page.title | xml_escape %]',
        '[% page.list | replace_last(", ", " and ") %]',
        '[% "x--y" | smart %]',
        '[% page.date.xmlschema %]',
        '[% page.date | date_to_xmlschema %]',
    ),
});
quiet_build();
my @lines = split /\n/, slurp('_output/index.html');
is($lines[0], 'Café &amp; Co', 'xml_escape in a template');
is($lines[1], 'a, b and c', 'replace_last receives its arguments in a template');
is($lines[2], 'x&ndash;y', 'smart in a template');
like($lines[3], qr/^2014-05-02T10:30:00(?:[-+]\d\d:\d\d|Z)?$/, 'page.date.xmlschema in a template');
is($lines[4], undef, 'filters do not apply to date objects, hence .xmlschema');

done_testing();
