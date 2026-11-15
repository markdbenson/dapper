use 5.010;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use Cwd qw(getcwd);

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Import;

# A new Dapper project with a post layout, and a place for the old site
sub project {
    my $old = tempdir(CLEANUP => 1);
    make_site({ '_layout/post.html' => "<article>[% page.content %]</article>" });
    return $old;
}

sub import_site {
    my ($kind, $from, %options) = @_;
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    return $d->import_from($kind, $from, %options);
}

sub front { my ($file) = @_; my ($front) = App::Dapper::Utils::split_frontmatter(slurp($file), $file); $front }

subtest 'WordPress' => sub {
    my $old = project();
    spew("$old/export.xml", <<'XML');
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:wp="http://wordpress.org/export/1.2/" xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/">
<channel>
  <title>Old Blog</title>
  <link>https://old.example.com</link>
  <item>
    <title>Hello &amp; welcome</title>
    <link>https://old.example.com/2019/05/hello-world/</link>
    <content:encoded><![CDATA[First line
second line

[caption id="a" align="alignnone"]<img src="https://old.example.com/wp-content/uploads/cat.jpg" alt="Cat"> A cat[/caption]

https://www.youtube.com/watch?v=dQw4w9WgXcQ

[gallery ids="1,2"]]]></content:encoded>
    <excerpt:encoded><![CDATA[<p>A short hello.</p>]]></excerpt:encoded>
    <wp:post_id>1</wp:post_id>
    <wp:post_date><![CDATA[2019-05-01 10:30:00]]></wp:post_date>
    <wp:post_name><![CDATA[hello-world]]></wp:post_name>
    <wp:status><![CDATA[publish]]></wp:status>
    <wp:post_type><![CDATA[post]]></wp:post_type>
    <category domain="category" nicename="news"><![CDATA[News]]></category>
    <category domain="category" nicename="uncategorized"><![CDATA[Uncategorized]]></category>
    <category domain="post_tag" nicename="hi"><![CDATA[hi]]></category>
  </item>
  <item>
    <title>Block post</title>
    <link>https://old.example.com/?p=2</link>
    <content:encoded><![CDATA[<!-- wp:paragraph -->
<p>Made with blocks.</p>
<!-- /wp:paragraph -->]]></content:encoded>
    <wp:post_id>2</wp:post_id>
    <wp:post_date><![CDATA[2020-01-01 00:00:00]]></wp:post_date>
    <wp:post_name><![CDATA[]]></wp:post_name>
    <wp:status><![CDATA[draft]]></wp:status>
    <wp:post_type><![CDATA[post]]></wp:post_type>
  </item>
  <item>
    <title>About</title>
    <link>https://old.example.com/about/</link>
    <content:encoded><![CDATA[<p>About us.</p>]]></content:encoded>
    <wp:post_name><![CDATA[about]]></wp:post_name>
    <wp:status><![CDATA[publish]]></wp:status>
    <wp:post_type><![CDATA[page]]></wp:post_type>
  </item>
  <item>
    <title>photo</title>
    <wp:status><![CDATA[inherit]]></wp:status>
    <wp:post_type><![CDATA[attachment]]></wp:post_type>
  </item>
</channel>
</rss>
XML

    my $state = import_site('wordpress', "$old/export.xml");
    is(scalar @{$state->{pages}}, 3, 'two posts and a page; no attachment');

    my $post = front('_source/blog/hello-world.html');
    is($post->{title}, 'Hello & welcome', 'title');
    is($post->{date}, '2019-05-01T10:30:00', 'date');
    is_deeply($post->{categories}, ['News'], 'categories, without Uncategorized');
    is_deeply($post->{tags}, ['hi'], 'tags');
    is($post->{description}, 'A short hello.', 'excerpt');
    is($post->{urlpattern}, '/2019/05/hello-world/', 'keeps its address');
    is($post->{layout}, 'post', 'the post layout');
    my $body = slurp('_source/blog/hello-world.html');
    like($body, qr{<p>First line<br>\nsecond line</p>}, 'paragraphs added');
    like($body, qr{<figure><img src="[^"]+cat\.jpg" alt="Cat"><figcaption>A cat</figcaption></figure>}, 'caption to figure');
    like($body, qr{youtube-nocookie\.com/embed/dQw4w9WgXcQ}, 'video embedded');

    my $draft = front('_source/blog/block-post.html');
    ok($draft->{draft}, 'a draft');
    ok(!defined $draft->{urlpattern}, 'no address for a draft');
    unlike(slurp('_source/blog/block-post.html'), qr{wp:paragraph}, 'block comments removed');

    is(front('_source/about.html')->{urlpattern}, '/about/', 'a page keeps its address');
    ok((grep { /shortcodes.*\[gallery\]/ } keys %{$state->{notes}}), 'unknown shortcodes noted');
    ok((grep { /wp-content\/uploads/ } keys %{$state->{notes}}), 'old images noted');

    quiet_build();
    ok(-f '_output/2019/05/hello-world/index.html', 'built at its old address');
    ok(-f '_output/about/index.html', 'the page too');

    # Importing again leaves the files alone
    $state = import_site('wordpress', "$old/export.xml");
    is(scalar @{$state->{pages}}, 0, 'nothing written the second time');
    is(scalar @{$state->{skipped}}, 3, 'three left alone');
};

subtest 'Jekyll' => sub {
    my $old = project();
    spew("$old/_config.yml", "title: Old\npermalink: pretty\n");
    spew("$old/_posts/2018-03-04-first-post.md", "---\nlayout: post\ntitle: First post\ncategories: [Notes]\ntags: perl\n---\nSee [the second]({% post_url 2018-04-01-second %}) and ![x]({{ site.baseurl }}/assets/x.png).\n\n{% highlight perl %}\nprint 1;\n{% endhighlight %}\n");
    spew("$old/_posts/2018-04-01-second.markdown", "---\ntitle: Second\npermalink: /custom/path/\n---\n{% include note.html %}\n");
    spew("$old/_drafts/idea.md", "---\ntitle: An idea\n---\nLater.\n");
    spew("$old/about.md", "---\ntitle: About\n---\nAbout.\n");
    spew("$old/docs/guide.html", "---\ntitle: Guide\n---\n<p>Guide.</p>\n");
    spew("$old/README.md", "---\ntitle: Readme\n---\nx\n");
    spew("$old/assets/x.png", "PNG");
    spew("$old/_site/ignored.html", "---\ntitle: No\n---\n");

    my $state = import_site('jekyll', $old);
    my %files = map { $_->{file} => 1 } @{$state->{pages}};
    is_deeply([ sort keys %files ], [ sort map { "_source/$_" } qw( blog/first-post.md blog/second.md blog/idea.md about.md docs/guide.html ) ], 'what was imported');

    my $first = front('_source/blog/first-post.md');
    is($first->{urlpattern}, '/notes/2018/03/04/first-post/', 'address from permalink: pretty');
    is($first->{date}, '2018-03-04T00:00:00', 'date from the file name');
    is($first->{layout}, 'post', 'layout kept where the project has it');
    is_deeply($first->{tags}, ['perl'], 'tags as a list');
    my $body = slurp('_source/blog/first-post.md');
    like($body, qr{\[the second\]\(/custom/path/\)}, 'post_url');
    like($body, qr{!\[x\]\(/assets/x\.png\)}, 'site.baseurl');
    like($body, qr{```perl\nprint 1;\n```}, 'highlight');
    is(front('_source/blog/second.md')->{urlpattern}, '/custom/path/', 'its own permalink');
    ok(front('_source/blog/idea.md')->{draft}, 'drafts');
    ok(!defined front('_source/about.md')->{urlpattern}, 'a page at the same address needs no urlpattern');
    ok(-f 'assets/x.png', 'assets copied');
    ok((grep { /Liquid/ } keys %{$state->{notes}}), 'Liquid left over is noted');
};

subtest 'Hugo' => sub {
    my $old = project();
    spew("$old/config.toml", qq{baseURL = "https://example.org/"\ntitle = "Old"\n\n[permalinks]\n  posts = "/:year/:month/:slug/"\n});
    spew("$old/content/posts/toml-post.md", qq{+++\ntitle = "TOML post"\ndate = 2021-06-01T09:00:00Z\ntags = ["a", "b"]\ncategories = [\n  "News",\n]\naliases = ["/old/toml/"]\ndraft = false\n[params]\n  mood = "happy"\n+++\n{{< youtube id="dQw4w9WgXcQ" title="Clip" >}}\n\n{{< figure src="pic.jpg" alt="A pic" caption="Nice" >}}\n\n{{< tweet 123 >}}\n\nSee [the bundle]({{< ref "posts/bundle/index.md" >}}).\n});
    spew("$old/content/posts/bundle/index.md", "---\ntitle: Bundle\ndate: 2021-07-01\nslug: my-bundle\ndraft: true\n---\n![pic](pic.jpg)\n");
    spew("$old/content/posts/bundle/pic.jpg", "JPG");
    spew("$old/content/posts/_index.md", "---\ntitle: Posts\n---\n");
    spew("$old/content/about.md", qq|{ "title": "About", "url": "/about-us/" }\nAbout.\n|);
    spew("$old/static/robots.txt", "User-agent: *\n");

    my $state = import_site('hugo', $old);
    my $post = front('_source/posts/toml-post.md');
    is($post->{title}, 'TOML post', 'TOML front matter');
    is($post->{date}, '2021-06-01T09:00:00Z', 'date');
    is_deeply($post->{tags}, ['a', 'b'], 'tags');
    is_deeply($post->{categories}, ['News'], 'a list over several lines');
    is($post->{urlpattern}, '/2021/06/toml-post/', 'address from permalinks');
    is_deeply($post->{params}, { mood => 'happy' }, 'other settings kept');
    my $body = slurp('_source/posts/toml-post.md');
    like($body, qr{^::: youtube dQw4w9WgXcQ "Clip"$}m, 'youtube shortcode');
    like($body, qr{^::: figure pic\.jpg "A pic" "Nice"$}m, 'figure shortcode');
    like($body, qr{\(/posts/bundle/\)}, 'ref');
    ok((grep { /shortcodes.*tweet/ } keys %{$state->{notes}}), 'unknown shortcodes noted');

    my $bundle = front('_source/posts/bundle/index.md');
    is($bundle->{urlpattern}, '/2021/07/my-bundle/', 'slug');
    ok($bundle->{draft}, 'draft');
    ok(-f '_source/posts/bundle/pic.jpg', 'bundle files copied');
    ok(!-e '_source/posts/_index.md', 'section pages skipped');
    is(front('_source/about.md')->{urlpattern}, '/about-us/', 'JSON front matter and url');
    ok(-f '_source/robots.txt', 'static copied');
    is_deeply(App::Dapper::Utils::read_file('_data/redirects.yml'), "/old/toml/: /2021/06/toml-post/\n", 'aliases become redirects');

    quiet_build();
    ok(-f '_output/2021/06/toml-post/index.html', 'built');
    ok(-f '_output/old/toml/index.html', 'with its redirect');
};

subtest 'Medium' => sub {
    my $old = project();
    spew("$old/posts/2020-02-02_Why-I-Write-1a2b3c4d5e6f.html", <<'HTML');
<!DOCTYPE html><html><head><title>Why I Write</title></head><body><article class="h-entry">
<header><h1 class="p-name">Why I Write</h1></header>
<section data-field="subtitle" class="p-summary">A few reasons.</section>
<section data-field="body" class="e-content"><section name="a1" class="section"><div class="section-content"><div class="section-inner"><h3 name="b2" id="b2" class="graf graf--h3 graf--title">Why I Write</h3><p name="c3" id="c3" class="graf graf--p">Because I <em class="markup--em">must</em>.</p></div></div></section></section>
<footer><p>By <a href="https://medium.com/@me" class="p-author h-card">Me</a> on <a href="https://medium.com/p/1a2b3c4d5e6f"><time class="dt-published" datetime="2020-02-02T10:00:00.000Z">February 2, 2020</time></a>.</p><p><a href="https://medium.com/@me/why-i-write-1a2b3c4d5e6f" class="p-canonical">Canonical link</a></p></footer></article></body></html>
HTML
    spew("$old/posts/draft_Unfinished-9f8e7d6c5b4a.html", qq{<html><head><title>Unfinished</title></head><body><section data-field="body" class="e-content"><p class="graf">Soon.</p></section>\n<footer></footer></body></html>});

    import_site('medium', $old);
    my $post = front('_source/blog/why-i-write.html');
    is($post->{title}, 'Why I Write', 'title');
    is($post->{date}, '2020-02-02T10:00:00Z', 'date');
    is($post->{description}, 'A few reasons.', 'subtitle');
    is(App::Dapper::Utils::split_frontmatter(slurp('_source/blog/why-i-write.html'), 'x') && (App::Dapper::Utils::split_frontmatter(slurp('_source/blog/why-i-write.html'), 'x'))[1],
        "\n<p>Because I <em>must</em>.</p>\n", 'body without Medium\'s markup or the repeated title');
    ok(front('_source/blog/unfinished.html')->{draft}, 'unpublished stories are drafts');
};

subtest 'dry run and errors' => sub {
    my $old = project();
    spew("$old/_posts/2018-03-04-a.md", "---\ntitle: A\n---\nA\n");
    my $state = import_site('jekyll', $old, dry_run => 1, to => 'posts');
    is_deeply([ map { $_->{file} } @{$state->{pages}} ], ['_source/posts/a.md'], 'would import, into --to');
    ok(!-e '_source/posts/a.md', 'but did not');

    eval { import_site('drupal', $old) };
    like($@, qr/can't import from "drupal"/, 'unknown kind');
    eval { import_site('jekyll', "$old/nope") };
    like($@, qr/doesn't exist/, 'missing path');
    eval { import_site('wordpress', $old) };
    like($@, qr/export file/, 'WordPress needs a file');
};

subtest 'toml' => sub {
    my $t = App::Dapper::Import::toml(qq{a = "x \\"y\\""\nb = 'lit'\nc = 3\nd = true\ne = [1, "two", 'three']\n# comment\n[x.y]\nz = "deep"\n});
    is_deeply($t, { a => 'x "y"', b => 'lit', c => 3, d => 1, e => [1, 'two', 'three'], x => { y => { z => 'deep' } } }, 'parsed');
};

done_testing();
