use 5.010;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Import;

# Importing a Jekyll site

sub project {
    my (%layouts) = @_;
    my $old = tempdir(CLEANUP => 1);
    %layouts = ('_layout/post.html' => "<article>[% page.content %]</article>") unless %layouts;
    make_site({ %layouts });
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
# The body, without the blank line Jekyll imports have after the front matter
sub body  { my ($file) = @_; my $b = (App::Dapper::Utils::split_frontmatter(slurp($file), $file))[1]; $b =~ s/^\n\n?//; $b }
sub files { my ($state) = @_; [ sort map { $_->{file} } @{$state->{pages}} ] }

subtest 'a post, exactly' => sub {
    my $old = project('_layout/post.html' => 'x', '_layout/page.html' => 'p');
    spew("$old/_posts/2018-03-04-first-post.md",
        "---\nlayout: page\ntitle: First\ndate: 2018-03-05 14:15:16\ncategories: [Big News, Perl]\ntags: [a, b]\nexcerpt: Ex\nauthor: Me\ncustom:\n  k: v\n---\nBody.\n");
    run_import('jekyll', $old);
    is(slurp('_source/blog/first-post.md'), <<'MD', 'the whole file');
---
title: First
date: 2018-03-05T14:15:16
layout: page
categories:
- Big News
- Perl
tags:
- a
- b
description: Ex
urlpattern: /big-news/perl/2018/03/05/first-post.html
author: Me
custom:
  k: v
---

Body.
MD
};

subtest 'permalink styles' => sub {
    my %want = (
        ''      => '/notes/2018/03/04/first-post.html',
        date    => '/notes/2018/03/04/first-post.html',
        pretty  => '/notes/2018/03/04/first-post/',
        ordinal => '/notes/2018/063/first-post.html',
        none    => '/notes/first-post.html',
        '/:year/:title/' => '/2018/first-post/',
        '/blog/:slug' => '/blog/first-post',
        'weird' => '/weird',
    );
    for my $style (sort keys %want) {
        my $old = project();
        spew("$old/_config.yml", length $style ? "permalink: $style\n" : "title: Old\n");
        spew("$old/_posts/2018-03-04-first-post.md", "---\ntitle: First post\ncategories: Notes\n---\nx\n");
        spew("$old/_posts/2018-03-05-plain.md", "---\ntitle: Plain\n---\nx\n");
        run_import('jekyll', $old);
        is(front('_source/blog/first-post.md')->{urlpattern}, $want{$style}, "permalink: '$style'");
    }

    my $old = project();
    spew("$old/_config.yml", "permalink: pretty\n");
    spew("$old/_posts/2018-03-05-plain.md", "---\ntitle: Plain\n---\nx\n");
    run_import('jekyll', $old);
    is(front('_source/blog/plain.md')->{urlpattern}, '/2018/03/05/plain/', 'no categories: no empty folder');

    $old = project();
    spew("$old/_config.yml", "permalink: [not, text]\n: broken: yaml: [\n");
    spew("$old/_posts/2018-03-05-plain.md", "---\ntitle: Plain\n---\nx\n");
    run_import('jekyll', $old);
    is(front('_source/blog/plain.md')->{urlpattern}, '/2018/03/05/plain.html', 'a _config.yml that cannot be read: the default');

    $old = project();
    spew("$old/_config.yml", "- a list\n");
    spew("$old/_posts/2018-03-05-plain.md", "---\ntitle: Plain\n---\nx\n");
    run_import('jekyll', $old);
    is(front('_source/blog/plain.md')->{urlpattern}, '/2018/03/05/plain.html', 'a _config.yml that is a list: the default');
};

subtest 'permalink tokens' => sub {
    my $u = sub { App::Dapper::Import::jekyll_url(@_) };
    my $item = { date_string => '2018-03-05T14:15:16', slug => 'my-post' };
    is($u->('/:year/:month/:day/:hour/:minute/:second/', $item, {}), '/2018/03/05/14/15/16/', 'year to second');
    is($u->('/:short_year/:i_month/:i_day/:y_day/', $item, {}), '/18/3/5/064/', 'short forms and day of the year');
    is($u->('/:title/:slug:output_ext', $item, {}), '/my-post/my-post.html', 'title, slug and output_ext');
    is($u->('/:title/', $item, { slug => 'other' }), '/other/', 'a slug in front matter is the title');
    is($u->('/:categories/:title/', $item, { categories => ['A B', 'C'] }), '/a-b/c/my-post/', 'categories slugified');
    is($u->('/:categories/:title/', $item, { category => 'Single' }), '/single/my-post/', 'category');
    is($u->('/:categories/:title/', $item, { categories => 'x y' }), '/x/y/my-post/', 'categories as text');
    is($u->(':year/:title', $item, {}), '/2018/my-post', 'a slash added at the start');
    is($u->('/:yearly/:titles/', $item, {}), '/:yearly/:titles/', 'a longer word is not a token');
    is($u->('/:year/:title/', { slug => 'undated' }, {}), '/undated/', 'no date: date tokens are empty');
    is($u->('/:year/:title/', { slug => 'bad', date_string => 'nope' }, {}), '/bad/', 'a date that cannot be read');
    is($u->('/:path/', { rel => 'docs/guide' }, {}), '/docs/guide/', 'a page: path');
    is($u->('/:title.html', { rel => 'docs/guide' }, {}), '/guide.html', 'a page: title is its file name');
    is($u->('/:path/', {}, {}), '/', 'nothing at all');
    is($u->('/:year/:month/', { date_string => '2018-03-05T14:15:16+01:00', slug => 's' }, {}), '/2018/03/', 'with a time zone');
};

subtest 'front matter' => sub {
    my $old = project('_layout/post.html' => 'x', '_layout/wide.html' => 'w');
    spew("$old/_posts/2018-03-04-a.md", "---\ntitle: A\nlayout: wide\ntags: perl\ndescription: Desc\nexcerpt: Not used\n---\nx\n");
    spew("$old/_posts/2018-03-04-b.md", "---\ntitle: B\nlayout: missing\ntags: one, two three\ncategory: Solo\n---\nx\n");
    spew("$old/_posts/2018-03-04-c.md", "---\ndate: 2019-12-31 23:00:00 +0100\npermalink: /c/\nslug: see\n---\nx\n");
    spew("$old/_posts/2018-03-04-d.md", "---\ntitle: D\npublished: false\n---\nx\n");
    spew("$old/_posts/2018-03-04-e.md", "---\ntitle: E\npublished: no\n---\nx\n");
    spew("$old/_posts/2018-03-04-f.md", "---\ntitle: F\npublished: true\ndraft: true\nzeta: 1\nalpha: 2\n---\nx\n");
    spew("$old/_posts/2018-03-04-g.md", "No front matter at all.\n");
    spew("$old/_posts/2018-03-04-h.md", "---\ntitle: H\ncategory: Big News\n---\nx\n");
    run_import('jekyll', $old);

    my $a = front('_source/blog/a.md');
    is($a->{layout}, 'wide', 'a layout the project has is kept');
    is_deeply($a->{tags}, ['perl'], 'one tag as text');
    is($a->{description}, 'Desc', 'description wins over excerpt');
    my $b = front('_source/blog/b.md');
    is($b->{layout}, 'post', 'a layout the project lacks: post');
    is_deeply($b->{tags}, ['one', 'two', 'three'], 'tags split on commas and spaces');
    is_deeply($b->{categories}, ['Solo'], 'category');
    is($b->{urlpattern}, '/solo/2018/03/04/b.html', 'and in the address');
    my $c = front('_source/blog/c.md');
    is($c->{date}, '2019-12-31T23:00:00+01:00', 'the date in front matter wins, with its zone');
    is($c->{urlpattern}, '/c/', 'its own permalink');
    is($c->{slug}, 'see', 'other keys are kept');
    ok(!exists $c->{title}, 'no title');
    my $e = front('_source/blog/e.md');
    ok($e->{draft}, 'published: no is a draft');
    ok(!exists $e->{urlpattern}, 'with no address');
    ok(!exists $e->{published}, 'published is not kept');
    my $f = front('_source/blog/f.md');
    ok(!exists $f->{draft}, 'draft: true in a Jekyll post is not kept (Jekyll ignores it)');
    is_deeply([ grep { /^(?:alpha|zeta)$/ } map { /^(\w+):/ ? $1 : () } split /\n/, slurp('_source/blog/f.md') ], ['alpha', 'zeta'], 'other keys sorted');
    ok(!exists front('_source/blog/g.md')->{title}, 'a post without front matter: no title');
    is(front('_source/blog/g.md')->{date}, '2018-03-04T00:00:00', 'the date from its name');
    is(body('_source/blog/g.md'), "No front matter at all.\n", 'its text is kept');

    my $d = front('_source/blog/d.md');
    ok($d->{draft}, 'published: false is a draft');
    ok(!exists $d->{urlpattern}, 'with no address');
    my $h = front('_source/blog/h.md');
    is_deeply($h->{categories}, ['Big News'], 'category with a space is one category');
};

subtest 'posts, drafts and pages' => sub {
    my $old = project();
    spew("$old/_posts/2018-03-04-one.md", "---\ntitle: One\n---\nx\n");
    spew("$old/_posts/2018/2018-04-01-nested.html", "---\ntitle: Nested\n---\n<p>x</p>\n");
    spew("$old/_posts/2018-05-01-mkd.mkd", "---\ntitle: Mkd\n---\nx\n");
    spew("$old/_posts/2018-05-02-cap.MARKDOWN", "---\ntitle: Cap\n---\nx\n");
    spew("$old/_posts/not-a-post.md", "---\ntitle: x\n---\nx\n");
    spew("$old/_posts/2018-05-03-text.txt", "---\ntitle: x\n---\nx\n");
    spew("$old/_drafts/idea.md", "---\ntitle: Idea\n---\nx\n");
    spew("$old/_drafts/2019-01-01-dated.md", "---\ntitle: Dated\n---\nx\n");
    spew("$old/_drafts/linked.md", "---\ntitle: Linked\npermalink: /linked/\n---\nx\n");
    spew("$old/about.md", "---\ntitle: About\n---\nAbout.\n");
    spew("$old/index.html", "---\nlayout: default\n---\nHome\n");
    spew("$old/docs/guide.html", "---\ntitle: Guide\npermalink: /:path/\n---\n<p>Guide.</p>\n");
    spew("$old/docs/deep/more.markdown", "---\ntitle: More\n---\nx\n");
    spew("$old/no-front.md", "Not a page.\n");
    spew("$old/README.md", "---\ntitle: Readme\n---\nx\n");
    spew("$old/LICENSE.md", "---\n---\nx\n");
    spew("$old/changelog.html", "---\n---\nx\n");
    spew("$old/style.scss", "---\n---\nbody {}\n");
    spew("$old/$_/page.md", "---\ntitle: No\n---\nx\n") for qw( _site _includes .git node_modules vendor assets images img css js scss sass files uploads );
    spew("$old/sub/_hidden/page.md", "---\ntitle: No\n---\nx\n");
    spew("$old/sub/.cache/page.md", "---\ntitle: No\n---\nx\n");
    spew("$old/sub/assets/page.md", "---\ntitle: Yes\n---\nx\n");

    my ($state, $out) = run_import('jekyll', $old, loud => 1);
    is_deeply(files($state), [ sort map { "_source/$_" } qw( blog/one.md blog/nested.html blog/mkd.md blog/cap.md blog/idea.md blog/dated.md blog/linked.md
        about.md index.html docs/guide.html docs/deep/more.md sub/assets/page.md ) ], 'what was imported');
    is_deeply([ map { "$_->{kind} $_->{draft}" } sort { $a->{file} cmp $b->{file} } @{$state->{pages}} ],
        ['page 0', 'post 0', 'post 1', 'post 1', 'post 1', 'post 0', 'post 0', 'post 0', 'page 0', 'page 0', 'page 0', 'page 0'], 'kinds and drafts');
    is(front('_source/blog/nested.html')->{urlpattern}, '/2018/04/01/nested.html', 'a post in a folder');
    is(front('_source/blog/idea.md')->{draft}, 1, 'a draft');
    ok(!exists front('_source/blog/idea.md')->{date}, 'without a date');
    ok(!exists front('_source/blog/idea.md')->{urlpattern}, 'or an address');
    is(front('_source/blog/dated.md')->{date}, '2019-01-01T00:00:00', 'a draft with a date in its name');
    is(front('_source/blog/linked.md')->{urlpattern}, '/linked/', 'a draft with its own permalink keeps it');
    is(front('_source/docs/guide.html')->{urlpattern}, '/docs/guide/', 'a page with a permalink');
    ok(!exists front('_source/about.md')->{urlpattern}, 'a page without one');
    ok(!exists front('_source/about.md')->{layout}, 'and no layout');
    ok(!exists front('_source/index.html')->{layout}, 'a layout the project lacks is dropped from a page');
    is($out, "Imported 7 posts and 5 pages into _source (3 as drafts).\nCopied 7 other files.\nRun \"dapper check\" to find links that need fixing.\n", 'the report (the pages in asset folders are copied as files)');
    ok(-f "$_/page.md", "$_/page.md copied as it is") for qw( assets images img css js files uploads );
};

subtest 'Liquid' => sub {
    my $old = project();
    spew("$old/_config.yml", "permalink: pretty\nbaseurl: /old\n");
    spew("$old/_posts/2018-03-04-first.md", <<'MD');
---
title: First
---
See [two]({% post_url 2018-04-01-second %}), [nested]({%post_url 2018/2018-05-01-deep%}) and [gone]({% post_url 2000-01-01-gone %}).
![x]({{ site.baseurl }}/assets/x.png) ![y]({{site.url}}/y.png) ![z]({{- site.baseurl -}}/z.png)
[a]({{ '/about/' | relative_url }}) [b]({{ "/b/" | absolute_url }}) [c]({{ "/c/"|relative_url }})
{% raw %}{{ kept }}{% endraw %} {%- raw -%}{% also %}{%- endraw -%}

{% highlight perl %}
print "<1>";
{% endhighlight %}

{% highlight ruby linenos %}
puts 1
{% endhighlight %}
{%- highlight js -%}
x()
{%- endhighlight -%}
MD
    spew("$old/_posts/2018-04-01-second.html", <<'HTML');
---
title: Second
---
{% highlight perl %}
my $x = '<a>' & 1;
{% endhighlight %}
<a href="{{ site.baseurl }}{% post_url 2018-03-04-first %}">first</a>
HTML
    spew("$old/_posts/2018/2018-05-01-deep.md", "---\ntitle: Deep\n---\n{% include note.html %} {{ page.title }}\n");
    spew("$old/plain.md", "---\ntitle: Plain\n---\nNo Liquid here.\n");

    my ($state, $out) = run_import('jekyll', $old, loud => 1);
    is(body('_source/blog/first.md'), <<'MD', 'Markdown');
See [two](/2018/04/01/second/), [nested](/2018/05/01/deep/) and [gone]({% post_url 2000-01-01-gone %}).
![x](/assets/x.png) ![y](/y.png) ![z](/z.png)
[a](/about/) [b](/b/) [c](/c/)
{{ kept }} {% also %}

```perl
print "<1>";
```

```ruby
puts 1
```
```js
x()
```
MD
    is(body('_source/blog/second.html'), <<'HTML', 'HTML: highlight becomes escaped code');
<pre><code class="language-perl">my $x = '&lt;a&gt;' &amp; 1;</code></pre>
<a href="/2018/03/04/first/">first</a>
HTML
    is(body('_source/blog/deep.md'), "{% include note.html %} {{ page.title }}\n", 'other Liquid is left');
    is_deeply($state->{notes}, {
        "post_url links to posts that weren't found" => ['_source/blog/first.md'],
        'Liquid tags Dapper does not run ({{ ... }} or {% ... %}); replace them, or set template: true and use Dapper template code'
            => ['_source/blog/first.md', '_source/blog/deep.md'],
    }, 'notes');
    like($out, qr{^Check: Liquid tags Dapper does not run \(\{\{ \.\.\. \}\} or \{% \.\.\. %\}\); replace them, or set template: true and use Dapper template code \(2 pages, such as _source/blog/first\.md\)$}m, 'reported');
    like($out, qr{^Check: post_url links to posts that weren't found \(1 page, such as _source/blog/first\.md\)$}m, 'reported');
};

subtest 'assets, --to and dry runs' => sub {
    my $old = project();
    spew("$old/_posts/2018-03-04-a.md", "---\ntitle: A\n---\nx\n");
    spew("$old/$_/file-$_.txt", $_) for qw( assets images img css js files uploads fonts );
    spew("$old/assets/sub/deep.txt", 'deep');
    spew("$old/assets/.DS_Store", 'x');
    spew("$old/favicon.ico", 'ico');
    spew("$old/other/x.txt", 'not copied');

    my ($state, $out) = run_import('jekyll', $old, dry_run => 1, to => 'posts', loud => 1);
    is_deeply(files($state), ['_source/posts/a.md'], 'into --to');
    is($state->{copied}, 10, 'ten files would be copied');
    ok(!-e 'assets', 'but nothing is');
    is($out, "Would import 1 post and 0 pages into _source.\nWould copy 10 other files.\n", 'the report');

    ($state, $out) = run_import('jekyll', $old, loud => 1);
    is(slurp("$_/file-$_.txt"), $_, "$_ copied into the project") for qw( assets images img css js files uploads fonts );
    is(slurp('assets/sub/deep.txt'), 'deep', 'folders inside');
    ok(!-e 'assets/.DS_Store', 'not hidden files');
    is(slurp('favicon.ico'), 'ico', 'favicon.ico');
    ok(!-e 'other', 'other folders are not');
    like($out, qr{^Copied 10 other files\.$}m, 'reported');

    spew('assets/file-assets.txt', 'mine');
    ($state, $out) = run_import('jekyll', $old, loud => 1);
    is(slurp('assets/file-assets.txt'), 'mine', 'a file already there is left alone');
    is($state->{copied}, 0, 'nothing copied');
    is(scalar @{$state->{skipped}}, 11, 'the post and ten files left alone');
    like($out, qr{^Left alone 11 files that already exist:\n  _source/blog/a\.md\n}m, 'reported');

    my $one = project();
    spew("$one/favicon.ico", 'ico');
    (undef, $out) = run_import('jekyll', $one, loud => 1);
    is($out, "Imported 0 posts and 0 pages into _source.\nCopied 1 other file.\n", 'one file');
};

subtest 'errors' => sub {
    my $old = project();
    spew("$old/file.txt", 'x');
    eval { run_import('jekyll', "$old/file.txt") };
    is($@, "error: give the Jekyll site's directory\n", 'a file');
    eval { run_import('jekyll', "$old/nope") };
    is($@, "error: \"$old/nope\" doesn't exist\n", 'missing');
};

done_testing();
