use utf8;
use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Markdown;
use App::Dapper::Components;

# The built-in components, every argument form, and how they are found

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw/ output failure_output todo_output /;

sub html { App::Dapper::Markdown::to_html(@_) }
sub built_in { App::Dapper::Components::built_in(@_) }
sub aside { my ($kind, $title, $inner) = @_; qq{<aside class="callout callout-$kind" role="note">\n} . (defined $title ? qq{<p class="callout-title">$title</p>\n} : '') . "$inner</aside>\n" }
sub err { my ($text) = @_; qq{<p class="component-error"><strong>$text</strong></p>\n} }
my $allow = 'allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; fullscreen" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe></div>';
sub yt { my ($id, $title) = @_; qq{<div class="video video-youtube"><iframe src="https://www.youtube-nocookie.com/embed/$id" title="$title" loading="lazy" $allow\n} }
sub vm { my ($id, $title) = @_; qq{<div class="video video-vimeo"><iframe src="https://player.vimeo.com/video/$id" title="$title" loading="lazy" $allow\n} }

subtest 'names' => sub {
    is_deeply([ App::Dapper::Components::names() ],
        [qw/ button callout caution details figure gallery important info map note tip vimeo warning youtube /], 'every built-in, sorted');
};

subtest 'callouts' => sub {
    for my $kind (qw/ note tip warning important caution info /) {
        is(html("::: $kind\nx\n:::\n"), aside($kind, undef, "<p>x</p>\n"), "::: $kind");
        is(html("::: callout $kind\nx\n:::\n"), aside($kind, undef, "<p>x</p>\n"), "::: callout $kind");
    }
    is(html("::: callout\nx\n:::\n"), aside('note', undef, "<p>x</p>\n"), 'callout alone is a note');
    is(html("::: callout TIP\nx\n:::\n"), aside('tip', undef, "<p>x</p>\n"), 'the kind in capitals');
    is(html("::: callout Just a title\nx\n:::\n"), aside('note', 'Just a title', "<p>x</p>\n"), 'callout with a title but no kind');
    is(html(qq{::: callout warning "A title"\nx\n:::\n}), aside('warning', 'A title', "<p>x</p>\n"), 'callout, kind and title');
    is(html(qq{::: callout "tip"\nx\n:::\n}), aside('tip', undef, "<p>x</p>\n"), 'a quoted kind is still the kind');
    is(html(qq{::: important "Read me"\nx\n:::\n}), aside('important', 'Read me', "<p>x</p>\n"), 'a quoted title');
    is(html("::: info Two words\nx\n:::\n"), aside('info', 'Two words', "<p>x</p>\n"), 'words without quotes are joined');
    is(html(qq{::: tip "a" b "c d"\nx\n:::\n}), aside('tip', 'a b c d', "<p>x</p>\n"), 'several arguments joined with spaces');
    is(html("::: tip 'single quotes'\nx\n:::\n"), aside('tip', 'single quotes', "<p>x</p>\n"), 'single quotes');
    is(html(qq{::: note ""\nx\n:::\n}), aside('note', undef, "<p>x</p>\n"), 'an empty title is no title');
    is(html(qq{::: note "unbalanced\nx\n:::\n}), aside('note', '&quot;unbalanced', "<p>x</p>\n"), 'an unbalanced quote is kept');
    is(html(qq{::: note "<b>&\\"</b>"\nx\n:::\n}), aside('note', '&lt;b&gt;&amp;&quot;&lt;/b&gt;', "<p>x</p>\n"), 'the title is escaped');
    is(html("::: NOTE\nx\n:::\n"), aside('note', undef, "<p>x</p>\n"), 'the name in capitals');
    is(html(":::note\nx\n:::\n"), aside('note', undef, "<p>x</p>\n"), 'no space after the colons');
    is(html("::: note   \nx\n:::   \n"), aside('note', undef, "<p>x</p>\n"), 'spaces at the ends of lines');
    is(html("::: note\t\"Tabbed\"\nx\n:::\n"), aside('note', 'Tabbed', "<p>x</p>\n"), 'a tab before the title');
    is(html("::::: note\nx\n:::::\n"), aside('note', undef, "<p>x</p>\n"), 'more colons, closed by as many');
    is(html("   ::: note\n   x\n   :::\n"), aside('note', undef, "<p>x</p>\n"), 'indented up to three spaces');
    is(html("    ::: note\n    x\n    :::\n"), "<pre><code>::: note\nx\n:::\n</code></pre>\n", 'four spaces is code');
    is(html("::: note\n:::\n"), aside('note', undef, ''), 'empty');
    is(html("::: note\n\n\n:::\n"), aside('note', undef, "\n"), 'only blank lines');
    is(html("::: warning\nOne.\n\nTwo *and* [a link](/x/).\n:::\n"),
        aside('warning', undef, qq{<p>One.</p>\n\n<p>Two <em>and</em> <a href="/x/">a link</a>.</p>\n}), 'Markdown inside');
    is(html("::: note\n# Heading\n:::\n"), aside('note', undef, qq{<h1 id="heading">Heading</h1>\n}), 'a heading inside');
};

subtest 'never closed' => sub {
    is(html("::: note\nnever closed\n"), "<p>::: note\nnever closed</p>\n", 'a callout');
    is(html("::: details \"x\"\nnever closed\n"), qq{<p>::: details "x"\nnever closed</p>\n}, 'details');
    is(html("::: gallery\n![A](a.jpg)\n"), qq{<p>::: gallery\n<img src="a.jpg" alt="A" id="a" /></p>\n}, 'a gallery');
    is(html("::: note\nx\n::::\n"), "<p>::: note\nx\n::::</p>\n", 'closed by the wrong number of colons');
    is(html("::::note\nx\n:::\n"), "<p>::::note\nx\n:::</p>\n", 'fewer colons do not close it');
    is(html("::: note\nx\n::: \t\n"), aside('note', undef, "<p>x</p>\n"), 'whitespace after closing colons is fine');
    is(html("::: note\nx\n:::x\n"), "<p>::: note\nx\n:::x</p>\n", 'closing colons followed by text do not close');
    is(html("::: note\n::: tip\nx\n:::\n"), "<p>::: note</p>\n\n" . aside('tip', undef, "<p>x</p>\n"),
        'another component with as many colons opening first: the first is left as text');
    is(html("::: details \"a\"\n::: note\ninner\n:::\n:::\n"),
        qq{<p>::: details "a"</p>\n\n} . aside('note', undef, "<p>inner</p>\n") . "\n<p>:::</p>\n", 'nesting needs more colons on the outside');
};

subtest 'nesting' => sub {
    is(html(qq{:::: note\n::: details "Inner"\nhidden\n:::\n::::\n}),
        qq{<aside class="callout callout-note" role="note">\n<details>\n<summary>Inner</summary>\n<p>hidden</p>\n</details>\n</aside>\n}, 'two deep');
    is(html(qq{::::: note\n:::: tip\n::: details "D"\ndeep\n:::\n::::\n:::::\n}),
        qq{<aside class="callout callout-note" role="note">\n<aside class="callout callout-tip" role="note">\n<details>\n<summary>D</summary>\n<p>deep</p>\n</details>\n</aside>\n</aside>\n},
        'three deep');
    is(html(qq{:::: note\n::: tip\na\n:::\n::: warning\nb\n:::\n::::\n}),
        qq{<aside class="callout callout-note" role="note">\n} . aside('tip', undef, "<p>a</p>\n") . "\n" . aside('warning', undef, "<p>b</p>\n") . "</aside>\n",
        'two side by side inside another');
    is(html(qq{:::: note\n::: youtube dQw4w9WgXcQ\n::::\n}),
        qq{<aside class="callout callout-note" role="note">\n} . yt('dQw4w9WgXcQ', 'YouTube video') . "</aside>\n", 'a single-line one inside');
    is(html(qq{:::: gallery\n::: figure a.jpg "A" "Cap"\n::: figure b.jpg "B"\n::::\n}),
        qq{<div class="gallery">\n<figure><img src="a.jpg" alt="A">\n<figcaption>Cap</figcaption></figure>\n\n<figure><img src="b.jpg" alt="B"></figure>\n</div>\n},
        'figures in a gallery');
};

subtest 'around other Markdown' => sub {
    is(html("Para\n::: note\nx\n:::\n"), "<p>Para</p>\n\n" . aside('note', undef, "<p>x</p>\n"), 'right after a paragraph');
    is(html("::: note\nx\n:::\nAfter\n"), aside('note', undef, "<p>x</p>\n") . "\n<p>After</p>\n", 'right before one');
    is(html("Before.\n\n::: note\nx\n:::\n\nAfter.\n"), "<p>Before.</p>\n\n" . aside('note', undef, "<p>x</p>\n") . "\n<p>After.</p>\n", 'between paragraphs');
    is(html("::: note\na\n:::\n::: tip\nb\n:::\n"), aside('note', undef, "<p>a</p>\n") . "\n" . aside('tip', undef, "<p>b</p>\n"), 'one after another');
    is(html("- one\n- two\n\n::: note\nx\n:::\n"), "<ul>\n<li>one</li>\n<li>two</li>\n</ul>\n\n" . aside('note', undef, "<p>x</p>\n"), 'after a list');
    is((App::Dapper::Components::expand("a ::: note b\nx :::\n", sub { die }, {}))[0], "a ::: note b\nx :::\n", 'colons in the middle of a line are text');
    is(html("::: 123\n"), "<p>::: 123</p>\n", 'a name must start with a letter');
    is(html("> ::: note\n> x\n> :::\n"), "<blockquote>\n  <p>::: note\n  x\n  :::</p>\n</blockquote>\n", 'not inside a blockquote');
    is(html("```\n::: note\nnot a component\n:::\n```\n"), "<pre><code>::: note\nnot a component\n:::\n</code></pre>\n", 'not inside fenced code');
    is(html("~~~\n::: youtube dQw4w9WgXcQ\n~~~\n"), "<pre><code>::: youtube dQw4w9WgXcQ\n</code></pre>\n", 'or tildes');
    is(html("::: note\n```\n:::\n```\n:::\n"), aside('note', undef, "<pre><code>:::\n</code></pre>\n"), 'colons in code inside one do not close it');
    is(html("::: note\n```perl\nmy \$x = 1;\n```\n:::\n"), aside('note', undef, qq{<pre><code class="language-perl">my \$x = 1;\n</code></pre>\n}), 'code inside');

    my $in_list = html("1. one\n2. two\n   ::: note\n   x\n   :::\n3. three\n");
    TODO: {
        local $TODO = 'a component indented under a list item ends the list instead of going inside the item';
        like($in_list, qr{<li>two\s*<aside class="callout callout-note" role="note">\n<p>x</p>\n</aside>\s*</li>}, 'inside a list item');
        unlike($in_list, qr{</ol>.*<ol>}s, 'the list is not split in two');
    }
    is($in_list, "<ol>\n<li>one</li>\n<li>two</li>\n</ol>\n\n" . aside('note', undef, "<p>x</p>\n") . "\n<ol>\n<li>three</li>\n</ol>\n",
        'what happens now: the list is split around it');
};

subtest 'details' => sub {
    is(html("::: details\nx\n:::\n"), "<details>\n<summary>Details</summary>\n<p>x</p>\n</details>\n", 'default summary');
    is(html(qq{::: details "Show the full list"\n- a\n- b\n:::\n}),
        "<details>\n<summary>Show the full list</summary>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n</details>\n", 'summary and list');
    is(html("::: details More info\nx\n:::\n"), "<details>\n<summary>More info</summary>\n<p>x</p>\n</details>\n", 'words without quotes');
    is(html(qq{::: details "<script>"\nx\n:::\n}), "<details>\n<summary>&lt;script&gt;</summary>\n<p>x</p>\n</details>\n", 'escaped');
    is(html("::: DETAILS\nx\n:::\n"), "<details>\n<summary>Details</summary>\n<p>x</p>\n</details>\n", 'in capitals');
    is(html("::: details\n:::\n"), "<details>\n<summary>Details</summary>\n</details>\n", 'empty');
};

subtest 'gallery' => sub {
    is(html("::: gallery\n![A](a.jpg)\n![B](b.jpg)\n:::\n"),
        qq{<div class="gallery">\n<img src="a.jpg" alt="A" id="a" />\n<img src="b.jpg" alt="B" id="b" />\n</div>\n}, 'paragraphs removed');
    is(html("::: gallery\n![A](a.jpg)\n\n![B](b.jpg)\n:::\n"),
        qq{<div class="gallery">\n<img src="a.jpg" alt="A" id="a" />\n\n<img src="b.jpg" alt="B" id="b" />\n</div>\n}, 'with blank lines between');
    is(html("::: gallery Title ignored\n![A](a.jpg)\n:::\n"), qq{<div class="gallery">\n<img src="a.jpg" alt="A" id="a" />\n</div>\n}, 'arguments are ignored');
    is(html("::: gallery\nSome *text*\n:::\n"), qq{<div class="gallery">\nSome <em>text</em>\n</div>\n}, 'text loses its paragraph too');
    is(html("::: gallery\n:::\n"), qq{<div class="gallery">\n</div>\n}, 'empty');
};

subtest 'YouTube' => sub {
    my $id = 'dQw4w9WgXcQ';
    is(html("::: youtube https://www.youtube.com/watch?v=$id\n"), yt($id, 'YouTube video'), 'watch address, default title');
    is(html(qq{::: youtube https://www.youtube.com/watch?v=$id "Our story"\n}), yt($id, 'Our story'), 'with a title');
    is(html(qq{::: youtube $id Two words\n}), yt($id, 'Two words'), 'a title without quotes');
    is(html(qq{::: youtube $id "Rock & <roll>"\n}), yt($id, 'Rock &amp; &lt;roll&gt;'), 'the title is escaped');
    is(html(qq{::: YouTube $id\n}), yt($id, 'YouTube video'), 'the name in capitals');
    is(html(qq{::: youtube\n}), err('::: youtube needs a video address or ID'), 'no video');
    is(html(qq{::: youtube abc\n}), err('::: youtube needs a video address or ID'), 'too short for an ID');
    is(html(qq{::: youtube https://example.com/video\n}), err('::: youtube needs a video address or ID'), 'another site');
    is(html("Text\n::: youtube $id\nmore\n"), "<p>Text</p>\n\n" . yt($id, 'YouTube video') . "\n<p>more</p>\n", 'splits a paragraph');
    is(html("::: youtube $id\n:::\n"), yt($id, 'YouTube video') . "\n<p>:::</p>\n", 'single-line: colons after it are text');
};

subtest 'Vimeo' => sub {
    is(html("::: vimeo https://vimeo.com/76979871\n"), vm('76979871', 'Vimeo video'), 'address, default title');
    is(html(qq{::: vimeo 76979871 "A short film"\n}), vm('76979871', 'A short film'), 'an ID and a title');
    is(html(qq{::: vimeo nope\n}), err('::: vimeo needs a video address or ID'), 'not an ID');
    is(html(qq{::: vimeo\n}), err('::: vimeo needs a video address or ID'), 'nothing');
};

subtest 'video IDs' => sub {
    my $id = 'dQw4w9WgXcQ';
    my %youtube = (
        "https://www.youtube.com/watch?v=$id"                      => $id,
        "http://youtube.com/watch?v=$id"                            => $id,
        "https://m.youtube.com/watch?v=$id&t=42s"                   => $id,
        "https://www.youtube.com/watch?feature=share&v=$id"         => $id,
        "https://www.youtube.com/watch?v=$id&list=PL123&index=2"    => $id,
        "https://youtu.be/$id"                                      => $id,
        "https://youtu.be/$id?t=10"                                 => $id,
        "https://youtu.be/$id?si=abcdef"                            => $id,
        "https://www.youtube.com/embed/$id"                         => $id,
        "https://www.youtube.com/embed/$id?start=5"                 => $id,
        "https://www.youtube-nocookie.com/embed/$id"                => $id,
        "https://www.youtube.com/shorts/$id"                        => $id,
        "https://www.youtube.com/live/$id?feature=share"            => $id,
        "www.youtube.com/watch?v=$id"                               => $id,
        $id                                                         => $id,
        'a-b_c-d_e-f'                                               => 'a-b_c-d_e-f',
        'abcdef'                                                    => 'abcdef',
        'abcde'                                                     => undef,
        'https://www.youtube.com/watch?v=abc'                       => undef,
        'https://www.youtube.com/playlist?list=PL0123456789'        => undef,
        'https://example.com/'                                      => undef,
        'not an id'                                                 => undef,
        ''                                                          => undef,
    );
    for my $url (sort keys %youtube) {
        is(App::Dapper::Components::video_id('youtube', $url), $youtube{$url}, "youtube: '$url'");
    }
    is(App::Dapper::Components::video_id('youtube', undef), undef, 'youtube: nothing');

    my %vimeo = (
        'https://vimeo.com/76979871'                   => '76979871',
        'http://vimeo.com/76979871'                    => '76979871',
        'https://www.vimeo.com/76979871'               => '76979871',
        'https://vimeo.com/76979871#t=30s'             => '76979871',
        'https://vimeo.com/76979871?share=copy'        => '76979871',
        'https://player.vimeo.com/video/76979871'      => '76979871',
        'https://player.vimeo.com/video/76979871?h=ab' => '76979871',
        '76979871'                                     => '76979871',
        '1'                                            => '1',
        'abc'                                          => undef,
        '7697987a'                                     => undef,
        'https://vimeo.com/about'                      => undef,
        'https://example.com/76979871'                 => undef,
        ''                                             => undef,
    );
    for my $url (sort keys %vimeo) {
        is(App::Dapper::Components::video_id('vimeo', $url), $vimeo{$url}, "vimeo: '$url'");
    }
    is(App::Dapper::Components::video_id('vimeo', undef), undef, 'vimeo: nothing');
    is(App::Dapper::Components::video_id('vimeo', 'https://vimeo.com/channels/staffpicks/76979871'), '76979871', 'vimeo: a channel address');
    is(App::Dapper::Components::video_id('vimeo', 'https://vimeo.com/groups/shortfilms/videos/76979871'), '76979871', 'vimeo: a group address');
};

subtest 'button' => sub {
    is(html(qq{::: button /contact/ "Get in touch"\n}), qq{<p><a class="button" href="/contact/">Get in touch</a></p>\n}, 'button');
    is(html(qq{::: button https://example.com/ Sign up now\n}), qq{<p><a class="button" href="https://example.com/">Sign up now</a></p>\n}, 'label without quotes');
    is(html(qq{::: button "/a b/" "x"\n}), qq{<p><a class="button" href="/a b/">x</a></p>\n}, 'a quoted address');
    is(html(qq{::: button /a?b=1&c="2" "<Go>"\n}), qq{<p><a class="button" href="/a?b=1&amp;c=2">&lt;Go&gt;</a></p>\n}, 'escaped (quotes in the address are removed as an argument)');
    is(html(qq{::: button mailto:me\@example.com "Mail"\n}), qq{<p><a class="button" href="mailto:me\@example.com">Mail</a></p>\n}, 'mailto:');
    is(html(qq{::: button #top "Up"\n}), qq{<p><a class="button" href="#top">Up</a></p>\n}, 'a fragment');
    is(html(qq{::: button tel:+15551234 "Call"\n}), qq{<p><a class="button" href="tel:+15551234">Call</a></p>\n}, 'tel:');
    for my $bad ('javascript:alert(1)', 'JavaScript:alert(1)', 'JAVASCRIPT:x', 'vbscript:msgbox', 'data:text/html,hi', 'Data:x') {
        is(html(qq{::: button $bad "x"\n}), err('::: button needs a web address'), "no $bad");
    }
    is(html(qq{::: button /x/\n}), err('::: button needs an address and a label'), 'no label');
    is(html(qq{::: button\n}), err('::: button needs an address and a label'), 'nothing');
};

subtest 'figure' => sub {
    is(html(qq{::: figure shop.jpg "The shop" "Open late"\n}), qq{<figure><img src="shop.jpg" alt="The shop">\n<figcaption>Open late</figcaption></figure>\n}, 'with a caption');
    is(html(qq{::: figure shop.jpg "The shop"\n}), qq{<figure><img src="shop.jpg" alt="The shop"></figure>\n}, 'without a caption');
    is(html(qq{::: figure shop.jpg Shop open late on Fridays\n}), qq{<figure><img src="shop.jpg" alt="Shop">\n<figcaption>open late on Fridays</figcaption></figure>\n}, 'unquoted: the first word is the alt text, the rest the caption');
    is(html(qq{::: figure shop.jpg ""\n}), qq{<figure><img src="shop.jpg" alt=""></figure>\n}, 'empty alt text is allowed');
    is(html(qq{::: figure "a&b.jpg" "<alt>" "\\"cap\\""\n}), qq{<figure><img src="a&amp;b.jpg" alt="&lt;alt&gt;">\n<figcaption>&quot;cap&quot;</figcaption></figure>\n}, 'escaped');
    is(html(qq{::: figure /img/x.png "X"\n}), qq{<figure><img src="/img/x.png" alt="X"></figure>\n}, 'an absolute path');
    is(html(qq{::: figure https://cdn.example.com/x.png "X"\n}), qq{<figure><img src="https://cdn.example.com/x.png" alt="X"></figure>\n}, 'a full address');
    is(html(qq{::: figure shop.jpg\n}), err('::: figure needs an image and its alt text'), 'no alt text');
    is(html(qq{::: figure\n}), err('::: figure needs an image and its alt text'), 'nothing');
    is(html(qq{::: figure javascript:x "alt"\n}), err('::: figure needs an image address'), 'no javascript:');
    is(html(qq{::: figure data:image/png;base64,AAAA "alt"\n}), err('::: figure needs an image address'), 'no data:');
};

subtest 'map' => sub {
    my $map = sub { my ($q, $title) = @_; qq{<div class="map"><iframe src="https://maps.google.com/maps?q=$q&amp;output=embed" title="Map of $title" loading="lazy" referrerpolicy="no-referrer-when-downgrade"></iframe></div>\n} };
    is(html(qq{::: map "1 Main St, Springfield"\n}), $map->('1+Main+St%2C+Springfield', '1 Main St, Springfield'), 'quoted');
    is(html(qq{::: map Eiffel Tower\n}), $map->('Eiffel+Tower', 'Eiffel Tower'), 'unquoted words joined');
    is(html(qq{::: map "A & B <C>"\n}), $map->('A+%26+B+%3CC%3E', 'A &amp; B &lt;C&gt;'), 'escaped in the address and the title');
    is(html(qq{::: map a-b_c.d~e\n}), $map->('a-b_c.d~e', 'a-b_c.d~e'), 'characters left as they are');
    is(html(qq{::: map 50/50 #1 ?x=y\n}), $map->('50%2F50+%231+%3Fx%3Dy', '50/50 #1 ?x=y'), 'other characters escaped');
    is(html(qq{::: map\n}), err('::: map needs an address or place'), 'nothing');
    is(html(qq{::: map ""\n}), err('::: map needs an address or place'), 'empty');
    my $unicode = html(qq{::: map 東京 Café\n});
    like($unicode, qr{title="Map of 東京 Café"}, 'the title keeps its characters');
    like($unicode, qr{\?q=%E6%9D%B1%E4%BA%AC\+Caf%C3%A9&amp;}, 'the address is escaped as UTF-8');
};

subtest 'unknown and built_in directly' => sub {
    my @unknown;
    is(html("::: nope\nx\n:::\n", { unknown => \@unknown }), "<p>::: nope\nx\n:::</p>\n", 'left as text');
    is_deeply(\@unknown, ['nope'], 'reported');
    @unknown = ();
    html("::: Nope\n::: nope a\n::: other\n::: note\nx\n:::\n", { unknown => \@unknown });
    is_deeply(\@unknown, ['nope', 'nope', 'other'], 'each use, lowercased');
    @unknown = ();
    html("```\n::: hidden\n```\n", { unknown => \@unknown });
    is_deeply(\@unknown, [], 'not in code');
    is(html("::: my-thing_2 a\n"), "<p>::: my-thing_2 a</p>\n", 'names with dashes and underscores');
    is(html("::: nope\n"), "<p>::: nope</p>\n", 'no list to report to: fine');

    is(built_in('nope', [], ''), '<p class="component-error"><strong>::: nope is not a component</strong></p>', 'built_in: not a component');
    is(built_in('note', ['A', 'B'], "<p>x</p>\n"), qq{<aside class="callout callout-note" role="note">\n<p class="callout-title">A B</p>\n<p>x</p>\n</aside>}, 'built_in: a callout');
    is(built_in('callout', ['caution'], ''), qq{<aside class="callout callout-caution" role="note">\n</aside>}, 'built_in: callout caution');
    is(built_in('callout', ['Nope', 'x'], ''), qq{<aside class="callout callout-note" role="note">\n<p class="callout-title">Nope x</p>\n</aside>}, 'built_in: not a kind, so a title');
    is(built_in('map', ['a b'], ''), qq{<div class="map"><iframe src="https://maps.google.com/maps?q=a+b&amp;output=embed" title="Map of a b" loading="lazy" referrerpolicy="no-referrer-when-downgrade"></iframe></div>}, 'built_in: map');
};

subtest 'parse_args' => sub {
    my $p = sub { [ App::Dapper::Components::parse_args(@_) ] };
    is_deeply($p->(undef), [], 'nothing');
    is_deeply($p->(''), [], 'empty');
    is_deeply($p->('a b c'), ['a', 'b', 'c'], 'words');
    is_deeply($p->('  a   b  '), ['a', 'b'], 'extra spaces');
    is_deeply($p->('a "b c" d'), ['a', 'b c', 'd'], 'double quotes');
    is_deeply($p->("'x y' z"), ['x y', 'z'], 'single quotes');
    is_deeply($p->('a\ b'), ['a b'], 'an escaped space');
    is_deeply($p->('""'), [''], 'an empty quoted argument');
    is_deeply($p->('k=v "a b"'), ['k=v', 'a b'], 'name=value');
    is_deeply($p->('x="1 2"'), ['x=1 2'], 'name="value with spaces"');
    is_deeply($p->("it's"), ["it's"], 'an unbalanced quote: split on spaces instead');
    is_deeply($p->(qq{say "hi there}), ['say', '"hi', 'there'], 'an unclosed quote');
};

subtest 'template lookup' => sub {
    is(App::Dapper::Components::template({}, 'note'), undef, 'no layout directory');
    make_site({
        '_layout/components/a.html' => 'A html', '_layout/components/a.tt' => 'A tt',
        '_layout/components/b.htm'  => 'B htm',  '_layout/components/b.tt' => 'B tt',
        '_layout/components/c.tt'   => 'C tt',
    });
    my $t = sub { App::Dapper::Components::template({ layout => '_layout' }, @_) };
    is($t->('a'), '_layout/components/a.html', '.html first');
    is($t->('b'), '_layout/components/b.htm', 'then .htm');
    is($t->('c'), '_layout/components/c.tt', 'then .tt');
    is($t->('d'), undef, 'none');
    is(App::Dapper::Components::template({ layout => 'nowhere' }, 'a'), undef, 'a layout directory that does not exist');
};

subtest 'expand' => sub {
    my ($text, $html) = App::Dapper::Components::expand("Before\n::: tip T\nx\n:::\nAfter", sub { "<<$_[0]>>" }, {});
    is($text, "Before\n\nDAPPERCOMPONENT0\n\nAfter", 'placeholders');
    is_deeply($html, [qq{<aside class="callout callout-tip" role="note">\n<p class="callout-title">T</p>\n<<x>></aside>}], 'and their HTML');
    ($text, $html) = App::Dapper::Components::expand("::: note\n:::\n", sub { die "not called for an empty body\n" }, {});
    is_deeply($html, [qq{<aside class="callout callout-note" role="note">\n</aside>}], 'an empty body is not converted');
    ($text, $html) = App::Dapper::Components::expand("plain\ntext", sub { die }, {});
    is($text, "plain\ntext", 'nothing to expand');
    is_deeply($html, [], 'no HTML');
};

subtest 'in a site' => sub {
    make_site({
        '_source/index.md' => "---\ntitle: Home\n---\n::: mystery\n\n::: mystery again\n\n::: other\n\n```\n::: hidden\n```\n\n::: tip \"Hi\"\nThere\n:::\n",
        '_source/page.html' => "---\ntitle: HTML\n---\n<p>::: note</p>\n",
    });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    my $names = join(', ', App::Dapper::Components::names());
    is_deeply(\@warnings, [
        qq{warning: _source/index.md uses the component "::: mystery", which doesn't exist; the built-in ones are $names, and others can be added in _layout/components\n},
        qq{warning: _source/index.md uses the component "::: other", which doesn't exist; the built-in ones are $names, and others can be added in _layout/components\n},
    ], 'one warning for each unknown name, not in code');
    like(slurp('_output/index.html'), qr{<aside class="callout callout-tip" role="note">\n<p class="callout-title">Hi</p>\n<p>There</p>\n</aside>}, 'built');
    is(slurp('_output/page.html'), "<title>HTML</title>\n<p>::: note</p>\n", 'not in HTML pages');
};

done_testing();
