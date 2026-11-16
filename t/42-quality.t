use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

# The accessibility and SEO warnings from dapper check: every rule, its
# exceptions, and the check: settings.

my $layout = qq{<html lang="en"><head><title>[% page.title %]</title></head><body>[% page.content %]</body></html>};

sub warnings_of {
    my ($type) = @_;
    my $report = App::Dapper->new()->check();
    return [ map { "$_->{file}: $_->{message}" } grep { $_->{type} eq $type } @{ $report->{warnings} } ];
}

sub a11y_for {
    my ($html, %more) = @_;
    make_site({ '_layout/index.html' => $layout, '_source/a.html' => "---\ntitle: A\n---\n$html\n", %more });
    return [ map { (my $w = $_) =~ s/^_source\/a\.html: //; $w } @{ warnings_of(q{accessibility}) } ];
}

sub seo_for {
    my (%files) = @_;
    make_site({ '_config.yml' => "---\nname: x\nurl: https://example.com\n", '_layout/index.html' => $layout, %files });
    return warnings_of('seo');
}

my $no_alt = 'has no alt text; describe it, or use alt="" if it is decoration';

subtest 'images: alt text' => sub {
    is_deeply(a11y_for('<img src="a.png">'), ["the image a.png $no_alt"], 'no alt');
    is_deeply(a11y_for('<img src="a.png" alt="">'), [], 'alt="" is decoration');
    is_deeply(a11y_for('<img src="a.png" alt="A cat">'), [], 'alt text');
    is_deeply(a11y_for('<IMG SRC="a.png" ALT="x">'), [], 'any case');
    is_deeply(a11y_for("<img src='a.png'>"), ["the image a.png $no_alt"], 'single quotes');
    is_deeply(a11y_for('<img src="a.png" alt>'), [], 'alt with no value counts as alt=""');
    is_deeply(a11y_for('<img>'), ["the image (no src) $no_alt"], 'no src');
    is_deeply(a11y_for('<img src="a.png"><img src="a.png"> <img src="b.png" />'),
        ["the image a.png $no_alt", "the image b.png $no_alt"], 'each image once, in order');
    is_deeply(a11y_for('<img data-alt="x" src="a.png">'), ["the image a.png $no_alt"], 'data-alt is not alt');
};

subtest 'images in Markdown' => sub {
    make_site({
        '_layout/index.html' => $layout,
        '_source/a.md' => "---\ntitle: A\n---\n![](one.png) ![ ](two.png) ![](<three.png>) ![Alt](four.png)\n\n`![](code.png)`\n\n```\n![](fenced.png)\n```\n\n~~~~\n![](tilde.png)\n~~~~\n\n![](one.png)\n",
    });
    is_deeply(warnings_of('accessibility'), [
        "_source/a.md: the image one.png $no_alt",
        "_source/a.md: the image two.png $no_alt",
        "_source/a.md: the image three.png $no_alt",
    ], 'empty or blank alt in Markdown; code spans and fences ignored; each once');
};

subtest 'images: Markdown and HTML together are reported once' => sub {
    make_site({
        '_layout/index.html' => $layout,
        '_source/a.md' => "---\ntitle: A\n---\n![](x.png)\n\n<img src=\"x.png\">\n",
    });
    is_deeply(warnings_of('accessibility'), ["_source/a.md: the image x.png $no_alt"], 'once');
};

subtest 'images in the layout' => sub {
    make_site({
        '_layout/index.html' => qq{<html lang="en"><title>[% page.title %]</title><img src="/logo.png">[% page.content %]</html>},
        '_source/a.html' => "---\ntitle: A\n---\n<p>a</p>\n",
        '_source/b.html' => "---\ntitle: B\n---\n<p>b</p>\n",
    });
    is_deeply(warnings_of('accessibility'), [
        "_source/a.html: the image /logo.png $no_alt",
        "_source/b.html: the image /logo.png $no_alt",
    ], 'reported for each page that uses the layout');
};

subtest 'headings' => sub {
    is_deeply(a11y_for('<h1>A</h1><h2>B</h2><h3>C</h3><h2>D</h2><h1>E</h1><h2>F</h2>'), [], 'in order, and going back up');
    is_deeply(a11y_for('<h1>A</h1><h3>C</h3>'), ['the heading "C" skips from h1 to h3; use h2'], 'skip a level');
    is_deeply(a11y_for('<h2>A</h2><h6>F</h6>'), ['the heading "F" skips from h2 to h6; use h3'], 'skip several');
    is_deeply(a11y_for('<h3>Starts low</h3><h4>x</h4>'), [], 'the first heading may be any level');
    is_deeply(a11y_for('<h1>A</h1><h3>B</h3><h1>C</h1><h4>D</h4>'), ['the heading "B" skips from h1 to h3; use h2'], 'only the first skip');
    is_deeply(a11y_for('<h1>A</h1><h3 class="x"><a href="/a.html">Linked &amp; <em>styled</em></a></h3>'),
        ['the heading "Linked & styled" skips from h1 to h3; use h2'], 'attributes and markup inside');
    is_deeply(a11y_for("<H1>A</H1>\n<h3>\nMulti\nline\n</h3>"), ['the heading "Multi line" skips from h1 to h3; use h2'], 'any case, across lines');
    is_deeply(a11y_for('<h1>A</h1><header>x</header><h2>B</h2>'), [], '<header> is not a heading');
};

subtest 'language' => sub {
    make_site({
        '_layout/index.html' => "<html><title>[% page.title %]</title>[% page.content %]</html>",
        '_layout/fr.tt'      => "<HTML LANG='fr'><title>[% page.title %]</title>[% page.content %]</HTML>",
        '_layout/nolang.htm' => "<html class=\"x\"><title>[% page.title %]</title>[% page.content %]</html>",
        '_layout/frag.html'  => "<title>[% page.title %]</title>[% page.content %]",
        '_source/a.html' => "---\ntitle: A\n---\n<p>a</p>\n",
        '_source/b.html' => "---\ntitle: B\n---\n<p>b</p>\n",
        '_source/c.html' => "---\ntitle: C\nlayout: fr\n---\n<p>c</p>\n",
        '_source/d.html' => "---\ntitle: D\nlayout: nolang\n---\n<p>d</p>\n",
        '_source/e.html' => "---\ntitle: E\nlayout: frag\n---\n<p>e</p>\n",
    });
    my $msg = 'the <html> tag has no lang attribute (for example <html lang="en">), so screen readers may read the page in the wrong language';
    is_deeply(warnings_of('accessibility'), [
        "_layout/index.html: $msg",
        "_layout/nolang.htm: $msg",
    ], 'once per layout, named with its extension; lang in any case is fine; no <html> tag is not checked');
};

subtest 'language: a layout that is not a file of its own' => sub {
    make_site({
        '_layout/index.html' => "<html><title>[% page.title %]</title>[% page.content %]</html>",
        '_source/a.html' => "---\ntitle: A\nlayout: ''\n---\n<p>a</p>\n",
    });
    is_deeply(warnings_of('accessibility'), [
        '_layout/index.html: the <html> tag has no lang attribute (for example <html lang="en">), so screen readers may read the page in the wrong language',
    ], 'an empty layout is the index layout');
};

subtest 'links with no text' => sub {
    my $empty = 'has no text; add text, alt text to its image, or an aria-label';
    is_deeply(a11y_for('<a href="/a.html"></a>'), ["the link to /a.html $empty"], 'empty');
    is_deeply(a11y_for('<a href="/a.html">  <span> </span> </a>'), ["the link to /a.html $empty"], 'only white space and tags');
    is_deeply(a11y_for('<a href="/a.html"><img src="i.png" alt=""></a>'), ["the link to /a.html $empty"], 'an image with empty alt');
    is_deeply(a11y_for('<a href="/a.html"><img src="i.png" alt="Home"></a>'), [], 'an image with alt text');
    is_deeply(a11y_for('<a href="/a.html" title="Home"></a>'), [], 'a title');
    is_deeply(a11y_for('<a href="/a.html" title=""></a>'), ["the link to /a.html $empty"], 'an empty title does not count');
    is_deeply(a11y_for('<a href="/a.html" aria-label="Home"></a>'), [], 'aria-label');
    is_deeply(a11y_for('<a href="/a.html" aria-labelledby="h"></a>'), [], 'aria-labelledby');
    is_deeply(a11y_for('<a name="top"></a><a id="x"></a>'), [], 'anchors without href are not links');
    is_deeply(a11y_for('<a href="/a.html"></a><a href="/a.html"></a><a href="/b.html"></a>'),
        ["the link to /a.html $empty", "the link to /b.html $empty"], 'once per target');
    is_deeply(a11y_for("<a href='/a.html'>&nbsp;</a>"), ["the link to /a.html $empty"], 'a non-breaking space is no text');
};

subtest 'links with vague text' => sub {
    my $vague = sub { qq{the link to $_[0] says only "$_[1]"; say where it goes instead} };
    for my $text ('click here', 'click', 'here', 'this', 'link', 'this link', 'this page') {
        is_deeply(a11y_for(qq{<a href="/a.html">$text</a>}), [ $vague->('/a.html', $text) ], qq{"$text"});
    }
    is_deeply(a11y_for('<a href="/a.html">Click Here!</a>'), [ $vague->('/a.html', 'click here') ], 'any case, trailing !');
    is_deeply(a11y_for('<a href="/a.html">Here...</a>'), [ $vague->('/a.html', 'here') ], 'trailing dots');
    is_deeply(a11y_for('<a href="/a.html">here: </a>'), [ $vague->('/a.html', 'here') ], 'trailing colon and space');
    is_deeply(a11y_for('<a href="/a.html"><b>this</b> page</a>'), [ $vague->('/a.html', 'this page') ], 'markup inside');
    is_deeply(a11y_for('<a href="/a.html">read more</a> <a href="/a.html">here and there</a> <a href="/a.html">here?</a>'), [], 'other text is fine');
    is_deeply(a11y_for('<a href="/a.html" aria-label="The A page">here</a>'), [], 'aria-label overrides');
    is_deeply(a11y_for('<a href="/a.html">here</a> <a href="/a.html">here</a> <a href="/b.html">here</a> <a href="/a.html">this</a>'),
        [ $vague->('/a.html', 'here'), $vague->('/b.html', 'here'), $vague->('/a.html', 'this') ], 'once per text and target');
    is_deeply(a11y_for('<a class="x" href="/a.html">here</a>'), [ $vague->('/a.html', 'here') ], 'href after other attributes');
    is_deeply(a11y_for('<a href>here</a>'), [], 'an href with no value is not seen as a link');
};

subtest 'code, scripts and styles are ignored' => sub {
    is_deeply(a11y_for('<pre><img src="a.png"><a href="/x">here</a></pre><code><h1>a</h1><h4>b</h4></code>'
        . '<script>var s = "<img src=b.png>";</script><style>/* <img src="c.png"> */</style><!-- <img src="d.png"> -->'), [], 'none of it is checked');
};

subtest 'every accessibility problem on a page, in order' => sub {
    is_deeply(a11y_for('<h1>A</h1><h3>C</h3><img src="i.png"><a href="/x.html">here</a><a href="/y.html"></a>'), [
        "the image i.png $no_alt",
        'the heading "C" skips from h1 to h3; use h2',
        'the link to /x.html says only "here"; say where it goes instead',
        'the link to /y.html has no text; add text, alt text to its image, or an aria-label',
    ], 'images, headings, language, then links');

    is_deeply(a11y_for('<a href="/x.html">here</a><h1>A</h1><h2>B</h2>'),
        ['the link to /x.html says only "here"; say where it goes instead'], 'a link before the headings, with no skip');
    is_deeply(a11y_for('<a href="/x.html">here</a><h1>A</h1><h3>C</h3>'), [
        'the heading "C" skips from h1 to h3; use h2',
        'the link to /x.html says only "here"; say where it goes instead',
    ], 'a link before a skipped heading is still checked');
};

subtest 'seo: titles' => sub {
    my $len = sub { my $n = shift; ('a' x $n) };
    is_deeply(seo_for('_source/a.html' => "---\ntitle: " . $len->(70) . "\ndescription: d\n---\n<p>x</p>\n"), [], '70 characters is fine');
    is_deeply(seo_for('_source/a.html' => "---\ntitle: " . $len->(71) . "\ndescription: d\n---\n<p>x</p>\n"),
        ['_source/a.html: the title is 71 characters long; search engines show about 60'], '71 is too long');
    is_deeply(seo_for('_source/a.html' => "---\ntitle: 'Tom &amp; Jerry'\ndescription: d\n---\n<p>x</p>\n",
                      '_source/b.html' => "---\ntitle: Tom & Jerry\ndescription: e\n---\n<p>x</p>\n"),
        ['_source/b.html: has the same title as _source/a.html ("Tom & Jerry"); give each page its own'], 'compared as text');
    is_deeply(seo_for('_source/a.html' => "---\ntitle: Same\ndescription: d\n---\n<p>x</p>\n",
                      '_source/b.html' => "---\ntitle: Same\ndescription: e\n---\n<p>x</p>\n",
                      '_source/c.html' => "---\ntitle: Same\ndescription: f\n---\n<p>x</p>\n"), [
        '_source/b.html: has the same title as _source/a.html ("Same"); give each page its own',
        '_source/c.html: has the same title as _source/a.html ("Same"); give each page its own',
    ], 'each later page names the first');
    is_deeply(seo_for('_layout/index.html' => "<html lang=\"en\"><title></title>[% page.content %]</html>",
                      '_source/a.html' => "---\ntitle: A\ndescription: d\n---\n<p>x</p>\n",
                      '_source/b.html' => "---\ntitle: B\ndescription: e\n---\n<p>x</p>\n"), [], 'empty titles are not compared');
    is_deeply(seo_for('_layout/index.html' => "<html lang=\"en\">[% page.content %]</html>",
                      '_source/a.html' => "---\ntitle: A\ndescription: d\n---\n<p>x</p>\n"), [], 'no <title> tag');
};

subtest 'seo: descriptions' => sub {
    my $no = 'has no description; add description to its front matter, or start it with a paragraph';
    is_deeply(seo_for('_source/a.html' => "---\ntitle: A\n---\n<div>x</div>\n"), ["_source/a.html: $no"], 'none');
    is_deeply(seo_for('_source/a.md' => "---\ntitle: A\n---\nA paragraph.\n"), [], 'the first paragraph of Markdown');
    is_deeply(seo_for('_source/a.html' => "---\ntitle: A\n---\n<p>An HTML paragraph is not an excerpt.</p>\n"), ["_source/a.html: $no"], 'HTML pages have no excerpt');
    is_deeply(seo_for('_source/a.html' => "---\ntitle: A\ndescription: " . ('d' x 160) . "\n---\n<p>x</p>\n"), [], '160 characters is fine');
    is_deeply(seo_for('_source/a.html' => "---\ntitle: A\ndescription: " . ('d' x 161) . "\n---\n<p>x</p>\n"),
        ['_source/a.html: the description is 161 characters long; search engines show about 160'], '161 is too long');
    is_deeply(seo_for('_source/a.md' => "---\ntitle: A\n---\n" . ('Word ' x 60) . "\n"), [], 'a long excerpt is not counted against the limit');
    is_deeply(seo_for('_source/a.md' => "---\ntitle: A\ndescription: [" . join(', ', ('long') x 50) . "]\n---\nShort.\n"), [],
        'a description that is a list is ignored, and the excerpt used');
    is_deeply(seo_for('_source/a.html' => "---\ntitle: A\ndescription: [x]\n---\n<div>x</div>\n"), ["_source/a.html: $no"],
        'a description that is a list does not count');
    is_deeply(seo_for('_source/a.html' => "---\ntitle: A\ndescription: Same.\n---\n<p>x</p>\n",
                      '_source/b.md'   => "---\ntitle: B\n---\nSame.\n"),
        ['_source/b.md: has the same description as _source/a.html; give each page its own'], 'a description and an excerpt can be the same');
};

subtest 'seo: pages that are skipped' => sub {
    my $no = 'has no description; add description to its front matter, or start it with a paragraph';
    is_deeply(seo_for(
        '_source/404.html'      => "---\ntitle: Gone\n---\n<div>x</div>\n",
        '_source/fr/404.html'   => "---\ntitle: Parti\n---\n<div>x</div>\n",
        '_source/hidden.html'   => "---\ntitle: Hidden\nsitemap: false\n---\n<div>x</div>\n",
        '_source/shown.html'    => "---\ntitle: Shown\nsitemap: true\n---\n<div>x</div>\n",
        '_source/data.html'     => "---\ntitle: Data\nextension: .json\n---\n{}\n",
    ), ["_source/shown.html: $no"], '404 pages, sitemap: false and non-HTML pages are skipped');
};

subtest 'seo: generated pages are skipped, but accessibility still applies' => sub {
    make_site({
        '_config.yml'       => "---\nname: x\nurl: https://example.com\ntag_pages:\n  layout: tag\n",
        '_layout/index.html' => $layout,
        '_layout/tag.html'  => "<html><title>Tags</title><img src=\"/t.png\"></html>",
        '_source/a.md'      => "---\ntitle: A\ntags: [x, y]\n---\nA.\n",
    });
    is_deeply(warnings_of('seo'), [], 'no duplicate titles or missing descriptions');
    is_deeply(warnings_of('accessibility'), [
        "tag_pages (x): the image /t.png $no_alt",
        '_layout/tag.html: the <html> tag has no lang attribute (for example <html lang="en">), so screen readers may read the page in the wrong language',
        "tag_pages (y): the image /t.png $no_alt",
    ], 'accessibility problems named by the setting; the layout once') or diag explain warnings_of('accessibility');
};

subtest 'check: settings' => sub {
    my %files = (
        '_layout/index.html' => $layout,
        '_source/a.html' => "---\ntitle: A\n---\n<img src=\"x.png\"><div>x</div>\n",
    );
    my $count = sub { my %by; $by{ $_->{type} }++ for @{ App::Dapper->new()->check()->{warnings} }; [ $by{accessibility} || 0, $by{seo} || 0 ] };
    make_site({ %files });
    is_deeply($count->(), [1, 1], 'both on by default');
    make_site({ %files, '_config.yml' => "---\nname: x\ncheck:\n  accessibility: false\n" });
    is_deeply($count->(), [0, 1], 'accessibility off');
    make_site({ %files, '_config.yml' => "---\nname: x\ncheck:\n  seo: no\n" });
    is_deeply($count->(), [1, 0], 'seo off');
    make_site({ %files, '_config.yml' => "---\nname: x\ncheck:\n  accessibility: off\n  seo: 0\n" });
    is_deeply($count->(), [0, 0], 'both off');
    make_site({ %files, '_config.yml' => "---\nname: x\ncheck: false\n" });
    is_deeply($count->(), [1, 1], 'check: false is not a map, so both stay on');
    make_site({ %files, '_config.yml' => "---\nname: x\ncheck:\n  accessibility: true\n  seo: true\n" });
    is_deeply($count->(), [1, 1], 'both on');
};

subtest 'pages that failed are not checked again' => sub {
    make_site({
        '_layout/index.html' => $layout,
        '_source/a.html' => "---\ntitle: A\nlayout: nope\n---\n<img src=\"x.png\">\n",
        '_source/b.html' => "---\ntitle: B\nurlpattern: /same.html\n---\n<img src=\"b.png\">\n",
        '_source/c.html' => "---\ntitle: C\nurlpattern: /same.html\n---\n<img src=\"c.png\">\n",
    });
    is_deeply(warnings_of('accessibility'), ["_source/b.html: the image b.png $no_alt"],
        'a page with no layout, and a page that lost its file, are left out');
};

done_testing();
