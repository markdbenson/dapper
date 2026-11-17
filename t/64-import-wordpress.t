use utf8;
use 5.010;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Import;

# Importing a WordPress export file

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw/ output failure_output todo_output /;

my $VIDEO_ALLOW = 'loading="lazy" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; fullscreen" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe></div>';
sub yt { qq{<div class="video video-youtube"><iframe src="https://www.youtube-nocookie.com/embed/$_[0]" title="YouTube video" $VIDEO_ALLOW} }
sub vm { qq{<div class="video video-vimeo"><iframe src="https://player.vimeo.com/video/$_[0]" title="Vimeo video" $VIDEO_ALLOW} }

# project(%files) - A new Dapper project (with a post layout unless told
# otherwise) and a directory for the export
sub project {
    my (%opt) = @_;
    my $old = tempdir(CLEANUP => 1);
    make_site($opt{no_post_layout} ? {} : { '_layout/post.html' => "<article>[% page.content %]</article>" });
    return $old;
}

# run_import(kind, from, options) - Import quietly, or with the output
# captured (loud => 1), returning the state and the output
sub run_import {
    my ($kind, $from, %options) = @_;
    my $loud = delete $options{loud};
    my $d = App::Dapper->new();
    $d->{quiet} = $loud ? 0 : 1;
    my $out = '';
    open(my $fh, '>', \$out) or die;
    my $old = select $fh;
    my $state = eval { $d->import_from($kind, $from, %options) };
    my $error = $@;
    select $old;
    close $fh;
    die $error if $error;
    return wantarray ? ($state, $out) : $state;
}

sub item {
    my (%f) = @_;
    my $xml = "  <item>\n";
    $xml .= "    <title>$f{title}</title>\n" if defined $f{title};
    $xml .= "    <link>$f{link}</link>\n" if defined $f{link};
    $xml .= "    <content:encoded><![CDATA[$f{content}]]></content:encoded>\n" if defined $f{content};
    $xml .= "    <excerpt:encoded><![CDATA[$f{excerpt}]]></excerpt:encoded>\n" if defined $f{excerpt};
    $xml .= "    <wp:post_id>$f{id}</wp:post_id>\n" if defined $f{id};
    $xml .= "    <wp:post_date><![CDATA[$f{date}]]></wp:post_date>\n" if defined $f{date};
    $xml .= "    <wp:post_name><![CDATA[$f{slug}]]></wp:post_name>\n" if defined $f{slug};
    $xml .= "    <wp:status><![CDATA[$f{status}]]></wp:status>\n" if defined $f{status};
    $xml .= "    <wp:post_type><![CDATA[$f{type}]]></wp:post_type>\n" if defined $f{type};
    $xml .= "    $_\n" for @{ $f{extra} || [] };
    return "$xml  </item>\n";
}

