use 5.010;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Import;

# Importing a Hugo site

sub project {
    my (%files) = @_;
    my $old = tempdir(CLEANUP => 1);
    make_site({ '_layout/post.html' => "<article>[% page.content %]</article>", %files });
    return $old;
}

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
    die $error if $error;
    return wantarray ? ($state, $out) : $state;
}

sub front { my ($file) = @_; (App::Dapper::Utils::split_frontmatter(slurp($file), $file))[0] }
sub body  { my ($file) = @_; my $b = (App::Dapper::Utils::split_frontmatter(slurp($file), $file))[1]; $b =~ s/^\n//; $b }
sub files { my ($state) = @_; [ sort map { $_->{file} } @{$state->{pages}} ] }

subtest 'a post, exactly' => sub {
    my $old = project();
    spew("$old/config.toml", qq{baseURL = "https://example.org/"\n[permalinks]\n  posts = "/:year/:month/:slug/"\n});
    spew("$old/content/posts/first.md", <<'MD');
---
title: Hello World!
date: 2021-03-04T10:00:00Z
lastmod: 2022-01-01
weight: 3
type: post
summary: The summary
tags: [a, b]
categories: News
aliases: [/old/first/]
mood: happy
author:
  name: Me
---
Body.
MD
    run_import('hugo', $old);
    is(slurp('_source/posts/first.md'), <<'MD', 'the whole file');
---
title: Hello World!
date: 2021-03-04T10:00:00Z
layout: post
categories:
- News
tags:
- a
- b
description: The summary
urlpattern: /2021/03/first/
author:
  name: Me
mood: happy
---
Body.
MD
    is(slurp('_data/redirects.yml'), "/old/first/: /2021/03/first/\n", 'the alias');
};

subtest 'front matter formats' => sub {
    my $old = project();
    spew("$old/content/toml.md", qq{+++\ntitle = "TOML"\ndate = 2021-06-01T09:00:00Z\ndraft = true\ntags = ["x"]\n[params]\n  mood = "happy"\n+++\nTOML body\n});
    spew("$old/content/toml-crlf.md", qq{+++\r\ntitle = "CRLF"\r\n+++\r\nBody\r\n});
    spew("$old/content/yaml.md", "---\ntitle: YAML\ndraft: false\n---\nYAML body\n");
    spew("$old/content/empty-yaml.md", "---\n---\nNo settings\n");
    spew("$old/content/json.md", qq|{\n  "title": "JSON",\n  "draft": "true",\n  "tags": ["j"]\n}\nJSON body\n|);
    spew("$old/content/bad-json.md", qq|{ not json\nText\n|);
    spew("$old/content/none.md", "Just text.\n");
    spew("$old/content/draft-string.md", "---\ntitle: S\ndraft: 'false'\n---\nx\n");
    spew("$old/content/draft-zero.md", "---\ntitle: Z\ndraft: 0\n---\nx\n");
    spew("$old/content/draft-yes.md", "---\ntitle: Y\ndraft: yes\n---\nx\n");
    my ($state, $out) = run_import('hugo', $old, loud => 1);

    my $toml = front('_source/toml.md');
    is($toml->{title}, 'TOML', 'TOML');
    is($toml->{date}, '2021-06-01T09:00:00Z', 'TOML date');
    is($toml->{draft}, 1, 'TOML draft = true');
    is_deeply($toml->{params}, { mood => 'happy' }, 'TOML tables are kept');
    is(body('_source/toml.md'), "TOML body\n", 'TOML body');
    is(front('_source/toml-crlf.md')->{title}, 'CRLF', 'TOML with Windows line endings');
    is(front('_source/yaml.md')->{title}, 'YAML', 'YAML');
    ok(!exists front('_source/yaml.md')->{draft}, 'draft: false');
    is(body('_source/yaml.md'), "YAML body\n", 'YAML body');
    is(body('_source/empty-yaml.md'), "No settings\n", 'empty YAML');
    is(front('_source/json.md')->{title}, 'JSON', 'JSON');
    is(front('_source/json.md')->{draft}, 1, 'JSON draft "true"');
    is_deeply(front('_source/json.md')->{tags}, ['j'], 'JSON tags');
    is(body('_source/json.md'), "\nJSON body\n", 'JSON body (from after the closing brace)');
    ok(!exists front('_source/bad-json.md')->{title}, 'JSON that cannot be read: no settings');
    is(body('_source/bad-json.md'), "{ not json\nText\n", 'and the whole file is the body');
    is(body('_source/none.md'), "Just text.\n", 'no front matter');
    is(front('_source/none.md')->{urlpattern}, '/none/', 'still gets its address');
    ok(!exists front('_source/draft-string.md')->{draft}, "draft: 'false'");
    ok(!exists front('_source/draft-zero.md')->{draft}, 'draft: 0');
    is(front('_source/draft-yes.md')->{draft}, 1, 'draft: yes');
    like($out, qr{^Imported 0 posts and 10 pages into _source \(3 as drafts\)\.$}m, 'the report');

    my $bad = project();
    spew("$bad/content/broken.md", "---\ntitle: [unclosed\n---\nx\n");
    eval { run_import('hugo', $bad) };
    like($@, qr{^error: could not read the front matter of \Q$bad\E/content/broken\.md: }, 'YAML that cannot be read');
    my $list = project();
    spew("$list/content/list.md", "---\n- a\n- b\n---\nx\n");
    eval { run_import('hugo', $list) };
    like($@, qr{^error: could not read the front matter of \Q$list\E/content/list\.md: }, 'YAML that is a list');
};

subtest 'configuration files' => sub {
    my %configs = (
        'hugo.toml'   => qq{[permalinks]\nposts = "/t/:slug/"\n},
        'hugo.yaml'   => "permalinks:\n  posts: /ya/:slug/\n",
        'hugo.yml'    => "permalinks:\n  posts: /yml/:slug/\n",
        'hugo.json'   => qq|{"permalinks": {"posts": "/j/:slug/"}}|,
        'config.toml' => qq{[permalinks]\nposts = "/ct/:slug/"\n},
        'config.yaml' => "permalinks:\n  posts: /cya/:slug/\n",
        'config.yml'  => "permalinks:\n  posts: /cyml/:slug/\n",
        'config.json' => qq|{"permalinks": {"posts": "/cj/:slug/"}}|,
    );
    my %want = ('hugo.toml' => '/t/p/', 'hugo.yaml' => '/ya/p/', 'hugo.yml' => '/yml/p/', 'hugo.json' => '/j/p/',
                'config.toml' => '/ct/p/', 'config.yaml' => '/cya/p/', 'config.yml' => '/cyml/p/', 'config.json' => '/cj/p/');
    for my $name (sort keys %configs) {
        my $old = project();
        spew("$old/$name", $configs{$name});
        spew("$old/content/posts/p.md", "---\ntitle: P\n---\nx\n");
        run_import('hugo', $old);
        is(front('_source/posts/p.md')->{urlpattern}, $want{$name}, $name);
    }
    my $old = project();
    spew("$old/$_", $configs{$_}) for keys %configs;
    spew("$old/content/posts/p.md", "---\ntitle: P\n---\nx\n");
    run_import('hugo', $old);
    is(front('_source/posts/p.md')->{urlpattern}, '/t/p/', 'hugo.toml is read first');

    $old = project();
    spew("$old/config.toml", qq{permalinks = "not a table"\n});
    spew("$old/content/posts/p.md", "---\ntitle: P\n---\nx\n");
    run_import('hugo', $old);
    is(front('_source/posts/p.md')->{urlpattern}, '/posts/p/', 'permalinks that are not a table are ignored');
};

subtest 'addresses' => sub {
    my $old = project();
    spew("$old/hugo.yaml", "permalinks:\n  posts: /:section/:year/:month/:day/:yearday/:monthname/:title/:filename/:contentbasename/\n  docs: /d/:slug/\n  blog: /:year/:title\n");
    spew("$old/content/posts/a-file.md", "---\ntitle: Hello World!\ndate: 2021-03-04\n---\nx\n");
    spew("$old/content/docs/guide.md", "---\ntitle: Guide\nslug: the-guide\n---\nx\n");
    spew("$old/content/docs/own.md", "---\ntitle: Own\nurl: /my/own/\nslug: ignored\n---\nx\n");
    spew("$old/content/docs/deep/nested.md", "---\ntitle: Nested\n---\nx\n");
    spew("$old/content/blog/undated.md", "---\ntitle: No Date\n---\nx\n");
    spew("$old/content/blog/untitled.md", "---\ndate: 2020-01-01\n---\nx\n");
    spew("$old/content/notes/plain.md", "---\ntitle: Plain\nslug: renamed\n---\nx\n");
    spew("$old/content/notes/sub/deeper.md", "---\ntitle: Deeper\n---\nx\n");
    spew("$old/content/top.md", "---\ntitle: Top\n---\nx\n");
    spew("$old/content/published.md", "---\ntitle: Pub\npublishDate: 2020-05-06\n---\nx\n");
    spew("$old/content/published2.md", "---\ntitle: Pub2\npublishdate: 2020-05-07\n---\nx\n");
    run_import('hugo', $old);

    is(front('_source/posts/a-file.md')->{urlpattern}, '/posts/2021/03/04/063/march/hello-world/a-file/a-file/', 'every token');
    is(front('_source/docs/guide.md')->{urlpattern}, '/d/the-guide/', 'slug');
    is(front('_source/docs/own.md')->{urlpattern}, '/my/own/', 'url wins');
    is(front('_source/docs/deep/nested.md')->{urlpattern}, '/d/nested/', 'the section is the top folder');
    is(front('_source/blog/undated.md')->{urlpattern}, '/no-date', 'no date: date tokens are empty; no slash added at the end');
    is(front('_source/blog/untitled.md')->{urlpattern}, '/2020/untitled', 'no title: :title is the slug');
    is(front('_source/notes/plain.md')->{urlpattern}, '/notes/renamed/', 'no permalinks for the section: folder and slug');
    is(front('_source/notes/sub/deeper.md')->{urlpattern}, '/notes/sub/deeper/', 'every folder');
    is(front('_source/top.md')->{urlpattern}, '/top/', 'a page at the top');
    is(front('_source/published.md')->{date}, '2020-05-06T00:00:00', 'publishDate when there is no date');
    is(front('_source/published2.md')->{date}, '2020-05-07T00:00:00', 'publishdate');

    my $u = \&App::Dapper::Import::hugo_url;
    is($u->('posts/:slug', {}, 'posts', 's', 'l'), '/posts/s', 'a slash at the start');
    is($u->('/:sections/:slugs/', {}, 'posts', 's', 'l'), '/:sections/:slugs/', 'longer words are not tokens');
    is($u->('/:year/:slug/', { date => 'garbage' }, 'posts', 's', 'l'), '/s/', 'a date that cannot be read');
    is($u->('/:title/', { title => '!!!' }, 'posts', 's', 'l'), '/s/', 'a title with nothing to slugify');
    is($u->('/:monthname/:yearday/', { date => '2020-12-31' }, '', 's', 'l'), '/december/366/', 'month name and day of a leap year');
};

subtest 'layouts, kinds and other settings' => sub {
    my $old = project('_layout/wide.html' => 'w');
    spew("$old/content/posts/p.md", "---\ntitle: P\n---\nx\n");
    spew("$old/content/post/p2.md", "---\ntitle: P2\n---\nx\n");
    spew("$old/content/blog/b.md", "---\ntitle: B\nlayout: wide\n---\nx\n");
    spew("$old/content/news/n.md", "---\ntitle: N\ncategories: [Updates]\n---\nx\n");
    spew("$old/content/news/m.md", "---\ntitle: M\nlayout: missing\n---\nx\n");
    spew("$old/content/about.md", "---\ntitle: About\ndescription: D\nsummary: S\nzeta: 1\nalpha: 2\n---\nx\n");
    my $state = run_import('hugo', $old);
    my %kind = map { $_->{file} => $_->{kind} } @{$state->{pages}};
    is_deeply(\%kind, { '_source/posts/p.md' => 'post', '_source/post/p2.md' => 'post', '_source/blog/b.md' => 'post',
                        '_source/news/n.md' => 'page', '_source/news/m.md' => 'page', '_source/about.md' => 'page' }, 'posts are in posts, post or blog');
    is(front('_source/posts/p.md')->{layout}, 'post', 'a post: the post layout');
    is(front('_source/post/p2.md')->{layout}, 'post', 'post too');
    is(front('_source/blog/b.md')->{layout}, 'wide', 'a layout the project has');
    is(front('_source/news/n.md')->{layout}, 'post', 'a page with categories: the post layout');
    ok(!exists front('_source/news/m.md')->{layout}, 'a layout the project lacks, not a post');
    ok(!exists front('_source/about.md')->{layout}, 'a page');
    is(front('_source/about.md')->{description}, 'D', 'description wins over summary');
    like(slurp('_source/about.md'), qr{^alpha: 2\nzeta: 1\n---\n}m, 'other settings, sorted');

    my $none = tempdir(CLEANUP => 1);
    make_site({});
    spew("$none/content/posts/p.md", "---\ntitle: P\n---\nx\n");
    run_import('hugo', $none);
    ok(!exists front('_source/posts/p.md')->{layout}, 'no post layout in the project');
};

subtest 'bundles, sections and static files' => sub {
    my $old = project();
    spew("$old/content/posts/bundle/index.md", "---\ntitle: Bundle\n---\n![pic](pic.jpg)\n");
    spew("$old/content/posts/bundle/pic.jpg", "JPG");
    spew("$old/content/posts/bundle/data.json", "{}");
    spew("$old/content/posts/bundle/.hidden", "h");
    spew("$old/content/posts/bundle/extra.md", "---\ntitle: Extra\n---\nx\n");
    spew("$old/content/posts/bundle/sub/deep.txt", "d");
    spew("$old/content/pages/html-bundle/index.html", "---\ntitle: HTML bundle\n---\n<p>x</p>\n");
    spew("$old/content/pages/html-bundle/a.css", "css");
    spew("$old/content/posts/_index.md", "---\ntitle: Posts\n---\n");
    spew("$old/content/_index.md", "---\ntitle: Home\n---\n");
    spew("$old/content/posts/page.HTML", "---\ntitle: Upper\n---\n<p>x</p>\n");
    spew("$old/content/posts/notes.txt", "not content");
    spew("$old/static/robots.txt", "User-agent: *\n");
    spew("$old/static/css/site.css", "body {}");
    spew("$old/static/.DS_Store", "x");

    my ($state, $out) = run_import('hugo', $old, loud => 1);
    is_deeply(files($state), [ sort map { "_source/$_" } qw( posts/bundle/index.md pages/html-bundle/index.html posts/page.html ) ], 'what was imported');
    is(front('_source/posts/bundle/index.md')->{urlpattern}, '/posts/bundle/', 'a bundle is addressed by its folder');
    is(front('_source/pages/html-bundle/index.html')->{urlpattern}, '/pages/html-bundle/', 'an HTML bundle');
    is(slurp('_source/posts/bundle/pic.jpg'), 'JPG', 'bundle files copied');
    is(slurp('_source/posts/bundle/data.json'), '{}', 'all of them');
    is(slurp('_source/pages/html-bundle/a.css'), 'css', 'for HTML bundles too');
    ok(!-e '_source/posts/bundle/.hidden', 'not hidden files');
    ok(!-e '_source/posts/bundle/sub', 'not folders');
    ok(!-e '_source/posts/_index.md' && !-e '_source/_index.md', 'section pages are not imported');
    ok(!-e '_source/posts/notes.txt', 'other files in content are not copied');
    is(slurp('_source/robots.txt'), "User-agent: *\n", 'static copied into the source directory');
    is(slurp('_source/css/site.css'), 'body {}', 'with its folders');
    ok(!-e '_source/.DS_Store', 'not hidden files');
    is_deeply($state->{notes}, {
        'Hugo section pages (_index.md) were not imported; Dapper lists pages with paginate' => ["$old/content/_index.md", "$old/content/posts/_index.md"],
        'Markdown files inside page bundles were left out (Hugo treats them as resources, not pages)' => ["$old/content/posts/bundle/extra.md"],
    }, 'section pages and bundle Markdown noted');
    like($out, qr{^Check: Hugo section pages \(_index\.md\) were not imported; Dapper lists pages with paginate \(2 pages, such as \Q$old\E/content/_index\.md\)$}m, 'reported');
    like($out, qr{^Copied 5 other files\.$}m, 'copies reported');
    ok(!-e '_source/posts/bundle/extra.md', 'a Markdown file in a bundle is not a page');
};

subtest 'aliases and redirects' => sub {
    my $old = project('_data/redirects.yml' => "/keep/: /there/\n/old/a/: /mine/\n");
    spew("$old/content/posts/a.md", "---\ntitle: A\naliases: [/old/a/, old/b, /old/c/]\n---\nx\n");
    spew("$old/content/posts/b.md", "---\ntitle: B\naliases: /single/\n---\nx\n");
    my ($state, $out) = run_import('hugo', $old, loud => 1);
    is(slurp('_data/redirects.yml'), "/keep/: /there/\n/old/a/: /mine/\n/old/b: /posts/a/\n/old/c/: /posts/a/\n/single/: /posts/b/\n",
        'added to the existing file, without changing what is there');
    is($state->{redirects_added}, 3, 'three added');
    like($out, qr{^Added 3 redirects to _data/redirects\.yml\.$}m, 'reported');

    ($state, $out) = run_import('hugo', $old, loud => 1);
    is($state->{redirects_added}, 0, 'nothing new the second time');
    unlike($out, qr/redirect/, 'and nothing said');

    my $one = project();
    spew("$one/content/a.md", "---\ntitle: A\naliases: [/x/]\n---\nx\n");
    (undef, $out) = run_import('hugo', $one, loud => 1, dry_run => 1);
    like($out, qr{^Would add 1 redirect to _data/redirects\.yml\.$}m, 'a dry run');
    ok(!-e '_data/redirects.yml', 'writes nothing');

    my $odd = project('_data/redirects.yml' => "- not a hash\n");
    spew("$odd/content/a.md", "---\ntitle: A\naliases: [/x/]\n---\nx\n");
    run_import('hugo', $odd);
    is(slurp('_data/redirects.yml'), "/x/: /a/\n", 'a redirects file that is not a hash is replaced');

    quiet_build();
    ok(-f '_output/x/index.html', 'and the redirect is built');
};

subtest 'shortcodes' => sub {
    my $old = project();
    spew("$old/content/posts/s.md", <<'MD');
{{< youtube dQw4w9WgXcQ >}}
{{% youtube id="abcdefghijk" title="My \"clip\"" %}}
{{< youtube id=xyz123abc title="Bare" >}}
{{< vimeo 123456 >}}
{{< vimeo id="55" title='x' >}}
{{< youtube >}}
{{< figure src="a.jpg" >}}
{{< figure src="b.jpg" alt="B" caption="Cap" >}}
{{< figure src="c.jpg" title="Title only" />}}
{{% figure src=d.jpg alt="D" %}}
{{< figure alt="no src" >}}
[r]({{< relref "/docs/guide.md" >}}) [s]({{< ref "posts/bundle/index.md" >}}) [t]({{< ref "about" >}}) [u]({{% ref "index.md" %}})
Inline {{< youtube dQw4w9WgXcQ >}} text.
{{< gist user 123 >}}
{{< highlight go >}}x{{< /highlight >}}
{{% notice note %}}Hi{{% /notice %}}
{{< tweet-embed 1 >}}
MD
    my $state = run_import('hugo', $old);
    is(body('_source/posts/s.md'), <<'MD', 'converted where Dapper has a component');
::: youtube dQw4w9WgXcQ
::: youtube abcdefghijk "My 'clip'"
::: youtube xyz123abc "Bare"
::: vimeo 123456
::: vimeo 55 "'x'"
{{< youtube >}}
::: figure a.jpg ""
::: figure b.jpg "B" "Cap"
::: figure c.jpg "Title only"
::: figure d.jpg "D"
{{< figure alt="no src" >}}
[r](/docs/guide/) [s](/posts/bundle/) [t](/about/) [u](/)
Inline ::: youtube dQw4w9WgXcQ text.
{{< gist user 123 >}}
{{< highlight go >}}x{{< /highlight >}}
{{% notice note %}}Hi{{% /notice %}}
{{< tweet-embed 1 >}}
MD
    is_deeply($state->{notes}, { 'Hugo shortcodes that were left as they are: figure, gist, highlight, notice, tweet-embed, youtube' => ['_source/posts/s.md'] }, 'the rest noted');
    like(body('_source/posts/s.md'), qr{^::: youtube abcdefghijk "My 'clip'"$}m, 'a title with escaped quotes');
    like(body('_source/posts/s.md'), qr{\[u\]\(/\)}, 'ref "index.md" is /');

    quiet_build();
    like(slurp('_output/posts/s/index.html'), qr{<div class="video video-youtube"><iframe src="https://www\.youtube-nocookie\.com/embed/dQw4w9WgXcQ"}, 'the components work');
};

subtest 'dry runs, --to and importing again' => sub {
    my $old = project();
    spew("$old/content/posts/a.md", "---\ntitle: A\ndraft: true\n---\nx\n");
    spew("$old/content/posts/b/index.md", "---\ntitle: B\n---\nx\n");
    spew("$old/content/posts/b/img.png", "P");
    spew("$old/static/s.txt", "s");
    my ($state, $out) = run_import('hugo', $old, dry_run => 1, to => 'ignored', loud => 1);
    is_deeply(files($state), ['_source/posts/a.md', '_source/posts/b/index.md'], 'Hugo pages keep their place (--to is not used)');
    ok(!-e '_source/posts', 'nothing written');
    is($out, "Would import 2 posts and 0 pages into _source (1 as drafts).\nWould copy 2 other files.\n", 'the report');

    run_import('hugo', $old);
    ($state, $out) = run_import('hugo', $old, loud => 1);
    is_deeply($state->{pages}, [], 'nothing the second time');
    is_deeply([ sort @{$state->{skipped}} ], [ sort '_source/posts/a.md', '_source/posts/b/index.md', '_source/posts/b/img.png', '_source/s.txt' ], 'everything left alone');
};

subtest 'errors' => sub {
    my $old = project();
    spew("$old/file.txt", 'x');
    eval { run_import('hugo', "$old/file.txt") };
    is($@, "error: give the Hugo site's directory\n", 'a file');
    eval { run_import('hugo', $old) };
    is($@, "error: $old has no content directory, so it doesn't look like a Hugo site\n", 'no content directory');
    mkdir "$old/content";
    my ($state, $out) = run_import('hugo', $old, loud => 1);
    is($out, "Imported 0 posts and 0 pages into _source.\n", 'an empty content directory');
};

done_testing();
