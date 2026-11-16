use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

binmode(Test::More->builder->$_, ':encoding(UTF-8)') for qw(output failure_output todo_output);

sub layouts_of {
    my (%files) = @_;
    make_site({ %files, '_source/x.md' => "---\n---\nx\n" });
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    $d->read_project();
    $d->read_templates();
    return $d->{layout_content};
}

subtest 'read_templates' => sub {
    my $layouts = layouts_of(
        '_layout/index.html'      => 'I[% page.content %]',
        '_layout/post.tt'         => 'P',
        '_layout/noext'           => 'N',
        '_layout/multi.dot.html'  => 'M',
        '_layout/.hidden.html'    => 'H',
        '_layout/sub/inner.html'  => 'S',
        '_layout/Zoë.html'        => 'Z',
    );
    is_deeply([sort keys %$layouts], [sort 'index', 'post', 'noext', 'multi.dot', 'Zoë'],
        'keyed by name without the extension; dot files and directories skipped');
    is($layouts->{index}, 'I[% page.content %]', 'content as written');
    is($layouts->{noext}, 'N', 'a layout without an extension');
    is($layouts->{'multi.dot'}, 'M', 'only the last extension is removed');

    $layouts = layouts_of('_layout/index.html' => 'html', '_layout/index.tt' => 'tt');
    is($layouts->{index}, 'tt', 'two files with one name: the later in sorted order wins');

    $layouts = layouts_of('_layout/empty.html' => '');
    is($layouts->{empty}, '', 'an empty layout');

    $layouts = layouts_of('_layout/fm.html' => "---\ndescription: x\n---\nBody");
    is($layouts->{fm}, "\nBody", 'front matter without a parent is removed');

    $layouts = layouts_of('_layout/nullparent.html' => "---\nlayout: ~\n---\nBody");
    is($layouts->{nullparent}, "\nBody", 'a null parent is no parent');

    $layouts = layouts_of('_layout/open.html' => "---\nlayout: x\nBody [% page.content %]");
    is($layouts->{open}, "---\nlayout: x\nBody [% page.content %]", 'unclosed front matter is just content');

    $layouts = layouts_of('_layout/notfm.html' => "----\nBody");
    is($layouts->{notfm}, "----\nBody", 'four dashes are content');

    # read_templates replaces what an earlier call read
    make_site({ '_layout/one.html' => '1', '_source/x.md' => "---\n---\nx\n" });
    my $d = App::Dapper->new();
    $d->read_project();
    $d->read_templates();
    unlink '_layout/one.html';
    spew('_layout/two.html', '2');
    $d->read_templates();
    is_deeply([sort keys %{ $d->{layout_content} }], ['index', 'two'], 'layouts are read afresh');
};

subtest 'nested layouts' => sub {
    my $layouts = layouts_of(
        '_layout/base.html'  => '<html>[% page.content %]</html>',
        '_layout/page.html'  => "---\nlayout: base\n---\n<main>[% page.content %]</main>",
        '_layout/post.html'  => "---\nlayout: page\n---\n<article>[% page.content %]</article>",
        '_layout/deep.html'  => "---\nlayout: post\n---\n<div>[% page.content %]</div>",
        '_layout/deeper.html' => "---\nlayout: deep\n---\n<span>[% page.content %]</span>",
    );
    is($layouts->{base}, '<html>[% page.content %]</html>', 'the base is unchanged');
    is($layouts->{page}, "<html>\n<main>[% page.content %]</main></html>", 'one level');
    is($layouts->{post}, "<html>\n<main>\n<article>[% page.content %]</article></main></html>", 'two levels');
    is($layouts->{deeper},
        "<html>\n<main>\n<article>\n<div>\n<span>[% page.content %]</span></div></article></main></html>",
        'four levels');
};

subtest 'every form of page.content is replaced' => sub {
    for my $tag ('[% page.content %]', '[%page.content%]', '[%- page.content -%]', '[%+ page.content +%]',
                 '[%= page.content =%]', '[%~ page.content ~%]', "[%   page.content\t%]", '[%- page.content %]') {
        my $layouts = layouts_of(
            '_layout/base.html'  => "<b>${tag}</b>",
            '_layout/child.html' => "---\nlayout: base\n---\nC",
        );
        is($layouts->{child}, "<b>\nC</b>", "replaces $tag");
    }

    my $layouts = layouts_of(
        '_layout/base.html'  => '[% page.content %]|[% page.content %]',
        '_layout/child.html' => "---\nlayout: base\n---\nC",
    );
    is($layouts->{child}, "\nC|\nC", 'every occurrence');

    $layouts = layouts_of(
        '_layout/base.html'  => '[% page.contents %][% page.content.length %][% PAGE.CONTENT %]',
        '_layout/child.html' => "---\nlayout: base\n---\nC",
    );
    is($layouts->{child}, '[% page.contents %][% page.content.length %][% PAGE.CONTENT %]',
        'other expressions are left alone');

    $layouts = layouts_of(
        '_layout/base.html'  => 'no content here',
        '_layout/child.html' => "---\nlayout: base\n---\nC",
    );
    is($layouts->{child}, 'no content here', 'a parent without page.content drops the child');

    $layouts = layouts_of(
        '_layout/base.html'  => '<[% page.content %]>',
        '_layout/child.html' => "---\nlayout: base\n---\n\$1 \\1 \$& \@x [% page.title %]",
    );
    is($layouts->{child}, "<\n\$1 \\1 \$& \@x [% page.title %]>", 'child content is inserted literally');
};

