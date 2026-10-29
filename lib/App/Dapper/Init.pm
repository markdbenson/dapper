package App::Dapper::Init;

=head1 NAME

App::Dapper::Init - Starter projects for the "dapper init" command.

=head1 DESCRIPTION

C<dapper init> writes a starter project into the current directory. These
templates are built in (C<dapper templates> lists them):

=over 4

=item B<default>

The smallest project: a project file, one layout and one page.

=item B<blog>

A complete blog: a home page that lists the newest posts across several
pages, a page per post, category and tag pages, an Atom feed, a sitemap,
SEO tags, a schema for posts, a menu from a data file, code highlighting,
and optional search.

=item B<portfolio>

A grid of projects with images, and about and contact pages.

=item B<business>

A small business: services, opening hours, contact details and news, all from
one data file.

=item B<docs>

Documentation with a sidebar, previous and next links, and code highlighting.

=back

    $ dapper init
    $ dapper init --template blog
    $ dapper init --template ./my-theme
    $ dapper init --template https://github.com/someone/dapper-theme.git

A template can also be a directory, or a git repository (cloned with C<git>),
laid out like a project: its files are copied into the current directory
(without C<.git>, the output directory or C<.dapper>).

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use App::Dapper::Utils;
use App::Dapper::Theme::Portfolio;
use App::Dapper::Theme::Business;
use App::Dapper::Theme::Docs;
use File::Temp qw/ tempdir /;
use File::Find ();
use File::Basename ();

my %TEMPLATES;

$TEMPLATES{default} = {
    '_config.yml' => <<'FILE',
# Dapper configuration file
---
name : My Site

# Where "dapper deploy" publishes the site. Uncomment "deploy:" and one
# of the targets below. See "Deploying with dapper deploy" in the README.
#deploy:
#  s3:
#    bucket: example.com
#  github_pages:
#    branch: gh-pages
#  command: rsync -av --delete _output/ me@example.com:/var/www/site/
FILE

    '_source/index.md' => <<'FILE',
---
layout: index
title: Welcome
---

Hello world.

FILE

    '_layout/index.html' => <<'FILE',
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>[% page.title %]</title>
</head>

<body>

[% page.content %]

</body>
</html>

FILE
};

