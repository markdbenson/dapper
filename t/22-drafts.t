use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Check;

my %site = (
    '_config.yml'          => "---\nname: x\nurl: https://example.com\nfeed: true\n",
    '_source/index.md'     => "---\ntitle: Home\n---\nHome\n",
    '_source/done.md'      => "---\ntitle: Done\ncategories: blog\ndate: 2020-01-01\n---\nDone\n",
    '_source/draft.md'     => "---\ntitle: Draft\ndraft: true\n---\nDraft\n",
    '_source/not-draft.md' => "---\ntitle: Not a draft\ndraft: false\n---\nx\n",
    '_source/later.md'     => "---\ntitle: Later\ncategories: blog\ndate: 2999-01-01\n---\nLater\n",
);

sub build_site {
    my (%options) = @_;
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{$_} = $options{$_} for keys %options;
    $d->build();
    return $d;
}

subtest 'held back from a build' => sub {
    make_site({ %site });
    my $d = build_site();

    ok(-f '_output/blog/2020/01/done/index.html', 'a published page');
    ok(-f '_output/not-draft.html', 'draft: false is published');
    ok(!-e '_output/draft.html', 'no draft');
    ok(!-e '_output/blog/2999/01/later/index.html', 'no page dated in the future');

    my @titles = sort map { $_->{title} } @{ $d->{site}->{pages} };
    is_deeply(\@titles, ['Done', 'Home', 'Not a draft'], 'not in site.pages');
    is(scalar @{ $d->{site}->{categories}->{blog} }, 1, 'not in categories');
    unlike(slurp('_output/sitemap.xml'), qr{/draft\.html|later}, 'not in the sitemap');
    unlike(slurp('_output/feed.xml'), qr/Draft|Later/, 'not in the feed');

    is_deeply([ map { "$_->{file} $_->{reason}" } @{ $d->{held} } ],
        ['_source/draft.md draft', '_source/later.md scheduled'], 'what was held back');
};

subtest 'shown with drafts on' => sub {
    make_site({ %site });
    build_site(drafts => 1);
    ok(-f '_output/draft.html', 'the draft');
    ok(-f '_output/blog/2999/01/later/index.html', 'the page dated in the future');
};

subtest 'future: true publishes pages dated in the future' => sub {
    make_site({ %site, '_config.yml' => "---\nname: x\nfuture: true\n" });
    build_site();
    ok(-f '_output/blog/2999/01/later/index.html', 'published');
    ok(!-e '_output/draft.html', 'drafts are still held back');
};

subtest 'a draft that is published later' => sub {
    make_site({ %site });
    build_site();
    ok(!-e '_output/draft.html', 'held back');
    spew('_source/draft.md', "---\ntitle: Draft\n---\nDraft\n");
    build_site();
    ok(-f '_output/draft.html', 'published once draft: true is removed');

    spew('_source/draft.md', "---\ntitle: Draft\ndraft: true\n---\nDraft\n");
    build_site();
    ok(!-e '_output/draft.html', 'removed again when it goes back to being a draft');
};

subtest 'check' => sub {
    make_site({ %site, '_source/index.md' => "---\ntitle: Home\n---\n[draft](/draft.html)\n" });
    my $report = App::Dapper->new()->check();
    is_deeply($report->{held}, [
        { file => '_source/draft.md', reason => 'draft' },
        { file => '_source/later.md', reason => 'scheduled' },
    ], 'held pages listed');
    ok((grep { $_->{message} =~ m{links to /draft\.html} } @{ $report->{errors} }), 'a link to a draft is broken');
    like(App::Dapper::Check::text($report), qr/Not published: 1 draft, 1 scheduled/, 'in the text report');

    my $d = App::Dapper->new();
    $d->{drafts} = 1;
    $report = $d->check();
    is_deeply($report->{held}, [], 'nothing held with drafts on');
    ok($report->{ok}, 'and the link is fine');
};

subtest 'deploy never publishes drafts' => sub {
    make_site({ %site, '_deploy.pl' => "1;\n",
                '_config.yml' => "---\nname: x\ndeploy:\n  command: '$^X _deploy.pl'\n" });
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->{drafts} = 1;
    $d->deploy();
    ok(!-e '_output/draft.html', 'no draft');
    ok(-f '_output/blog/2020/01/done/index.html', 'published pages');
};

subtest 'the MCP tools' => sub {
    require App::Dapper::MCP;
    make_site({ %site });
    my $d = App::Dapper->new();
    is(scalar @{ App::Dapper::MCP::check($d, {})->{held} }, 2, 'check leaves drafts out');
    is(scalar @{ App::Dapper::MCP::check($d, { drafts => JSON::true })->{held} }, 0, 'unless asked');
    App::Dapper::MCP::build($d, { drafts => 1 });
    ok(-f '_output/draft.html', 'build with drafts');
    ok(!$d->{drafts}, 'and only that once');
};

done_testing();
