use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use POSIX ();
use App::Dapper::Check;

# Drafts and pages dated in the future: what is held back, and what check says

sub build_site {
    my (%options) = @_;
    my $loud = delete $options{loud};
    my $d = App::Dapper->new();
    $d->{quiet} = $loud ? 0 : 1;
    $d->{$_} = $options{$_} for keys %options;
    my $out = '';
    open(my $fh, '>', \$out) or die;
    my $old = select $fh;
    eval { $d->build() };
    my $error = $@;
    select $old;
    die $error if $error;
    return wantarray ? ($d, $out) : $d;
}

sub held { my ($d) = @_; [ map { "$_->{file} $_->{reason}" } @{ $d->{held} } ] }
sub page { my ($title, $extra) = @_; "---\ntitle: $title\n" . (defined $extra ? $extra : '') . "---\n$title\n" }

subtest 'an undated page is never scheduled, whatever the time zones' => sub {
    # The file's modified time is a moment, not a clock reading: a site time
    # zone west of the machine's must not push it into the future
    local $ENV{TZ} = 'UTC';
    POSIX::tzset();
    for my $zone (qw( America/Chicago Pacific/Pago_Pago Pacific/Kiritimati )) {
        make_site({ '_config.yml' => "---\nname: x\ntimezone: $zone\n", '_source/undated.md' => page('Undated') });
        my $d = build_site();
        is_deeply(held($d), [], "not held back with the site in $zone");
        ok(-f '_output/undated.html', "and written");
        is($d->{site}->{pages}->[0]->{date}->time_zone->name, $zone, "its date is shown in $zone");
    }
};
POSIX::tzset();

subtest 'which values make a draft' => sub {
    my %drafts = (true => 1, yes => 1, on => 1, 1 => 1, 'Yes' => 1, 'anything' => 1,
                  false => 0, no => 0, off => 0, 0 => 0, "''" => 0, 'No' => 0, 'OFF' => 0);
    my %files;
    my $n = 0;
    for my $value (sort keys %drafts) {
        $files{"_source/p$n.md"} = page("P$n", "draft: $value\n");
        $n++;
    }
    make_site({ %files, '_source/none.md' => page('None') });
    my $d = build_site();
    $n = 0;
    for my $value (sort keys %drafts) {
        if ($drafts{$value}) { ok(!-e "_output/p$n.html", "draft: $value is held back") }
        else                 { ok(-f "_output/p$n.html", "draft: $value is published") }
        $n++;
    }
    ok(-f '_output/none.html', 'no draft key: published');
    is(scalar @{ $d->{held} }, scalar(grep { $_ } values %drafts), 'everything held is listed');
    is_deeply([ sort map { $_->{reason} } @{ $d->{held} } ], [ ('draft') x scalar(grep { $_ } values %drafts) ], 'all as drafts');
};

subtest 'scheduled pages and future:' => sub {
    my %site = (
        '_source/later.md'       => page('Later', "date: 2999-01-01\n"),
        '_source/past.md'        => page('Past', "date: 2001-01-01\n"),
        '_source/later-draft.md' => page('Later draft', "date: 2999-01-01\ndraft: true\n"),
        '_source/zoned.md'       => page('Zoned', "date: 2999-06-01T08:00:00\ntimezone: America/New_York\n"),
        '_source/undated.md'     => page('Undated'),
    );
    make_site({ %site });
    my ($d, $out) = build_site(loud => 1);
    is_deeply(held($d), ['_source/later-draft.md draft', '_source/later.md scheduled', '_source/zoned.md scheduled'],
        'a draft dated in the future is held as a draft');
    ok(-f '_output/past.html', 'a page dated in the past');
    ok(-f '_output/undated.html', 'a page without a date (its file time)');
    like($out, qr{^Held back _source/later-draft\.md \(draft\)$}m, 'said for a draft');
    like($out, qr{^Held back _source/later\.md \(scheduled for 2999-01-01T00:00:00\)$}m, 'said for a scheduled page, with its date');
    like($out, qr{^Held back _source/zoned\.md \(scheduled for 2999-06-01T08:00:00\)$}m, 'in its own time zone');
    isa_ok($d->{held}->[1]->{date}, 'DateTime', 'the date is kept');

    for my $on ('true', 'yes', '1') {
        make_site({ %site, '_config.yml' => "---\nname: x\nfuture: $on\n" });
        $d = build_site();
        is_deeply(held($d), ['_source/later-draft.md draft'], "future: $on publishes pages dated in the future");
        ok(-f '_output/later.html', "future: $on, the page");
    }
    for my $off ('false', 'no', 'off', '0') {
        make_site({ %site, '_config.yml' => "---\nname: x\nfuture: $off\n" });
        $d = build_site();
        is(scalar @{ $d->{held} }, 3, "future: $off holds them back");
    }
};