sub export {
    my ($old, @items) = @_;
    spew("$old/export.xml", qq{<?xml version="1.0" encoding="UTF-8" ?>\n<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:wp="http://wordpress.org/export/1.2/" xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/">\n<channel>\n<title>Old</title>\n<wp:wxr_version>1.2</wp:wxr_version>\n}
        . join('', @items) . "</channel>\n</rss>\n");
    return "$old/export.xml";
}

subtest 'a post, exactly' => sub {
    my $old = project();
    my $file = export($old, item(
        title => 'Hello &amp; welcome', link => 'https://old.example.com/2019/05/hello-world/', id => 1,
        date => '2019-05-01 10:30:00', slug => 'hello-world', status => 'publish', type => 'post',
        content => "First line\nsecond line\n\nAnother paragraph.", excerpt => "<p>A <b>short</b>\n hello.</p>",
        extra => [
            '<category domain="category" nicename="news"><![CDATA[News]]></category>',
            '<category domain="category" nicename="uncategorized"><![CDATA[Uncategorized]]></category>',
            '<category domain="category" nicename="perl"><![CDATA[Perl]]></category>',
            '<category domain="post_tag" nicename="hi"><![CDATA[hi]]></category>',
            '<category domain="post_tag" nicename="qa">Q&amp;A</category>',
            '<category domain="nav_menu" nicename="main"><![CDATA[Main menu]]></category>',
        ]));
    my $state = run_import('wordpress', $file);
    is(slurp('_source/blog/hello-world.html'), <<'HTML', 'the whole file');
---
title: Hello & welcome
date: 2019-05-01T10:30:00
layout: post
categories:
- News
- Perl
tags:
- hi
- Q&A
description: A short hello.
urlpattern: /2019/05/hello-world/
---
<p>First line<br>
second line</p>

<p>Another paragraph.</p>
HTML
    is_deeply($state->{pages}, [{ file => '_source/blog/hello-world.html', kind => 'post', draft => 0 }], 'the summary');
    is($state->{to}, 'blog', 'posts go in blog');
    is_deeply($state->{skipped}, [], 'nothing skipped');
    is_deeply($state->{notes}, {}, 'nothing to note');
};

subtest 'statuses and post types' => sub {
    my $old = project();
    my $file = export($old,
        item(title => 'Published', slug => 'published', status => 'publish', type => 'post', link => 'https://x.com/published/', content => 'x'),
        item(title => 'Draft', slug => 'draft', status => 'draft', type => 'post', link => 'https://x.com/draft/', content => 'x'),
        item(title => 'Pending', slug => 'pending', status => 'pending', type => 'post', link => 'https://x.com/pending/', content => 'x'),
        item(title => 'Private', slug => 'private', status => 'private', type => 'post', link => 'https://x.com/private/', content => 'x'),
        item(title => 'Future', slug => 'future', status => 'future', type => 'post', link => 'https://x.com/future/', content => 'x', date => '2999-01-01 00:00:00'),
        item(title => 'Trash', slug => 'trash', status => 'trash', type => 'post', content => 'x'),
        item(title => 'Auto', slug => 'auto', status => 'auto-draft', type => 'post', content => 'x'),
        item(title => 'Inherit', slug => 'inherit', status => 'inherit', type => 'post', content => 'x'),
        item(title => 'No status', slug => 'no-status', type => 'post', content => 'x'),
        item(title => 'No type', slug => 'no-type', status => 'publish', content => 'x'),
        item(title => 'A page', slug => 'a-page', status => 'publish', type => 'page', link => 'https://x.com/parent/a-page/', content => 'x'),
        item(title => 'Draft page', slug => 'draft-page', status => 'draft', type => 'page', content => 'x'),
        item(title => 'Photo', slug => 'photo', status => 'inherit', type => 'attachment'),
        item(title => 'Menu', slug => 'menu', status => 'publish', type => 'nav_menu_item'),
        item(title => 'Product', slug => 'product', status => 'publish', type => 'product', content => 'x'),
        item(title => 'Block', slug => 'block', status => 'publish', type => 'wp_block', content => 'x'),
    );
    my ($state, $out) = run_import('wordpress', $file, loud => 1);
    is_deeply([ map { "$_->{file} $_->{kind} $_->{draft}" } @{$state->{pages}} ], [
        '_source/blog/published.html post 0', '_source/blog/draft.html post 1', '_source/blog/pending.html post 1',
        '_source/blog/private.html post 1', '_source/blog/future.html post 0', '_source/blog/no-status.html post 0',
        '_source/blog/no-type.html post 0', '_source/a-page.html page 0', '_source/draft-page.html page 1',
    ], 'what was imported, in order');
    my $front = sub { (App::Dapper::Utils::split_frontmatter(slurp($_[0]), $_[0]))[0] };
    is($front->('_source/blog/draft.html')->{draft}, 1, 'a draft');
    ok(!exists $front->('_source/blog/draft.html')->{urlpattern}, 'with no address');
    ok(!exists $front->('_source/blog/published.html')->{draft}, 'published posts have no draft key');
    is($front->('_source/blog/future.html')->{urlpattern}, '/future/', 'a scheduled post keeps its address');
    is($front->('_source/blog/future.html')->{date}, '2999-01-01T00:00:00', 'and its date');
    is($front->('_source/a-page.html')->{urlpattern}, '/parent/a-page/', 'a page keeps its address');
    ok(!exists $front->('_source/a-page.html')->{layout}, 'pages get no layout');
    ok(!-e "_source/blog/$_.html", "no $_") for qw/ trash auto inherit photo menu product block /;
    is($out, qq{Imported 7 posts and 2 pages into _source (4 as drafts).\nRun "dapper check" to find links that need fixing.\n}, 'the report');
};

subtest 'slugs and addresses' => sub {
    my $old = project();
    my $file = export($old,
        item(title => 'No Slug: Here!', slug => '', id => 5, status => 'publish', type => 'post', link => 'https://x.com/?p=5', content => 'x'),
        item(title => '', slug => '', id => 6, status => 'publish', type => 'post', content => 'x'),
        item(title => '!!!', status => 'publish', type => 'post', content => 'x'),
        item(slug => 'untitled', status => 'publish', type => 'post', content => 'x'),
        item(title => 'Page id', slug => 'page-id', status => 'publish', type => 'page', link => 'https://x.com/?page_id=9', content => 'x'),
        item(title => 'Query', slug => 'query', status => 'publish', type => 'post', link => 'https://x.com/2020/query/?utm_source=x#c', content => 'x'),
        item(title => 'Bare', slug => 'bare', status => 'publish', type => 'post', link => 'https://x.com', content => 'x'),
        item(title => 'Relative', slug => 'relative', status => 'publish', type => 'post', link => 'relative/path/', content => 'x'),
        item(title => 'Empty link', slug => 'empty-link', status => 'publish', type => 'post', link => '', content => 'x'),
        item(title => 'Same', slug => 'same', status => 'publish', type => 'post', link => 'https://x.com/a/', content => 'one'),
        item(title => 'Same', slug => 'same', status => 'publish', type => 'post', link => 'https://x.com/b/', content => 'two'),
        item(title => 'Same', slug => 'same', status => 'publish', type => 'post', link => 'https://x.com/c/', content => 'three'),
        item(title => 'Same page', slug => 'same', status => 'publish', type => 'page', content => 'page'),
    );
    my $state = run_import('wordpress', $file);
    my @files = map { $_->{file} } @{$state->{pages}};
    is_deeply(\@files, [ map { "_source/$_" } qw( blog/no-slug-here.html blog/post-6.html blog/post-2.html blog/untitled.html page-id.html
        blog/query.html blog/bare.html blog/relative.html blog/empty-link.html blog/same.html blog/same-2.html blog/same-3.html same.html ) ], 'file names');
    my $front = sub { (App::Dapper::Utils::split_frontmatter(slurp($_[0]), $_[0]))[0] };
    ok(!exists $front->('_source/blog/no-slug-here.html')->{urlpattern}, '?p= addresses are not kept');
    ok(!exists $front->('_source/page-id.html')->{urlpattern}, '?page_id= addresses are not kept');
    is($front->('_source/blog/query.html')->{urlpattern}, '/2020/query/', 'query and fragment removed');
    is($front->('_source/blog/bare.html')->{urlpattern}, '/', 'the home page address');
    is($front->('_source/blog/relative.html')->{urlpattern}, '/relative/path/', 'a relative address gets a slash');
    ok(!exists $front->('_source/blog/empty-link.html')->{urlpattern}, 'an empty link');
    ok(!exists $front->('_source/blog/post-6.html')->{title}, 'an empty title is left out');
    is($front->('_source/blog/untitled.html')->{title}, undef, 'no title at all');
    like(slurp('_source/blog/same-2.html'), qr{<p>two</p>}, 'the second of the same name');
    like(slurp('_source/blog/same-3.html'), qr{<p>three</p>}, 'the third');
};

subtest 'entities, CDATA and dates' => sub {
    my $old = project();
    my $file = export($old,
        item(title => 'Q&amp;A: &lt;tags&gt; &#8217;quotes&#8217; &#x2014; &quot;x&quot; &#39;y&#39; &apos;z&apos; &amp;lt;', slug => 'entities',
             status => 'publish', type => 'post', date => '0000-00-00 00:00:00', content => 'x',
             extra => ['<category domain="category" nicename="a"><![CDATA[A &amp; B]]></category>']),
        item(title => '<![CDATA[Raw &amp; kept]]>', slug => 'cdata', status => 'publish', type => 'post', date => 'not a date', content => 'x'),
        item(title => 'Dated', slug => 'dated', status => 'publish', type => 'post', date => '2021-12-31 23:59:59', content => 'x'),
        item(title => 'Unicode – ü', slug => 'unicode', status => 'publish', type => 'post', content => "Caf\x{e9} \x{2014} \x{1F600}"),
    );
    run_import('wordpress', $file);
    my $front = sub { (App::Dapper::Utils::split_frontmatter(slurp($_[0]), $_[0]))[0] };
    is($front->('_source/blog/entities.html')->{title}, qq{Q&A: <tags> \x{2019}quotes\x{2019} \x{2014} "x" 'y' 'z' &lt;}, 'entities decoded once');
    ok(!exists $front->('_source/blog/entities.html')->{date}, 'a zero date is left out');
    is($front->('_source/blog/cdata.html')->{title}, 'Raw &amp; kept', 'CDATA is taken as it is');
    ok(!exists $front->('_source/blog/cdata.html')->{date}, 'a date that cannot be read is left out');
    is($front->('_source/blog/dated.html')->{date}, '2021-12-31T23:59:59', 'a date');
    is($front->('_source/blog/unicode.html')->{title}, "Unicode \x{2013} \x{fc}", 'characters outside ASCII in the title');
    like(slurp('_source/blog/unicode.html'), qr{<p>Caf\x{e9} \x{2014} \x{1F600}</p>}, 'and the body');
    is_deeply($front->('_source/blog/entities.html')->{categories}, ['A & B'], 'category names are decoded');
};

subtest 'classic content and blocks' => sub {
    my $old = project();
    my $file = export($old,
        item(title => 'Classic', slug => 'classic', status => 'publish', type => 'post',
             content => "  One\ntwo  \n\n\n\nThree\n \n<iframe src=\"x\"></iframe>\n\n<em>inline</em> start"),
        item(title => 'Mixed', slug => 'mixed', status => 'publish', type => 'post', content => "Text\n\n<div class=\"d\">kept</div>\n\n<figure>f</figure>"),
        item(title => 'Has blocks', slug => 'blocks', status => 'publish', type => 'post',
             content => "<!-- wp:paragraph -->\n<p>Made with blocks.</p>\n<!-- /wp:paragraph -->\n\n<!-- wp:image {\"id\":1} -->\n<figure class=\"wp-block-image\"><img src=\"a.jpg\"/></figure>\n<!-- /wp:image -->\n\nLoose\nline"),
        item(title => 'HTML', slug => 'html', status => 'publish', type => 'post', content => "<h2>Title</h2>\nText\n\nMore"),
        item(title => 'Empty', slug => 'empty', status => 'publish', type => 'post', content => ''),
        item(title => 'None', slug => 'none', status => 'publish', type => 'post'),
    );
    my $state = run_import('wordpress', $file);
    my $body = sub { my $b = (App::Dapper::Utils::split_frontmatter(slurp($_[0]), $_[0]))[1]; $b =~ s/^\n//; $b };
    is($body->('_source/blog/classic.html'),
        qq{<p>One<br>\ntwo</p>\n\n<p>Three</p>\n\n<iframe src="x"></iframe>\n\n<p><em>inline</em> start</p>\n},
        'paragraphs and line breaks; an iframe is left alone');
    is($body->('_source/blog/mixed.html'), qq{Text\n\n<div class="d">kept</div>\n\n<figure>f</figure>\n}, 'a div or figure anywhere means no paragraphs are added');
    is($body->('_source/blog/blocks.html'),
        qq{<p>Made with blocks.</p>\n\n<figure class="wp-block-image"><img src="a.jpg"/></figure>\n\nLoose\nline\n}, 'block comments removed, no paragraphs added');
    is($body->('_source/blog/html.html'), "<h2>Title</h2>\nText\n\nMore\n", 'HTML with headings is left as it is');
    is($body->('_source/blog/empty.html'), "\n", 'empty content');
    is($body->('_source/blog/none.html'), "\n", 'no content');
};

subtest 'captions, embeds and notes' => sub {
    my $old = project();
    my $file = export($old,
        item(title => 'Media', slug => 'media', status => 'publish', type => 'post', content => join("\n\n",
            '[caption id="attachment_1" align="alignnone" width="300"]<img src="https://old.example.com/wp-content/uploads/cat.jpg" alt="Cat"> A cat[/caption]',
            '[caption id="c"]<a href="big.jpg"><img src="small.jpg" alt="S"></a> Linked [/caption]',
            '[caption]No image here[/caption]',
            '[embed]https://www.youtube.com/watch?v=dQw4w9WgXcQ[/embed]',
            '[embed width="500"]https://vimeo.com/123456[/embed]',
            '[embed]https://example.com/page[/embed]',
            'https://youtu.be/dQw4w9WgXcQ',
            '  https://vimeo.com/987654  ',
            'https://example.com/not-a-video',
            'See https://youtu.be/dQw4w9WgXcQ in a sentence.',
            '[gallery ids="1,2"] and [contact-form-7 id="3" title="x"] and [gallery]',
        )),
        item(title => 'Plain', slug => 'plain', status => 'publish', type => 'post', content => 'Hello [b]bold[/b]'),
    );
    my ($state, $out) = run_import('wordpress', $file, loud => 1);
    my $body = (App::Dapper::Utils::split_frontmatter(slurp('_source/blog/media.html'), 'x'))[1];
    $body =~ s/^\n//;
    is($body, join("\n\n",
        '<figure><img src="https://old.example.com/wp-content/uploads/cat.jpg" alt="Cat"><figcaption>A cat</figcaption></figure>',
        '<figure><a href="big.jpg"><img src="small.jpg" alt="S"></a><figcaption>Linked</figcaption></figure>',
        '<p>No image here</p>',
        yt('dQw4w9WgXcQ'), vm('123456'),
        '<p>https://example.com/page</p>',
        yt('dQw4w9WgXcQ'), vm('987654'),
        '<p>https://example.com/not-a-video</p>',
        '<p>See https://youtu.be/dQw4w9WgXcQ in a sentence.</p>',
        '<p>[gallery ids="1,2"] and [contact-form-7 id="3" title="x"] and [gallery]</p>',
    ) . "\n", 'captions become figures, video addresses become videos');
    is_deeply($state->{notes}, {
        'WordPress shortcodes that were left as text: [contact-form-7], [gallery]' => ['_source/blog/media.html'],
        'images that still load from the old WordPress site (wp-content/uploads); copy them into the site' => ['_source/blog/media.html'],
        'WordPress shortcodes that were left as text: [b]' => ['_source/blog/plain.html'],
    }, 'notes, with the page each is on');
    is($out, "Imported 2 posts and 0 pages into _source.\n"
        . "Check: WordPress shortcodes that were left as text: [b] (1 page, such as _source/blog/plain.html)\n"
        . "Check: WordPress shortcodes that were left as text: [contact-form-7], [gallery] (1 page, such as _source/blog/media.html)\n"
        . "Check: images that still load from the old WordPress site (wp-content/uploads); copy them into the site (1 page, such as _source/blog/media.html)\n"
        . qq{Run "dapper check" to find links that need fixing.\n}, 'the report');

    my $old2 = project();
    my $file2 = export($old2, map { item(title => "P$_", slug => "p$_", status => 'publish', type => 'post', content => '[x]') } 1 .. 3);
    my (undef, $out2) = run_import('wordpress', $file2, loud => 1);
    like($out2, qr{^Check: WordPress shortcodes that were left as text: \[x\] \(3 pages, such as _source/blog/p1\.html\)$}m, 'the same note on several pages');

    my $old3 = project();
    my $file3 = export($old3, item(title => 'Mixed', slug => 'mixed', status => 'publish', type => 'post',
        content => "[embed]https://vimeo.com/111111[/embed]\nhttps://example.com/x\nNo blank line"));
    run_import('wordpress', $file3);
    is(do { (my $b = slurp('_source/blog/mixed.html')) =~ s/^---\n.*?---\n//s; $b }, vm('111111') . "\nhttps://example.com/x\nNo blank line\n",
        'a block that starts with a video is not put in a paragraph');
};

subtest 'layouts, --to and dry runs' => sub {
    my $old = project(no_post_layout => 1);
    my $file = export($old, item(title => 'A', slug => 'a', status => 'publish', type => 'post', content => 'x'),
                            item(title => 'B', slug => 'b', status => 'draft', type => 'page', content => 'x'));
    my ($state, $out) = run_import('wordpress', $file, to => '/posts/', dry_run => 1, loud => 1);
    is_deeply([ map { $_->{file} } @{$state->{pages}} ], ['_source/posts/a.html', '_source/b.html'], 'into --to, with slashes trimmed');
    ok(!-e '_source/posts/a.html', 'nothing written');
    is($out, "Would import 1 post and 1 page into _source (1 as drafts).\n", 'the report says would');

    run_import('wordpress', $file, to => 'news/archive');
    ok(-f '_source/news/archive/a.html', 'a deeper --to');
    unlike(slurp('_source/news/archive/a.html'), qr/layout:/, 'no post layout in the project: none given');
};

subtest 'importing again' => sub {
    my $old = project();
    my $file = export($old, map { item(title => "P$_", slug => "p$_", status => 'publish', type => 'post', content => 'x') } 1 .. 12);
    run_import('wordpress', $file);
    spew('_source/blog/p1.html', "mine\n");
    my ($state, $out) = run_import('wordpress', $file, loud => 1);
    is(scalar @{$state->{pages}}, 0, 'nothing written');
    is(scalar @{$state->{skipped}}, 12, 'twelve left alone');
    is(slurp('_source/blog/p1.html'), "mine\n", 'a changed file is not overwritten');
    is($out, "Imported 0 posts and 0 pages into _source.\nLeft alone 12 files that already exist:\n"
        . join('', map { "  _source/blog/p$_.html\n" } 1 .. 10) . "  ...\n", 'the report lists ten and then ...');

    my $old2 = project();
    my $file2 = export($old2, item(title => 'One', slug => 'one', status => 'publish', type => 'post', content => 'x'));
    run_import('wordpress', $file2);
    my (undef, $out2) = run_import('wordpress', $file2, loud => 1);
    is($out2, "Imported 0 posts and 0 pages into _source.\nLeft alone 1 file that already exist:\n  _source/blog/one.html\n", 'one file');
};

subtest 'errors' => sub {
    my $old = project();
    eval { run_import('wordpress', $old) };
    is($@, "error: give the WordPress export file (Tools, Export in WordPress), not a directory\n", 'a directory');
    spew("$old/feed.xml", "<rss><channel><item><title>x</title></item></channel></rss>\n");
    eval { run_import('wordpress', "$old/feed.xml") };
    is($@, "error: $old/feed.xml is not a WordPress export file\n", 'an RSS feed that is not an export');
    spew("$old/other.xml", "<wp:thing/>\n");
    eval { run_import('wordpress', "$old/other.xml") };
    is($@, "error: $old/other.xml is not a WordPress export file\n", 'not RSS');
    eval { run_import('wordpress', "$old/missing.xml") };
    is($@, "error: \"$old/missing.xml\" doesn't exist\n", 'missing');
    eval { run_import('WordPress', "$old/missing.xml") };
    is($@, "error: \"$old/missing.xml\" doesn't exist\n", 'the kind in capitals');
    eval { run_import(undef, $old) };
    is($@, "error: say what to import from: dapper import <hugo|jekyll|medium|wordpress> <file or directory>\n", 'no kind');
    eval { run_import('wordpress', undef) };
    is($@, "error: say what to import from: dapper import <hugo|jekyll|medium|wordpress> <file or directory>\n", 'no file');
    eval { run_import('blogger', $old) };
    is($@, "error: Dapper can't import from \"blogger\"; it can import from hugo, jekyll, medium, wordpress\n", 'unknown kind');
    is_deeply([ App::Dapper::Import::kinds() ], [qw/ hugo jekyll medium wordpress /], 'kinds');

    my $empty = export($old);
    my ($state, $out) = run_import('wordpress', $empty, loud => 1);
    is($out, "Imported 0 posts and 0 pages into _source.\n", 'an export with nothing in it');
};

subtest 'fitting the folder\'s schema' => sub {
    # As in the blog starter: posts must be in "blog", with a title
    my $old = project();
    spew('_source/blog/_schema.yml', <<'YAML');
required: [title, categories]
fields:
  title: { type: string, max_length: 20 }
  categories: { type: list, values: [blog, news] }
  tags: { type: list }
  description: { type: string, max_length: 30 }
YAML
    my $cat = sub { qq{<category domain="category" nicename="x"><![CDATA[$_[0]]]></category>} };
    my $tag = sub { qq{<category domain="post_tag" nicename="x"><![CDATA[$_[0]]]></category>} };
    my $file = export($old,
        item(title => 'One', slug => 'one', type => 'post', date => '2020-01-01 00:00:00', content => 'x',
             extra => [ $cat->('News'), $cat->('Classic'), $cat->('Markup'), $tag->('markup'), $tag->('perl') ]),
        item(title => 'Two', slug => 'two', type => 'post', date => '2020-01-02 00:00:00', content => 'x',
             extra => [ $cat->('news'), $tag->('Perl'), $tag->('MARKUP') ]),
        item(title => '', slug => 'three', type => 'post', date => '2020-01-03 00:00:00', content => 'x',
             excerpt => 'A description that is much too long for the schema'),
        item(title => 'A title far longer than twenty', slug => 'four', type => 'post', date => '2020-01-04 00:00:00', content => 'x'),
        item(title => 'Page', slug => 'page', type => 'page', content => 'x', extra => [ $cat->('Classic') ]),
    );
    my ($state, $out) = run_import('wordpress', $file, loud => 1);
    my $front = sub { my ($f) = App::Dapper::Utils::split_frontmatter(slurp($_[0]), $_[0]); $f };

    my $one = $front->('_source/blog/one.html');
    is_deeply($one->{categories}, ['blog'], 'with no allowed category left ("News" is not "news"), it gets the first allowed one');
    is_deeply($one->{tags}, ['markup', 'perl', 'News', 'Classic'], 'other categories become tags, without a second "markup"');

    is_deeply($front->('_source/blog/two.html')->{categories}, ['news'], 'an allowed category stays');
    is_deeply($front->('_source/blog/two.html')->{tags}, ['perl', 'markup'], 'tags take the spelling first seen in the import');
    my $three = $front->('_source/blog/three.html');
    is($three->{title}, 'Untitled', 'a missing title becomes "Untitled"');
    is_deeply($three->{categories}, ['blog'], 'a post without a category gets the first allowed one');
    is($three->{description}, "A description that is much\x{2026}", 'a long description is shortened at a word');
    is($front->('_source/blog/four.html')->{title}, "A title far longer\x{2026}", 'so is a long title');
    is_deeply($front->('_source/page.html')->{categories}, ['Classic'], 'a page outside the folder is left alone');
    like($out, qr/^Check: categories its folder's _schema\.yml doesn't allow, kept as tags \(1 page, such as _source\/blog\/one\.html\)$/m, 'noted');
    like($out, qr/^Check: pages without a title, now called "Untitled" \(1 page/m, 'noted');
    like($out, qr/^Check: pages given "categories: blog", which its folder's _schema\.yml requires \(2 pages/m, 'noted');
    like($out, qr/^Check: "title" shortened to the 20 characters its folder's _schema\.yml allows \(1 page/m, 'noted');
    is(App::Dapper->new()->check()->{ok}, 1, 'and the site checks clean');

    # Without free tags, categories that don't fit are left out
    project();
    spew('_source/blog/_schema.yml', "fields:\n  categories: { type: list, values: [blog] }\n  tags: { type: list, values: [a] }\n");
    ($state, $out) = run_import('wordpress', export($old, item(title => 'X', slug => 'x', type => 'post', content => 'x', extra => [ $cat->('Other') ])), loud => 1);
    is_deeply($front->('_source/blog/x.html')->{categories}, undef, 'not required, so no category is added');
    like($out, qr/^Check: values of "categories" its folder's _schema\.yml doesn't allow, left out/m, 'noted');
};

subtest 'non-ASCII addresses and the posts page' => sub {
    my $old = project();
    spew('_config.yml', "---\nname: x\ncategory_pages:\n  layout: index\n");
    my $file = export($old,
        item(title => 'Greek', slug => '%ce%b5%cf%80%ce%af%cf%80%ce%b5%ce%b4%ce%bf-2', type => 'page', content => 'x',
             link => 'https://old.example.com//greek/%ce%b5%cf%80%ce%af%cf%80%ce%b5%ce%b4%ce%bf-2/'),
        item(title => 'Blog', slug => 'blog', type => 'page', content => 'Posts', link => 'https://old.example.com/blog/'),
        item(title => 'Slash', slug => 'a%2fb', type => 'page', content => 'x', link => 'https://old.example.com/a%2Fb/'),
    );
    my ($state, $out) = run_import('wordpress', $file, loud => 1);
    my $greek = "\x{3b5}\x{3c0}\x{3af}\x{3c0}\x{3b5}\x{3b4}\x{3bf}-2";
    my $name = App::Dapper::Utils::name_bytes("_source/$greek.html");
    ok(-f $name, 'the file is named in Greek letters');
    like(slurp($name), qr{^urlpattern: /greek/$greek/$}m, 'and so is its address, with one slash');
    ok(!-e '_source/blog.html', 'the posts page is left out where the project makes the list');
    like($out, qr{^Check: pages at the address of the list of posts \(/blog/\), left out since the project makes that list \(1 page, such as blog\.html\)$}m, 'noted');
    like(slurp('_source/a%2fb.html'), qr{^urlpattern: /a%2Fb/$}m, 'encoded ASCII is left as it is');

    project();
    run_import('wordpress', $file);
    ok(-f '_source/blog.html', 'kept without category pages');
};

subtest 'helpers' => sub {
    my $state = { source => '_source', taken => { '_source/README' => 1, '_source/a.b/c' => 1 }, pages => [], skipped => [], dry_run => 1 };
    App::Dapper::Import::add_page($state, '/README', [[ title => 'x' ]], '');
    App::Dapper::Import::add_page($state, 'a.b/c', [[ draft => 1 ]], '');
    is_deeply($state->{pages}, [{ file => '_source/README-2', kind => 'page', draft => 0 }, { file => '_source/a.b/c-2', kind => 'page', draft => 1 }],
        'add_page: a second file without an extension gets -2');
    is(App::Dapper::Import::front_matter([[ a => undef ], [ b => [] ], [ c => '' ], [ draft => 0 ], [ d => 0 ], [ e => 'x' ]]), "d: 0\ne: x\n",
        'front_matter: empty values and draft: 0 left out');

    my $d = \&App::Dapper::Import::decode_entities;
    is($d->(undef), '', 'decode_entities: nothing');
    is($d->('&amp;lt;'), '&lt;', 'decode_entities: &amp; last');
    is($d->('&#65;&#x42;&#X43;&#039;'), "ABC'", 'decode_entities: numbers');
    my $s = \&App::Dapper::Import::strip_tags;
    is($s->(undef), '', 'strip_tags: nothing');
    is($s->("  <p>A <b>b</b>\n\n c&amp;d </p> "), 'A b c&d', 'strip_tags');
    my $u = \&App::Dapper::Import::url_path;
    is($u->(undef), undef, 'url_path: nothing');
    is($u->(''), undef, 'url_path: empty');
    is($u->('HTTPS://Example.com/a/b/?x=1#y'), '/a/b/', 'url_path: a full address');
    is($u->('ftp://example.com'), '/', 'url_path: no path');
    is($u->('a/b'), '/a/b', 'url_path: relative');
    is($u->('https://example.com//a///b/'), '/a/b/', 'url_path: doubled slashes');
    my $dp = \&App::Dapper::Import::decode_path;
    is($dp->(undef), undef, 'decode_path: nothing');
    is($dp->('a%20b%2F'), 'a%20b%2F', 'decode_path: encoded ASCII stays');
    is($dp->('caf%C3%A9'), "caf\x{e9}", 'decode_path: UTF-8 letters');
    is($dp->("\x{e9}%C3%A9"), "\x{e9}\x{e9}", 'decode_path: next to letters already decoded');
    is($dp->('%E9t%E9'), '%E9t%E9', 'decode_path: not UTF-8, left as it is');
    my $ds = \&App::Dapper::Import::date_string;
    is($ds->(undef), undef, 'date_string: nothing');
    is($ds->('0000-00-00'), undef, 'date_string: zero');
    is($ds->('2020-01-02'), '2020-01-02T00:00:00', 'date_string: a day');
    is($ds->('2020-01-02T03:04:05Z'), '2020-01-02T03:04:05Z', 'date_string: UTC');
    is($ds->('2020-01-02T03:04:05+02:00'), '2020-01-02T03:04:05+02:00', 'date_string: an offset');
    is($ds->('2020-01-02T03:04:05+00:00'), '2020-01-02T03:04:05+00:00', 'date_string: +00:00 written out stays');
    is($ds->('garbage'), undef, 'date_string: not a date');
    my $l = \&App::Dapper::Import::list;
    is_deeply($l->(undef), [], 'list: nothing');
    is_deeply($l->('a, b c'), ['a', 'b', 'c'], 'list: text');
    is_deeply($l->(['a', '', undef, 'b']), ['a', 'b'], 'list: a list');
    is_deeply($l->({ a => 1 }), [], 'list: a hash');
    is(App::Dapper::Import::video('https://example.com/'), undef, 'video: not a video');
    is(App::Dapper::Import::video('https://youtube.com/watch?v=abc'), undef, 'video: an ID too short');
    is(App::Dapper::Import::video('https://vimeo.com/123'), vm('123'), 'video: Vimeo');
};

done_testing();