$TEMPLATES{blog} = {
    '_config.yml' => <<'FILE',
# Dapper configuration file. See https://github.com/markdbenson/dapper
---
name: My Blog
description: Notes, ideas and things I've learned.
author: Your Name

# The address the site will be published at, without a trailing slash.
# Needed for the sitemap, the feed and absolute links in llms.txt.
url: https://example.com

# The time zone that dates in posts are written in.
timezone: America/Chicago

# An Atom feed of the blog at /feed.xml.
feed:
  category: blog
  limit: 20

# A page for each category and tag.
category_pages:
  layout: list
tag_pages:
  layout: list

# Set to true to build a search index with Pagefind (https://pagefind.app).
search: false

# Where "dapper deploy" publishes the site. Uncomment "deploy:" and one
# of the targets below. See "Deploying with dapper deploy" in the README.
#deploy:
#  s3:
#    bucket: example.com
#  github_pages:
#    branch: gh-pages
#  command: rsync -av --delete _output/ me@example.com:/var/www/site/
FILE

    '_layout/index.html' => <<'FILE',
---
description: The page wrapper used by every page (header with the menu, footer, SEO tags, code highlighting, search)
---
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>[% IF page.title %][% page.title | html %] - [% END %][% site.name | html %]</title>
[% page.seo %]
  <link rel="stylesheet" href="/css/site.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css">
[% IF site.search %]
  <link rel="stylesheet" href="/pagefind/pagefind-ui.css">
[% END %]
</head>
<body>
  <header>
    <a class="site-name" href="/">[% site.name | html %]</a>
    <nav>
[% FOR item IN site.data.menu %]
      <a href="[% item.url %]">[% item.label | html %]</a>
[% END %]
    </nav>
  </header>
[% IF site.search %]
  <div id="search"></div>
[% END %]
  <main>
[% page.content %]
  </main>
  <footer>
    &copy; [% site.time.year %] [% site.author | html %] &middot;
    <a href="/feed.xml">Feed</a>
  </footer>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
  <script>hljs.highlightAll();</script>
[% IF site.search %]
  <script src="/pagefind/pagefind-ui.js"></script>
  <script>new PagefindUI({ element: "#search", showSubResults: true });</script>
[% END %]
</body>
</html>
FILE

    '_layout/post.html' => <<'FILE',
---
layout: index
description: A blog post, with its date and tags
---
<article data-pagefind-body>
  <h1>[% page.title | html %]</h1>
  <p class="meta">
    [% page.date.strftime('%d %B %Y') %]
[% IF page.tags %]
    &middot;
[% FOR tag IN page.tags %]
    <a href="[% site.tag_pages.item(tag) %]">#[% tag | html %]</a>
[% END %]
[% END %]
  </p>
  [% page.content %]
</article>
FILE

    '_layout/list.html' => <<'FILE',
---
layout: index
description: A list of posts, used for the category and tag pages
---
<h1>[% page.title | html %]</h1>
[% FOR post IN page.posts %]
<article>
  <h2><a href="[% post.url %]">[% post.title | html %]</a></h2>
  <p class="meta">[% post.date.strftime('%d %B %Y') %]</p>
  [% post.excerpt %]
</article>
[% END %]
FILE

    '_source/index.html' => <<'FILE',
---
title: Home
template: true
paginate:
  category: blog
  per_page: 10
---
[% FOR post IN paginator.items %]
<article>
  <h2><a href="[% post.url %]">[% post.title | html %]</a></h2>
  <p class="meta">[% post.date.strftime('%d %B %Y') %]</p>
  [% post.excerpt %]
  <p><a href="[% post.url %]">Read more</a></p>
</article>
[% END %]

<nav class="pages">
[% IF paginator.previous_url %]<a href="[% paginator.previous_url %]">Newer posts</a>[% END %]
[% IF paginator.next_url %]<a href="[% paginator.next_url %]">Older posts</a>[% END %]
</nav>
FILE

    '_source/about.md' => <<'FILE',
---
title: About
description: Who writes this blog, and why.
---

This is the about page. Edit `_source/about.md` to tell readers who you are.

FILE

    '_source/blog/_schema.yml' => <<'FILE',
# Every post must have these. Run "dapper check" to see any problems.
required: [title, date, categories]
fields:
  title:
    type: string
    max_length: 100
  date:
    type: date
  categories:
    type: list
    values: [blog]
  tags:
    type: list
  description:
    type: string
    max_length: 200
FILE

    '_source/blog/welcome.md' => <<'FILE',
---
title: Welcome to Your New Blog
layout: post
categories: blog
tags: [dapper]
date: 2026-01-01T09:00:00
description: What's in this starter blog, and where to go next.
---

This is your first post. The first paragraph of a post is its excerpt, shown
on the home page and in the feed.

Posts live in `_source/blog/`. Each starts with front matter (the settings
between the `---` lines), and `_source/blog/_schema.yml` says which settings
every post needs.

## Code

Code blocks are highlighted:

```perl
print "Hello, world!\n";
```

## Next steps

* Edit `_config.yml` with your site's name and address.
* Run `dapper serve` and open http://localhost:8000.
* Run `dapper check` to find broken links and missing settings.

FILE

    '_source/blog/writing-posts.md' => <<'FILE',
---
title: Writing Posts
layout: post
categories: blog
tags: [dapper, writing]
date: 2026-01-02T09:00:00
---

Create a file in `_source/blog/` with a title, a date and `categories: blog`,
then write in Markdown below the front matter. The post appears on the home
page, in the feed, on its tag pages and in the sitemap.

FILE

    '_data/menu.yml' => <<'FILE',
# The links in the site's header (site.data.menu)
- label: Home
  url: /
- label: Blog
  url: /blog/
- label: About
  url: /about.html
FILE

    'css/site.css' => <<'FILE',
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  line-height: 1.6;
  max-width: 42em;
  margin: 0 auto;
  padding: 1em;
  color: #222;
}
header { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 2em; }
header nav a { margin-left: 1em; }
.site-name { font-weight: bold; text-decoration: none; color: inherit; }
.meta { color: #666; font-size: 0.9em; }
pre { overflow-x: auto; }
footer { margin-top: 3em; color: #666; font-size: 0.9em; }
@media (prefers-color-scheme: dark) {
  body { background: #111; color: #ddd; }
  a { color: #8ab4f8; }
}
FILE
};

# Notes about each template, added to AGENTS.md below the part Dapper writes
my %NOTES;

my %DESCRIPTIONS = (
    default => 'The smallest project: a project file, one layout and one page',
    blog    => 'A blog: paginated home page, posts, category and tag pages, feed, a schema for posts',
);

for my $theme (qw/ Portfolio Business Docs /) {
    my $class = "App::Dapper::Theme::$theme";
    my $name = lc $theme;
    $TEMPLATES{$name} = $class->files();
    $DESCRIPTIONS{$name} = $class->description();
}

my $GITIGNORE = <<'FILE';
_output/
.dapper/
FILE

$NOTES{blog} = <<'NOTES';
## About this blog

- Posts go in `_source/blog/`, one Markdown file each, with `layout: post`,
  `categories: blog`, a `title`, a `date` and optional `tags`.
- The home page (`_source/index.html`) lists posts ten to a page, newest first.
- The menu is `_data/menu.yml`.
NOTES
$NOTES{$_} = "App::Dapper::Theme::\u$_"->notes() for qw/ portfolio business docs /;

=head2 templates

Returns the names of the built-in templates.

=cut

sub templates {
    return sort keys %TEMPLATES;
}

=head2 description

Takes a template name and returns its one-line description.

=cut

sub description {
    my ($name) = @_;
    return $DESCRIPTIONS{$name};
}

=head2 template_files

Takes a template: a built-in name, a directory, or a git URL. Returns a hash
of the template's files (path to content) and its notes for C<AGENTS.md>.

=cut

sub template_files {
    my ($template) = @_;

    return ($TEMPLATES{$template}, $NOTES{$template}) if $TEMPLATES{$template};

    my $dir = $template;
    if ($template =~ m{^(?:https?|git|ssh)://|^git@|\.git$}) {
        $dir = tempdir(CLEANUP => 1) . '/template';
        system('git', 'clone', '--quiet', '--depth', '1', '--', $template, $dir) == 0
            or die "error: could not clone the template from $template (is git installed, and is the URL right?)\n";
    }
    elsif (not -d $dir) {
        die "error: there is no template called \"$template\"; use one of: " . join(', ', templates())
          . ", a directory, or a git URL\n";
    }

    my %files;
    my $root = App::Dapper::Utils::name_bytes($dir);
    File::Find::find({
        no_chdir => 1,
        wanted   => sub {
            my $path = App::Dapper::Utils::name_chars($File::Find::name);
            (my $relative = $path) =~ s{^\Q$dir\E/?}{};
            return if $relative eq '';
            if (-d $File::Find::name) {
                $File::Find::prune = 1 if $relative =~ m{^(?:\.git|_output|\.dapper|node_modules)$};
                return;
            }
            return if $relative =~ m{(?:^|/)\.DS_Store$};
            open(my $fh, '<:raw', $File::Find::name) or die "error: could not read $path: $!\n";
            local $/;
            $files{$relative} = { raw => scalar <$fh> };
            close $fh;
        },
    }, $root);

    die "error: the template $template has no files\n" unless %files;
    return (\%files, undef);
}

=head2 init

Initialize a Dapper project from a template. Takes the source directory,
output directory, layout directory, config file name and template name
(default: C<default>). Nothing is written if any of the files already exist.
A C<.gitignore> for the output directory is added if there isn't one.
Returns the template's notes for C<AGENTS.md>, if it has any.

=cut

sub init {
    my ($source, $output, $layout, $config, $template) = @_;

    $template = 'default' unless defined $template;
    my ($files, $notes) = template_files($template);

    # Map the template's paths onto the directories being used
    my %targets;
    for my $path (keys %$files) {
        my $target = $path;
        $target =~ s{^_source/}{$source/};
        $target =~ s{^_layout/}{$layout/};
        $target = $config if $target eq '_config.yml';
        $targets{$target} = $files->{$path};
    }

    my @existing = sort grep { -e $_ } keys %targets;
    die "error: refusing to initialize, these files already exist: @existing\n" if @existing;

    for my $target (sort keys %targets) {
        my $content = $targets{$target};
        if (ref $content) {
            # A file from a template directory, copied byte for byte
            print "Creating $target\n" unless $App::Dapper::Utils::QUIET;
            my $dir = File::Basename::dirname($target);
            App::Dapper::Utils::create_dir($dir) unless -d $dir;
            open(my $fh, '>:raw', $target) or die "error: could not write $target: $!\n";
            print $fh $content->{raw};
            close $fh;
        }
        else {
            App::Dapper::Utils::create_file($target, $content);
        }
    }

    if (not -e '.gitignore') {
        (my $ignore = $GITIGNORE) =~ s{^_output/}{$output/}m;
        App::Dapper::Utils::create_file('.gitignore', $ignore);
    }

    return $notes;
}

1;
