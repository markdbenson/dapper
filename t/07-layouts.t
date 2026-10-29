use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

subtest 'layouts can be nested several levels deep' => sub {
    make_site({
        '_layout/base.html'    => "<html>[% page.content %]</html>",
        '_layout/page.html'    => "---\nlayout: base\n---\n<main>[% page.content %]</main>",
        '_layout/post.html'    => "---\nlayout: page\n---\n<article>[%- page.content -%]</article>",
        '_source/index.md'     => "---\nlayout: post\n---\nHello\n",
    });
    quiet_build();
    like(slurp('_output/index.html'), qr{^<html>\s*<main>\s*<article><p>Hello</p>\s*</article></main></html>$},
        'three levels, including a chomped page.content');
};

subtest 'front matter is removed from layouts without a parent' => sub {
    make_site({
        '_layout/index.html' => "---\ndescription: top level\n---\n<body>[% page.content %]</body>",
        '_source/index.md'   => "---\ntitle: x\n---\nHi\n",
    });
    quiet_build();
    unlike(slurp('_output/index.html'), qr/description/, 'front matter not in output');
};

subtest 'a loop of layouts is an error' => sub {
    make_site({
        '_layout/a.html'   => "---\nlayout: b\n---\nA[% page.content %]",
        '_layout/b.html'   => "---\nlayout: a\n---\nB[% page.content %]",
        '_source/index.md' => "---\nlayout: a\n---\nHi\n",
    });
    eval { quiet_build() };
    like($@, qr/is part of a loop of layouts/, 'loop detected');
};

subtest 'includes from the layout directory' => sub {
    make_site({
        '_layout/include-footer.html' => "<footer>[% site.name %]</footer>",
        '_layout/index.html'          => "[% page.content %][% INCLUDE 'include-footer.html' %]",
        '_layout/partials/skip.html'  => "directories in the layout dir are ignored",
        '_source/index.md'            => "---\ntitle: x\n---\nHi\n",
    });
    quiet_build();
    like(slurp('_output/index.html'), qr{<footer>Test Site</footer>}, 'include rendered');
};

done_testing();
