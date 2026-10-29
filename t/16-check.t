use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Check;

sub check_site {
    my $d = App::Dapper->new();
    return $d->check();
}

subtest 'a clean site' => sub {
    make_site({
        '_config.yml'      => "---\nname: x\nurl: https://example.com\n",
        '_source/index.md' => "---\ntitle: Home\n---\n[About](/about.html), [again](https://example.com/about.html), [top](#top), [ext](https://perl.org), [mail](mailto:a\@b.c)\n",
        '_source/about.md' => "---\ntitle: About\n---\n[Home](/) and [index](./index.html) ![me](img/me.png)\n",
        '_source/img/me.png' => "PNG",
    });
    my $report = check_site();
    ok($report->{ok}, 'ok') or diag explain $report;
    is($report->{pages}, 2, 'pages counted');
    is_deeply($report->{errors}, [], 'no errors');
    is_deeply($report->{warnings}, [], 'no warnings');
    ok(!-e '_output', 'the output directory is not written');
};

subtest 'every kind of problem, all at once' => sub {
    make_site({
        '_source/_schema.yml'  => "required: [title]\n",
        '_source/a.md'         => "---\ntitle: A\n---\n[gone](/gone/) ![pic](missing.png)\n",
        '_source/b.md'         => "---\ndescription: no title\n---\nx\n",
        '_source/c.md'         => "---\ntitle: C\nlayout: nope\n---\nx\n",
        '_source/d.md'         => "---\ntitle: [broken\n---\nx\n",
        '_source/e.md'         => "---\ntitle: E\ntemplate: true\n---\n[% IF %]\n",
        '_source/f.md'         => "---\ntitle: F\nurlpattern: /a.html\n---\nx\n",
    });
    my $report = check_site();
    ok(!$report->{ok}, 'not ok');

    my %by_type;
    push @{ $by_type{$_->{type}} }, $_ for @{ $report->{errors} };

    is(scalar @{ $by_type{schema} || [] }, 1, 'schema error') or diag explain $report->{errors};
    like($by_type{schema}->[0]->{message}, qr/"title" is required/, 'schema message');
    is($by_type{schema}->[0]->{file}, '_source/b.md', 'schema file');
    is(scalar @{ $by_type{layout} || [] }, 1, 'layout error');
    is($by_type{layout}->[0]->{message}, 'uses the layout "nope", but there is no such file in _layout', 'file name not repeated');
    is(scalar @{ $by_type{front_matter} || [] }, 1, 'front matter error');
    is(scalar @{ $by_type{template} || [] }, 1, 'template error');
    is(scalar @{ $by_type{duplicate} || [] }, 1, 'two pages writing one file');
    is_deeply([ sort map { $_->{message} } @{ $by_type{link} || [] } ],
        [ 'links to /gone/, which is not in the site', 'links to missing.png, which is not in the site' ], 'broken links');
    is($by_type{link}->[0]->{file}, '_source/a.md', 'links reported against the source file');

    my @warnings = map { $_->{message} } @{ $report->{warnings} };
    ok((grep { /url is not set/ } @warnings), 'url warning');
};

subtest 'target_path' => sub {
    my $t = \&App::Dapper::Check::target_path;
    is($t->('../b/', '/blog/a/', ''), '/blog/b/', 'relative with ..');
    is($t->('./c.html?x=1#y', '/blog/', ''), '/blog/c.html', 'query and fragment removed');
    is($t->('https://example.com/x/', '/', 'https://example.com'), '/x/', 'absolute link to the site');
    is($t->('https://other.com/x/', '/', 'https://example.com'), undef, 'other sites ignored');
    is($t->('my%20file.txt', '/', ''), '/my file.txt', 'decoded');
    is($t->('#top', '/', ''), undef, 'same page');
};

done_testing();