subtest 'nested layouts in a build' => sub {
    make_site({
        '_layout/base.html'  => "<html><title>[% page.title %]</title>[% page.content %]<footer>[% site.name %]</footer></html>",
        '_layout/post.html'  => "---\nlayout: base\ndescription: hidden\n---\n<h1>[% page.title %]</h1>[%- page.content -%][% page.description %]",
        '_source/a.md'       => "---\ntitle: Zoë\nlayout: post\n---\nHello\n",
        '_source/b.md'       => "---\ntitle: B\nlayout: base\n---\nBase\n",
    });
    quiet_build();
    is(slurp('_output/a.html'), "<html><title>Zoë</title>\n<h1>Zoë</h1><p>Hello</p>\n<footer>Test Site</footer></html>",
        'page and site variables reach every level; layout front matter does not');
    is(slurp('_output/b.html'), "<html><title>B</title><p>Base</p>\n<footer>Test Site</footer></html>", 'the base directly');
};

subtest 'a missing parent layout' => sub {
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    my $layouts = layouts_of('_layout/post.html' => "---\nlayout: nope\n---\nP[% page.content %]");
    is($layouts->{post}, "\nP[% page.content %]", 'the layout is used without a parent');
    is_deeply(\@warnings, [qq{warning: layout "post" names the layout "nope", which does not exist\n}], 'with a warning');

    @warnings = ();
    make_site({
        '_layout/post.html' => "---\nlayout: nope\n---\n<[% page.content %]>",
        '_source/a.md'      => "---\nlayout: post\n---\nA\n",
    });
    quiet_build();
    is(slurp('_output/a.html'), "\n<<p>A</p>\n>", 'a page using it still builds');
    is(scalar @warnings, 1, 'one warning per build');
};

subtest 'loops of layouts' => sub {
    make_site({
        '_layout/self.html' => "---\nlayout: self\n---\nS[% page.content %]",
        '_source/x.md'      => "---\n---\nx\n",
    });
    eval { quiet_build() };
    is($@, qq{error: layout "self" is part of a loop of layouts\n}, 'a layout that wraps itself');

    make_site({
        '_layout/a.html' => "---\nlayout: b\n---\nA[% page.content %]",
        '_layout/b.html' => "---\nlayout: c\n---\nB[% page.content %]",
        '_layout/c.html' => "---\nlayout: a\n---\nC[% page.content %]",
        '_layout/index.html' => '[% page.content %]',
        '_source/x.md'   => "---\n---\nx\n",
    });
    eval { quiet_build() };
    like($@, qr/^error: layout "[abc]" is part of a loop of layouts\n\z/, 'a loop of three, even when no page uses it');

    make_site({
        '_layout/a.html' => "---\nlayout: b\n---\nA[% page.content %]",
        '_layout/b.html' => "---\nlayout: base\n---\nB[% page.content %]",
        '_layout/c.html' => "---\nlayout: b\n---\nC[% page.content %]",
        '_layout/base.html' => '<[% page.content %]>',
        '_source/x.md'   => "---\nlayout: a\n---\nx\n",
    });
    eval { quiet_build() };
    is($@, '', 'two layouts sharing a parent is not a loop');
    is(slurp('_output/x.html'), "<\nB\nA<p>x</p>\n>", 'and renders');
};

subtest 'layout front matter errors' => sub {
    make_site({ '_layout/index.html' => "---\nlayout: [x\n---\nA", '_source/x.md' => "---\n---\nx" });
    eval { quiet_build() };
    like($@, qr/^error: could not parse front matter in "_layout\/index/, 'invalid YAML');
    like($@, qr/^error: could not parse front matter in "_layout\/index\.html"/, 'names the actual file');

    make_site({ '_layout/index.html' => "---\n- a\n---\nA", '_source/x.md' => "---\n---\nx" });
    eval { quiet_build() };
    like($@, qr/^error: front matter in "_layout\/index\.html" must be a set of key: value pairs/, 'a list');
};

subtest 'expand_layout called directly' => sub {
    make_site({ '_source/x.md' => "---\n---\nx" });
    my $d = App::Dapper->new();
    $d->read_project();
    my %raw = (
        outer => '[[% page.content %]]',
        inner => "---\nlayout: outer\n---\ni",
        plain => 'p',
    );
    is($d->expand_layout('inner', \%raw, {}), "[\ni]", 'expands the chain');
    is($d->expand_layout('plain', \%raw, {}), 'p', 'a layout without front matter');
    eval { $d->expand_layout('inner', \%raw, { inner => 1 }) };
    is($@, qq{error: layout "inner" is part of a loop of layouts\n}, 'a name already seen is a loop');
    eval { $d->expand_layout('inner', \%raw, { outer => 1 }) };
    is($@, qq{error: layout "outer" is part of a loop of layouts\n}, 'so is a parent already seen');
    is(scalar keys %raw, 3, 'the raw layouts are not changed');
};

subtest 'includes from the layout directory' => sub {
    make_site({
        '_layout/index.html'          => "[% page.content %][% INCLUDE partials/footer.html %][% PROCESS head.html %]",
        '_layout/partials/footer.html' => "<footer>[% site.name %] [% page.title %]</footer>",
        '_layout/head.html'           => "<head>[% page.title | upper %]</head>",
        '_source/a.md'                => "---\ntitle: a\n---\nA\n",
    });
    my $d = quiet_build();
    is(slurp('_output/a.html'), "<p>A</p>\n<footer>Test Site a</footer><head>A</head>", 'INCLUDE and PROCESS');
    ok(exists $d->{layout_content}->{head}, 'an included file is also a layout');
    ok(!exists $d->{layout_content}->{footer}, 'files in subdirectories are not');

    make_site({ '_layout/index.html' => "[% INCLUDE missing.html %]", '_source/a.md' => "---\n---\nA\n" });
    eval { quiet_build() };
    like($@, qr/^error: could not process _source\/a\.md with layout index: .*missing\.html/, 'a missing include');
};

done_testing();
