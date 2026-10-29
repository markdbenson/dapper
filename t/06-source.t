use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

subtest 'files without front matter are copied as they are' => sub {
    my $binary = join('', map { chr } 0 .. 255) x 4;
    make_site({
        '_source/index.md'       => "---\ntitle: Home\n---\nhi\n",
        '_source/notes.txt'      => "just text\n",
        '_source/plain.md'       => "# Not a page\n",
    });
    spew('_source/files/archive.zip', $binary, ':raw');

    quiet_build();
    is(slurp('_output/notes.txt'), "just text\n", 'text file copied');
    is(slurp('_output/plain.md'), "# Not a page\n", 'markdown without front matter copied, not rendered');
    is(slurp('_output/files/archive.zip', ':raw'), $binary, 'binary file copied byte for byte');
};

subtest 'front matter edge cases' => sub {
    make_site({
        '_source/empty.md'  => "---\n---\nNo settings\n",
        '_source/dashes.md' => "---\ntitle: before---after\n---\nBody --- text\n",
        '_layout/index.html' => "[% page.title %]|[% page.content %]",
    });
    quiet_build();
    like(slurp('_output/empty.html'), qr{<p>No settings</p>}, 'empty front matter is allowed');
    like(slurp('_output/dashes.html'), qr{^before---after\|<p>Body --- text</p>}, '--- inside values and body');
};

subtest 'front matter errors name the file' => sub {
    make_site({ '_source/bad.md' => "---\ntitle: [oops\n---\nx\n" });
    eval { quiet_build() };
    like($@, qr{could not parse front matter in "_source/bad.md"}, 'invalid YAML');

    make_site({ '_source/open.md' => "---\ntitle: never closed\n" });
    eval { quiet_build() };
    like($@, qr{"_source/open.md" has front matter that is never closed}, 'unclosed front matter');

    make_site({ '_source/a.md' => "---\nlayout: nope\n---\nx\n" });
    eval { quiet_build() };
    like($@, qr{_source/a.md uses the layout "nope"}, 'unknown layout');
};

subtest 'dates' => sub {
    make_site({
        '_source/iso.md'   => "---\ndate: 2014-05-02T10:30:00\n---\nx\n",
        '_source/space.md' => "---\ndate: 2014-05-02 10:30:00\n---\nx\n",
        '_source/day.md'   => "---\ndate: 2014-05-02\n---\nx\n",
        '_source/tz.md'    => "---\ndate: 2014-05-02T10:30:00-05:00\n---\nx\n",
        '_layout/index.html' => "[% page.year %]-[% page.month %]-[% page.day %] [% page.hour %]:[% page.minute %]",
    });
    quiet_build();
    is(slurp('_output/iso.html'), '2014-05-02 10:30', 'ISO 8601');
    is(slurp('_output/space.html'), '2014-05-02 10:30', 'pre-0.19 format with a space');
    is(slurp('_output/day.html'), '2014-05-02 00:00', 'date only');
    is(slurp('_output/tz.html'), '2014-05-02 10:30', 'with a time zone');

    make_site({ '_source/bad.md' => "---\ndate: last tuesday\n---\nx\n" });
    eval { quiet_build() };
    like($@, qr{could not understand the date "last tuesday" in "_source/bad.md"}, 'bad date names the file');
};

subtest 'categories are sorted by date' => sub {
    make_site({
        '_source/b.md' => "---\ntitle: Second\ncategories: blog\ndate: 2020-02-01\n---\nx\n",
        '_source/a.md' => "---\ntitle: Third\ncategories: blog\ndate: 2020-03-01\n---\nx\n",
        '_source/c.md' => "---\ntitle: First\ncategories: blog\ndate: 2020-01-01\n---\nx\n",
        '_layout/index.html' => "[% FOR p IN site.categories.blog %][% p.title %] [% END %]",
    });
    quiet_build();
    is(slurp('_output/blog/2020/01/first/index.html'), 'First Second Third ', 'oldest first');
};

subtest 'markdown, excerpts and unicode' => sub {
    make_site({
        '_source/index.md' => "---\ntitle: Café\n---\nFirst paragraph — with ünïcode.\n\nSecond.\n",
        '_layout/index.html' => "[% page.title %]|[% page.excerpt %]|[% page.slug %]",
    });
    quiet_build();
    is(slurp('_output/index.html'), 'Café|<p>First paragraph — with ünïcode.</p>|cafe', 'unicode survives');
};

subtest 'template statements in source files are rendered' => sub {
    make_site({
        '_config.yml'      => "---\nname: Site\nfooter: \"[% site.name %] footer\"\n",
        '_source/index.md' => "---\ntitle: Home\n---\nIn [% site.name %]\n",
        '_layout/index.html' => "[% page.content %][% site.footer %]",
    });
    quiet_build();
    is(slurp('_output/index.html'), "<p>In Site</p>\nSite footer", 'source and config templates rendered');
};

done_testing();
