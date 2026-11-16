use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

sub warnings_of {
    my ($type) = @_;
    my $report = App::Dapper->new()->check();
    return [ sort map { "$_->{file}: $_->{message}" } grep { $_->{type} eq $type } @{ $report->{warnings} } ];
}

my $layout = qq{<html lang="en"><head><title>[% page.title %]</title></head><body>[% page.content %]</body></html>};

subtest 'accessibility' => sub {
    make_site({
        '_layout/index.html' => $layout,
        '_layout/bare.html'  => "<html><title>[% page.title %]</title>[% page.content %]</html>",
        '_source/a.md' => "---\ntitle: A\n---\nIntro.\n\n![](one.png) ![](one.png)\n\n<img src=\"two.png\">\n\n<img src=\"three.png\" alt=\"\">\n\n## Two\n\n#### Four\n\n[click here](/b.html), [Here.](/b.html), [<img src=\"three.png\" alt=\"\">](/b.html)\n",
        '_source/b.md' => "---\ntitle: B\nlayout: bare\n---\nFine. [The B page](/b.html) [<img src=\"one.png\" alt=\"B\">](/b.html) <a href=\"/b.html\" aria-label=\"B\"></a>\n",
        '_source/c.md' => "---\ntitle: C\nlayout: bare\n---\nAlso bare.\n\n```\n<img src=\"one.png\">\n```\n",
        '_source/one.png' => "PNG", '_source/two.png' => "PNG", '_source/three.png' => "PNG",
    });
    is_deeply(warnings_of('accessibility'), [
        '_layout/bare.html: the <html> tag has no lang attribute (for example <html lang="en">), so screen readers may read the page in the wrong language',
        '_source/a.md: the heading "Four" skips from h2 to h4; use h3',
        '_source/a.md: the image one.png has no alt text; describe it, or use alt="" if it is decoration',
        '_source/a.md: the image two.png has no alt text; describe it, or use alt="" if it is decoration',
        '_source/a.md: the link to /b.html has no text; add text, alt text to its image, or an aria-label',
        '_source/a.md: the link to /b.html says only "click here"; say where it goes instead',
        '_source/a.md: the link to /b.html says only "here"; say where it goes instead',
    ], 'each problem once, alt="" allowed, code ignored') or diag explain warnings_of('accessibility');
};

subtest 'seo' => sub {
    my $long = 'x' x 80;
    my $wordy = 'Words ' x 30;
    make_site({
        '_config.yml'        => "---\nname: x\nurl: https://example.com\n",
        '_layout/index.html' => $layout,
        '_source/a.md'       => "---\ntitle: Same\n---\nFirst paragraph.\n",
        '_source/b.md'       => "---\ntitle: Same\ndescription: First paragraph.\n---\nx\n",
        '_source/c.html'     => "---\ntitle: No description\n---\n<div>x</div>\n",
        '_source/d.md'       => "---\ntitle: $long\ndescription: $wordy\n---\nx\n",
        '_source/e.html'     => "---\ntitle: Hidden\nsitemap: false\n---\n<div>x</div>\n",
        '_source/404.html'   => "---\ntitle: Not found\n---\n<div>x</div>\n",
    });
    is_deeply(warnings_of('seo'), [
        '_source/b.md: has the same description as _source/a.md; give each page its own',
        '_source/b.md: has the same title as _source/a.md ("Same"); give each page its own',
        '_source/c.html: has no description; add description to its front matter, or start it with a paragraph',
        '_source/d.md: the description is 179 characters long; search engines show about 160',
        '_source/d.md: the title is 80 characters long; search engines show about 60',
    ], 'titles and descriptions; sitemap: false and 404 pages skipped') or diag explain warnings_of('seo');
};

subtest 'turned off' => sub {
    make_site({
        '_config.yml'    => "---\nname: x\ncheck:\n  accessibility: false\n  seo: false\n",
        '_source/a.html' => "---\ntitle: A\n---\n<img src=\"x.png\"><h1>a</h1><h3>c</h3>\n",
        '_source/x.png'  => "PNG",
    });
    is_deeply(warnings_of('accessibility'), [], 'no accessibility warnings');
    is_deeply(warnings_of('seo'), [], 'no seo warnings');
};

subtest 'pages after the first of a list are not compared' => sub {
    make_site({
        '_config.yml'        => "---\nname: x\n",
        '_layout/index.html' => $layout,
        '_source/index.html' => "---\ntitle: Home\ndescription: Home page.\npaginate:\n  category: blog\n  per_page: 1\n---\n<div>list</div>\n",
        map({ ("_source/p$_.md" => "---\ntitle: Post $_\ncategories: blog\n---\nPost $_.\n") } 1 .. 3),
    });
    is_deeply(warnings_of('seo'), [], 'no duplicate titles from page 2 and 3');
};

done_testing();