subtest 'drafts on' => sub {
    make_site({
        '_source/a.md' => page('A', "draft: true\n"),
        '_source/b.md' => page('B', "date: 2999-01-01\n"),
        '_source/c.html' => page('C', "draft: true\n"),
    });
    my $d = build_site(drafts => 1);
    is_deeply($d->{held}, [], 'nothing held');
    ok(-f "_output/$_", $_) for qw/ a.html b.html c.html /;
    is(scalar @{ $d->{site}->{pages} }, 3, 'all in site.pages');

    $d = build_site();
    is_deeply(held($d), ['_source/a.md draft', '_source/b.md scheduled', '_source/c.html draft'], 'HTML pages too, once drafts are off');
    ok(!-e "_output/$_", "$_ removed") for qw/ a.html b.html c.html /;
    $d->build();
    is(scalar @{ $d->{held} }, 3, 'the list starts again with each build');
};

subtest 'left out of the site' => sub {
    make_site({
        '_config.yml' => "---\nname: x\nurl: https://example.com\nfeed: true\n",
        '_layout/index.html' => "<title>[% page.title %]</title>[% page.content %]\n"
            . "[% FOR p IN site.pages %][% p.title %];[% END %]|[% FOR t IN site.tags.keys.sort %][% t %];[% END %]|[% FOR c IN site.categories.keys.sort %][% c %];[% END %]",
        '_source/index.md' => page('Home'),
        '_source/pub.md'   => page('Pub', "categories: news\ntags: [shared, open]\ndate: 2020-01-01\n"),
        '_source/draft.md' => page('Draft', "categories: secret\ntags: [shared, hidden]\ndate: 2020-01-02\ndraft: true\n"),
        '_source/later.md' => page('Later', "categories: news\ntags: [soon]\ndate: 2999-01-02\n"),
        '_source/img.png'  => 'not a page',
    });
    my $d = build_site();
    my $home = slurp('_output/index.html');
    like($home, qr{\|open;shared;\|news;$}, 'not in site.tags or site.categories');
    unlike($home, qr{Draft;|Later;}, 'not in site.pages');
    is(scalar @{ $d->{site}->{categories}->{news} }, 1, 'the category has only the published page');
    unlike(slurp('_output/sitemap.xml'), qr{draft|later}, 'not in the sitemap');
    unlike(slurp('_output/feed.xml'), qr{Draft|Later}, 'not in the feed');
    ok(-f '_output/img.png', 'files without front matter are never held');
};

subtest 'check' => sub {
    my %site = (
        '_config.yml'    => "---\nname: x\nurl: https://example.com\n",
        '_source/index.md' => page('Home'),
        '_source/a.md'   => page('A', "draft: true\n"),
        '_source/b.md'   => page('B', "draft: true\n"),
        '_source/c.md'   => page('C', "date: 2999-01-01\n"),
    );
    make_site({ %site });
    my $report = App::Dapper->new()->check();
    is_deeply($report->{held}, [
        { file => '_source/a.md', reason => 'draft' },
        { file => '_source/b.md', reason => 'draft' },
        { file => '_source/c.md', reason => 'scheduled' },
    ], 'held pages, with the file and why (no date)');
    like(App::Dapper::Check::text($report), qr{^Not published: 2 drafts, 1 scheduled \(use --drafts to include them\)\.$}m, 'plural');

    make_site({ %site, '_source/b.md' => page('B'), '_source/c.md' => page('C') });
    $report = App::Dapper->new()->check();
    like(App::Dapper::Check::text($report), qr{^Not published: 1 draft, 0 scheduled \(use --drafts to include them\)\.$}m, 'one draft');

    make_site({ %site, '_source/a.md' => page('A'), '_source/b.md' => page('B') });
    $report = App::Dapper->new()->check();
    like(App::Dapper::Check::text($report), qr{^Not published: 0 drafts, 1 scheduled}m, 'only scheduled');

    make_site({ %site, '_source/a.md' => page('A'), '_source/b.md' => page('B'), '_source/c.md' => page('C') });
    $report = App::Dapper->new()->check();
    is_deeply($report->{held}, [], 'nothing held');
    unlike(App::Dapper::Check::text($report), qr/Not published/, 'and nothing said');

    is(App::Dapper::Check::text({ errors => [], warnings => [], pages => 1, held => [{ reason => 'draft' }] }),
        "Not published: 1 draft, 0 scheduled (use --drafts to include them).\nChecked 1 page: 0 errors, 0 warnings.\n", 'text, exactly');
    is(App::Dapper::Check::text({ errors => [], warnings => [], pages => 2 }), "Checked 2 pages: 0 errors, 0 warnings.\n", 'text without a held list');
};

done_testing();
