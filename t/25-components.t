use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Markdown;
use App::Dapper::Components;

sub html { App::Dapper::Markdown::to_html(@_) }

subtest 'callouts' => sub {
    is(html(qq{::: warning "Before you start"\nBack up **first**.\n:::\n}),
        qq{<aside class="callout callout-warning" role="note">\n<p class="callout-title">Before you start</p>\n<p>Back up <strong>first</strong>.</p>\n</aside>\n},
        'with a title, Markdown inside');
    like(html("::: callout tip\nx\n:::\n"), qr{^<aside class="callout callout-tip" role="note">\n<p>x</p>\n</aside>}, 'callout with a kind');
    like(html("::: callout\nx\n:::\n"), qr{callout-note}, 'callout on its own is a note');
    like(html("Before.\n\n::: note\nx\n:::\n\nAfter.\n"), qr{<p>Before\.</p>\s*<aside[^>]*>\n<p>x</p>\n</aside>\s*<p>After\.</p>}, 'between paragraphs');
    is(html("::: note\nnever closed\n"), "<p>::: note\nnever closed</p>\n", 'left as text if never closed');
    like(html(qq{::: note "<b>&"\nx\n:::\n}), qr{<p class="callout-title">&lt;b&gt;&amp;</p>}, 'title escaped');
};

subtest 'details, gallery, nesting and code' => sub {
    is(html(qq{::: details "More"\n- a\n- b\n:::\n}),
        qq{<details>\n<summary>More</summary>\n<ul>\n<li>a</li>\n<li>b</li>\n</ul>\n</details>\n}, 'details');
    like(html("::: gallery\n![A](a.jpg)\n![B](b.jpg)\n:::\n"),
        qr{^<div class="gallery">\n<img src="a\.jpg" alt="A"[^>]*/>\n<img src="b\.jpg" alt="B"[^>]*/>\n</div>}, 'gallery without paragraphs');
    like(html(qq{:::: note\n::: details "Inner"\nhidden\n:::\n::::\n}),
        qr{<aside class="callout callout-note" role="note">\n<details>\n<summary>Inner</summary>\n<p>hidden</p>\n</details>\n</aside>}, 'nested with more colons');
    like(html("```\n::: note\nnot a component\n:::\n```\n"), qr{<pre><code>::: note\nnot a component\n:::\n</code></pre>}, 'left alone in code');
    like(html("::: note\n```perl\nmy \$x = 1;\n```\n:::\n"), qr{<aside[^>]*>\n<pre><code class="language-perl">my \$x = 1;\n</code></pre>\n</aside>}, 'code inside a component');
};

subtest 'single-line components' => sub {
    my $yt = qr{^<div class="video video-youtube"><iframe src="https://www\.youtube-nocookie\.com/embed/dQw4w9WgXcQ" title="Our story" loading="lazy" };
    like(html(qq{::: youtube https://www.youtube.com/watch?v=dQw4w9WgXcQ "Our story"\n}), $yt, 'YouTube from its address');
    like(html(qq{::: youtube https://youtu.be/dQw4w9WgXcQ "Our story"\n}), $yt, 'short address');
    like(html(qq{::: youtube dQw4w9WgXcQ\n}), qr{title="YouTube video"}, 'an ID, default title');
    like(html(qq{::: vimeo https://vimeo.com/76979871\n}), qr{src="https://player\.vimeo\.com/video/76979871"}, 'Vimeo');
    is(html(qq{::: button /contact/ "Get in touch"\n}), qq{<p><a class="button" href="/contact/">Get in touch</a></p>\n}, 'button');
    like(html(qq{::: button javascript:alert(1) "x"\n}), qr{component-error}, 'no javascript: links');
    is(html(qq{::: figure shop.jpg "The shop" "Open late"\n}),
        qq{<figure><img src="shop.jpg" alt="The shop">\n<figcaption>Open late</figcaption></figure>\n}, 'figure');
    like(html(qq{::: map "1 Main St, Springfield"\n}), qr{maps\.google\.com/maps\?q=1\+Main\+St%2C\+Springfield&amp;output=embed" title="Map of 1 Main St, Springfield"}, 'map');
    like(html(qq{::: youtube\n}), qr{<p class="component-error"><strong>::: youtube needs a video address or ID</strong></p>}, 'an error shows in the page');
    like(html("Text\n::: youtube dQw4w9WgXcQ\nmore\n"), qr{<p>Text</p>\s*<div class="video[^\n]*\s*<p>more</p>}, 'splits a paragraph');
};

subtest 'unknown components' => sub {
    my @unknown;
    like(html("::: nope\nx\n:::\n", { unknown => \@unknown }), qr{<p>::: nope}, 'left as text');
    is_deeply(\@unknown, ['nope'], 'reported');
    my ($text) = App::Dapper::Components::expand("a ::: note b\n", sub { '' }, {});
    is($text, "a ::: note b\n", 'colons inside a line are text');
};

subtest 'in a site, with components of your own' => sub {
    make_site({
        '_source/index.md' => "---\ntitle: Home\n---\n::: pricing plan=Pro \"Most popular\"\n**\$10** a month\n:::\n\n::: badge new\n\n::: note\nMine\n:::\n\n::: mystery\n",
        '_layout/components/pricing.html' => qq{<div class="price [% args.plan %]">[% args.1 %]: [% content %] ([% args.size %] args, on [% page.title %])</div>},
        '_layout/components/badge.html'   => qq{<span class="badge">[% FOR a IN args.list %][% a | upper %][% END %]</span>},
        '_layout/components/note.html'    => qq{<div class="my-note">[% content %]</div>},
    });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    my $html = slurp('_output/index.html');
    like($html, qr{<div class="price Pro">Most popular: <p><strong>\$10</strong> a month</p>\n \(2 args, on Home\)</div>}, 'a wrapping component of your own');
    like($html, qr{<span class="badge">NEW</span>}, 'a single-line component of your own');
    like($html, qr{<div class="my-note"><p>Mine</p>\n</div>}, 'a built-in one replaced');
    like(join('', @warnings), qr{_source/index\.md uses the component "::: mystery", which doesn't exist}, 'a warning for an unknown one');

    my $report = App::Dapper->new()->check();
    is_deeply([ map { $_->{type} } grep { $_->{message} =~ /mystery/ } @{$report->{warnings}} ], ['component'], 'in check');
};

subtest 'templates are not needed in content' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\n::: note\n[% site.name %]\n:::\n" });
    quiet_build();
    like(slurp('_output/index.html'), qr{<p>\[% site\.name %\]</p>}, 'content is still not run as a template');
};

done_testing();
