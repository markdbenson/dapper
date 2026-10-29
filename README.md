# Dapper

[![test](https://github.com/markdbenson/dapper/actions/workflows/test.yml/badge.svg)](https://github.com/markdbenson/dapper/actions/workflows/test.yml)
[![CPAN](https://img.shields.io/cpan/v/App-Dapper.svg)](https://metacpan.org/dist/App-Dapper)

A publishing tool for static websites

[Distributed as a Perl module](https://metacpan.org/dist/App-Dapper),
Dapper comes with a command-line application called `dapper` which you
can use to create static websites.

    $ cpanm App::Dapper # Install
    $ dapper init       # Initialize current directory with new site
    $ dapper serve      # Build and serve locally at http://localhost:8000

Dapper has three goals:

1. **Simple**. Learning Dapper is easy -- it gets out of the way so you can
   write content, develop layouts, and deploy to production the way you
   want.

2. **Flexible**. Content is written in
   [Markdown](https://metacpan.org/pod/Text::MultiMarkdown), and
   templates are written using the TT3 mini-language from
   [Template::Alloy](https://metacpan.org/pod/Template::Alloy) for 
   maximum flexibility.

3. **Pragmatic**. The easy things are easy and the hard things are
   possible. Dapper was created to solve problems in a straight-forward
   and intuitive way.

Why static? Decent question. Here are some reasons:

1. **Fast**. Static pages are fast to load and easy to cache. Content
   management systems, on the other hand, may contact the database at
   least one time per page request, process the results, merge with a
   templating system, and serve the result to the user's web browser.

2. **Cheap**. Having a static website means that options for hosting those
   static files also just got a lot more simple. No database is needed and
   no real processing power for scripting is needed. For example, with a
   static website, it becomes possible to host the site on
   [Github Pages](https://pages.github.com/) for free, or
   [Amazon S3](http://aws.amazon.com/s3/) for very modest fees.

3. **Secure**. It's much more secure to host a static website than a
   dynamic one.  Content management systems that use scripting languages
   such as Perl, Python, or Ruby, all are more susceptible to being hacked
   than a static website is.  Simply stated, why use a dynamic content-
   management system if a static setup will do?

4. **Portable**. With a static website, it's way easier to move the site
   to a new host in the future. All web hosts now and in the future
   support serving up a static website -- think of it as the lowest common
   denominator -- and so there's no need to pick a premium host with
   premium services.

Dapper was first written in 2002 to facilitate the creation of a series
of static websites that each had their own look and feel, but shared
content. Since then, Dapper has been used to create websites for speakers,
artists, authors, illusionists, web designers, piano tuners,
photographers, entertainment agencies, and API documentation for
industrial sensing equipment. For many years it was also the tool that
powered the author's personal website.

In 2014, Dapper was submitted as a Perl module (App::Dapper) to
[CPAN](http://cpan.org/) under the MIT license for anyone to use for any
purpose.

**Features**

* Content in Markdown (with highlightable fenced code blocks) or HTML, with YAML front matter.
* Layouts in the TT3 mini-language from Template::Alloy. Content is safe by default: it is never run as template code unless a page asks.
* Front matter schemas, data files, categories, tags, pagination, and generated category and tag pages.
* A built-in sitemap, Atom feed, SEO and structured data tags, and Markdown copies of pages with an `llms.txt` index for AI tools.
* `dapper check` finds broken links and front matter mistakes; `dapper serve` rebuilds and reloads the browser as you edit.
* An MCP server, so AI assistants can write, check and build the site, with your schemas as guardrails.
* Install from CPAN, as a single file, with Homebrew, or with Docker.

The rest of this document shows you how to get your site up and running,
how to manage the content and the way it looks, and how to deploy the
result to your favorite web host.

**Contents**

* [Getting Started](#getting-started)
    * [Install](#install)
    * [Usage](#usage)
    * [Directory Structure](#directory-structure)
* [Tutorial: Build a Blog](#tutorial-build-a-blog)
* [Configuration](#configuration)
* [Source](#source)
    * [Template code in content](#template-code-in-content)
    * [Front matter schemas](#front-matter-schemas)
    * [Data files](#data-files)
    * [Source file types](#source-file-types)
    * [Assets](#assets)
    * [Drafts and clean builds](#drafts-and-clean-builds)
    * [Headings](#headings)
    * [Text](#text)
    * [Lists](#lists)
    * [Tables](#tables)
    * [Images](#images)
    * [Footnotes](#footnotes)
* [Layout](#layout)
    * [Variables](#variables)
    * [Pagination](#pagination)
    * [Category and tag pages](#category-and-tag-pages)
    * [Comments](#comments)
    * [Filters](#filters)
    * [Conditionals](#conditionals)
    * [Iteration](#iteration)
    * [Blocks](#blocks)
    * [Perl code](#perl-code)
    * [Includes](#includes)
    * [Macros](#macros)
    * [Plugins](#plugins)
    * [Chomping](#chomping)
    * [Dumping](#dumping)
* [Publishing for Search Engines and AI](#publishing-for-search-engines-and-ai)
    * [Sitemap](#sitemap)
    * [Feed](#feed)
    * [SEO tags](#seo-tags)
    * [Markdown copies and llms.txt](#markdown-copies-and-llmstxt)
    * [Search](#search)
* [AI Assistants (MCP)](#ai-assistants-mcp)
* [Deployment](#deployment)
    * [Amazon S3](#amazon-s3)
    * [GitHub Pages](#github-pages)
* [What Dapper Doesn't Do](#what-dapper-doesnt-do)
* [Upgrading to 1.0](#upgrading-to-10)
* [Upgrading from 0.21](#upgrading-from-021)
* [Troubleshooting](#troubleshooting)
* [Further Reading](#further-reading)
* [Appendix A: Extending](#appendix-a-extending)
* [Appendix B: Debugging](#appendix-b-debugging)
* [Appendix C: Internals](#appendix-c-internals)
* [Appendix D: Contributing](#appendix-d-contributing)
* [Author](#author)
* [License and Copyright](#license-and-copyright)

# Getting Started

The following sections show you how to install, upgrade, and downgrade the
version of Dapper you have, as well as how to use the `dapper` command-
line utility and work with the directory structure it depends on.

## Install

Dapper needs Perl 5.10 or newer. Check with `perl -v`. It is installed
with `cpanm`; if you don't have it, install it first:

    $ curl -L https://cpanmin.us | perl - App::cpanminus

On macOS, the Perl that comes with the system is best left alone. Rather
than installing modules into it with `sudo`, install your own Perl with
[Homebrew](https://brew.sh/) (`brew install perl`) or
[perlbrew](https://perlbrew.pl/), or install modules into your home
directory with [local::lib](https://metacpan.org/pod/local::lib).

Install Dapper in seconds:

    $ cpanm App::Dapper

Other ways to install, if you'd rather not use `cpanm`:

* **A single file.** Download `dapper` from the
  [latest release](https://github.com/markdbenson/dapper/releases/latest).
  It runs with any Perl 5.10 or newer and needs nothing else installed:

      $ curl -fsSLo dapper https://github.com/markdbenson/dapper/releases/latest/download/dapper
      $ chmod +x dapper
      $ sudo mv dapper /usr/local/bin/

* **Homebrew:** `brew install markdbenson/tap/dapper`

* **Docker**, with no Perl at all. Run it in your project directory:

      $ docker run --rm -v "$PWD":/site ghcr.io/markdbenson/dapper build
      $ docker run --rm -v "$PWD":/site -p 8000:8000 ghcr.io/markdbenson/dapper serve

Then, create a new site, build it, and view it locally like so:

    $ mkdir new-site && cd new-site
    $ dapper init
    $ dapper build
    $ dapper serve

For a complete starter blog (layouts, a paginated home page, category and
tag pages, a feed, a schema for posts and more), use
`dapper init --template blog` instead of `dapper init`.

After that, browse to [http://localhost:8000](http://localhost:8000) to
see your site.  To modify the content, look at `_source/index.md`. To
modify the layout, edit `_layout/index.html`.

### Upgrade

Find out which version of Dapper you have, by using the `-v` option:

    $ dapper -v

You can compare this with the latest version from CPAN like this:

    $ cpan -D App::Dapper

    ...
    M/MD/MDB/App-Dapper-0.22.tar.gz
    /Library/Perl/5.34/App/Dapper.pm
    Installed: 0.21
    CPAN:      0.22  Not up to date
    Mark Benson (MDB)

In this example, you can see there is a newer version available. Upgrade
like this:

    $ cpan App::Dapper

Stable releases are available on CPAN, but development happens at
[Github](https://github.com/markdbenson/dapper). If you like living on the
edge, install from the latest development tip like this:

    $ cpanm https://github.com/markdbenson/dapper.git

A list of recent commits can also be
[viewed on Github](https://github.com/markdbenson/dapper/commits/master).

### Downgrade

If you want to install an older version of Dapper, first find the link on
[backpan](http://backpan.perl.org/authors/id/M/MD/MDB/). Then, install like
this (e.g. v0.13):

    $ cpanm http://backpan.perl.org/authors/id/M/MD/MDB/App-Dapper-0.13.tar.gz

If you want, you can also install from source. To do that, you just need to
download and unpack the desired release from
[backpan](http://backpan.perl.org/authors/id/M/MD/MDB/), or clone the
repository from Github. Then, do this:

    $ perl Makefile.PL
    $ make
    $ make test
    $ make install

## Usage

When you install the `App::Dapper` Perl module, an executable named
`dapper` will be available to you in your terminal window. You can use
this executable in a number of ways. The following sections show you how.

### Init

The `dapper init` command initializes a new site. Note that the
site will be initialized in the current directory. Therefore, it's usually
best to create a blank directory that can be used for this purpose. A
description of the resulting directory structure is available in the
[Directory Structure](#directory-structure) section.

    # Initialize the current directory with a fresh skeleton of a site
    $ dapper init

    # ...or with a complete starter blog
    $ dapper init --template blog

### Build

After the site has been initialized, build it using the `dapper build`
command. Dapper takes care of reading the source files, combining them
with the layout template(s), and saving the result in the `_output`
directory.

    # Build the site
    $ dapper build

### Watch

The `dapper watch` command builds the site and then watches all the files
in the project for changes. If any changes occur, the site is rebuilt
again. The `dapper watch` command will do this repeatedly until you exit
using *Ctrl-C*.

    # Rebuild the site if anything changes
    $ dapper watch

Specifically, the dapper command watches all files in the current
directory and all subdirectories, including the project file
(`_config.yml`), and notices files that are added or removed. It does not
watch:

* Files and directories that begin with a period (.), such as `.git`.
* The output directory (`_output`, or whatever `output` is set to) and
  everything in it.

If a rebuild fails (for instance, because of a typo in a layout), the
error is printed and Dapper keeps watching.

### Serve

The `dapper serve` command builds the site, serves the contents of the
`_output` directory using Dapper's built-in webserver, and handles auto-
rebuilding your site if anything changes. You can think of the `dapper
serve` command as a combination of `build`, `watch`, and `serve`.

    # Serve the site locally at http://localhost:8000
    $ dapper serve

If you want to use a different port number (e.g. 9000), specify it using
the *-p* option:

    # Serve the site locally at http://localhost:9000
    $ dapper -p 9000 serve

While `dapper serve` is running, pages in your browser reload by themselves
after each rebuild. The server listens on every network interface, so other
devices on your network can reach it too, which is handy for testing on a
phone.

### Check

The `dapper check` command builds the site into a temporary directory and
reports every problem it finds, without touching the output directory:
front matter that can't be read or doesn't match its
[schema](#front-matter-schemas), missing layouts, mistakes in templates, two
pages that would be written to the same file, links and images that lead
nowhere, and pages without a title.

    $ dapper check
    error: _source/blog/new.md: links to /contact.html, which is not in the site
    Checked 12 pages: 1 error, 0 warnings.

It exits with status 1 when there are errors, so it can stop a deploy
script or a CI job. Add `--json` for a report that scripts and AI
assistants can read:

    $ dapper check --json

### MCP

The `dapper mcp` command runs a server that AI assistants can use to work on
the site. See [AI Assistants (MCP)](#ai-assistants-mcp).

### Options

Every command accepts these options. Directories given on the command line
take precedence over the ones in `_config.yml`, which take precedence over
the defaults.

Option                     | Description
---------------------------|------------------------------------------------------
`-s`, `--source` *dir*     | Source directory (default: `source` in `_config.yml`, or `_source`)
`-o`, `--output` *dir*     | Output directory (default: `output` in `_config.yml`, or `_output`)
`-l`, `--layout` *dir*     | Layout directory (default: `layout` in `_config.yml`, or `_layout`)
`-c`, `--config` *file*    | Project file (default: `_config.yml`)
`-p`, `--port` *number*    | Port for `dapper serve` (default: `8000`)
`-q`, `--quiet`            | Only print errors
`-C`, `--directory` *dir* | Run in this directory instead of the current one
`-t`, `--template` *name* | For `init`: the starter project, `default` or `blog`
`--json`                   | For `check`: print the report as JSON
`-h`, `--help`             | Print usage
`-v`, `--version`          | Print the version

### Help

To get more information about command-line options available, the current
version of Dapper that you have installed on your system, or further
documentation available, see the following:

    # Get help on usage and switches
    $ dapper -h

    # Print the version
    $ dapper -v

## Directory Structure

After running the [`dapper init`](#init) command, the following directory
structure will be created:

    _config.yml
    _layout/
        index.html
    _source/
        index.md

Here is a description of each file:

**_config.yml**

The configuration file is a [YAML](http://www.yaml.org/) file that specifies
key configuration elements for your static website. The default
configuration file is as follows:

    # Dapper configuration file
    ---
    name : My Site

If you want to use a separate source, layout, or output directory, you may
specify it in this file. For instance:

    # Dapper configuration file
    ---
    name : My Site
    source : _source
    layout : _layout
    output : _output

There are a few definitions that affect the way that Dapper behaves. Those
are defined in the [Configuration](#configuration) section. Those and any
others that you choose to specify become available in the layout templates
under the `site` namespace. For instance, `name` is available in templates
like this:

    [% site.name %]

**_source/index.md**

A sample markdown file is available in the `_source` directory. Contents:

    ---
    layout: index
    title: Welcome
    ---

    Hello world.

There are a few things to note about this file:

1. There is a YAML configuration block (the "front matter") at the start of the file.

2. The *layout* configuration specifies which layout to use.

3. The `index` layout indicates that `_layout/index.html` should be used.

4. The `title` configuration is the name of the post/page. It is optional.

5. All of the configurations may be used in the corresponding layout file.

    <!-- Example use of "title" in a layout file -->
    <h1>[% page.title %]</h1>

**_layout/index.html**

Layout files are processed using the TT3 mini-language from the Template::Alloy 
template system. The initial layout file that is given after you run the `dapper 
init` command, is this:

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

The main content of the text file that is being rendered with this template
is available using `[% page.content %]`.

Definitions specified in the `_config.yml` file can be referenced under the
"site" namespace (e.g. `[% site.name %]`). Definitions specified in the YAML
portion of text files can be referenced under the "page" namespace (e.g.
`[% page.title %]`).

In that same directory, you may then build the site using the `dapper
build` command, which will combine the source files and the layout files
and place the results in the output directory (default: `_output`). After
you build the default site, you'll then have the following directory
structure:

    _config.yml
    _layout/
        index.html
    _source/
        index.md
    _output/
        index.html

Now, you'll see a new directory that has been created (`_output`) that
contains a single file (`index.html`) containing a mashup of the source
file and the layout template.

**_output/index.html**

The output file that is created is a mix of the input file and the layout
that is specified by the input file. For the default site, the following
output file is created:

    <!DOCTYPE html>
    <html>
    <head>
      <meta charset="utf-8">
      <title>Welcome</title>
    </head>

    <body>

    <p>Hello world.</p>

    </body>
    </html>

# Tutorial: Build a Blog

This walkthrough builds a small blog: a home page that lists the latest
posts, one page per post, a stylesheet, and the feed, sitemap and SEO tags
that Dapper generates for you. Every file is shown in full, so you can copy
them as they are.

(`dapper init --template blog` creates a project much like this one, with
category and tag pages, a schema for posts and a menu as well. This
tutorial builds it by hand so you can see how the pieces fit.)

When it's done, the project looks like this:

    _config.yml
    _layout/
        index.html      The page wrapper used by every page
        post.html       A post, wrapped in index.html
    _source/
        index.html      The home page: a list of posts
        blog/
            hello-world.md
            second-post.md
    css/
        site.css        Copied to the output as it is

**1. The project file.** `url` is the address the site will be published at
(leave off the trailing slash); the sitemap, the feed and the SEO tags use
it to make absolute links. `timezone` is the time zone your post dates are
written in. `feed` turns on an Atom feed of the blog.

    # Dapper configuration file
    ---
    name: My Blog
    description: Notes on building things.
    url: https://example.com
    author: Jane Doe
    timezone: America/Chicago
    feed:
      category: blog

**2. The main layout**, `_layout/index.html`. Pages without a `layout`
setting use this one. `[% page.seo %]` adds the page's description,
canonical link, feed link, Open Graph tags and structured data.

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>[% page.title | html %] - [% site.name | html %]</title>
[% page.seo %]
  <link rel="stylesheet" href="/css/site.css">
</head>
<body>
  <header><a href="/">[% site.name | html %]</a></header>
  <main>
[% page.content %]
  </main>
  <footer>&copy; [% site.time.year %] [% site.author | html %]</footer>
</body>
</html>
```

**3. A post layout**, `_layout/post.html`. Its front matter says to wrap
it in the `index` layout, so a post gets the header and footer too.

```html
---
layout: index
---
<article>
  <h1>[% page.title | html %]</h1>
  <p class="date">[% page.date.strftime('%d %B %Y') %]</p>
  [% page.content %]
</article>
```

**4. Posts**, in `_source/blog/`. The `categories: blog` setting puts each
post in `site.categories.blog` (and so in the feed), and also means the
post is written to the path described by `urlpattern`
(`/:category/:year/:month/:slug/` by default), so this one becomes
`/blog/2026/10/hello-world/`.

```
---
title: Hello World
layout: post
categories: blog
date: 2026-10-01T09:00:00
---

This is my first post. This paragraph becomes the excerpt.

The rest of the post goes here.
```

Add a second post, `_source/blog/second-post.md`, the same way with a
later date.

**5. The home page**, `_source/index.html`. It is an `.html` file rather
than `.md` so that Markdown doesn't touch its HTML, and it sets
`template: true` because its content uses template code (see [Template
code in content](#template-code-in-content)). `paginate` hands it the posts
in `paginator.items`, newest first, ten to a page.

```html
---
title: Home
template: true
paginate:
  category: blog
  per_page: 10
---
<h1>Recent posts</h1>
[% FOR post IN paginator.items %]
<article>
  <h2><a href="[% post.url %]">[% post.title | html %]</a></h2>
  <p class="date">[% post.date.strftime('%d %B %Y') %]</p>
  [% post.excerpt %]
  <p><a href="[% post.url %]">Read more</a></p>
</article>
[% END %]
[% IF paginator.next_url %]<a href="[% paginator.next_url %]">Older posts</a>[% END %]
```

**6. A stylesheet**, `css/site.css`. Directories at the top of the project
are copied to the output as they are (see [Assets](#assets)), so this is
served at `/css/site.css`.

    body { font-family: sans-serif; max-width: 40em; margin: auto; }

**7. Build and look.**

    $ dapper serve

Browse to http://localhost:8000. Edit any file while `dapper serve` is
running and the site is rebuilt, and the page in your browser reloads by
itself. The output directory now contains:

    _output/
        index.html
        blog/2026/10/hello-world/index.html
        blog/2026/10/hello-world/index.md    A Markdown copy, for AI tools
        blog/2026/10/second-post/index.html
        blog/2026/10/second-post/index.md
        css/site.css
        feed.xml                             The Atom feed
        sitemap.xml                          For search engines
        llms.txt                             An index for AI tools
        llms-full.txt

**8. Check it.**

    $ dapper check
    Checked 3 pages: 0 errors, 0 warnings.

`dapper check` finds broken links, missing layouts and front matter
mistakes, without touching the output directory.

From here, you might add [category and tag pages](#category-and-tag-pages),
a [schema](#front-matter-schemas) so every post has what it needs,
[search](#search), or let an [AI assistant](#ai-assistants-mcp) write and
publish posts for you.

# Configuration

Dapper allows you to create static websites in just about any way that you
want to. The project configuration file (`_config.yml`) allows you to
specify special instructions to Dapper and also to guide the process of
rendering the site using the source files (`_source/`) and the layout
templates (`_layout/`).

Variables specified in `_config.yml` are done using YAML. Here is the
default configuration file created after a `dapper init` command:

    # Dapper configuration file
    ---
    name : My Site

Note that lines beginning with `#` are comments. Lines with `---` mark the
beginning/end of a YAML "document". What follows are `<key>:<value>`
pairs or arrays, arranged hierarchically:

    # Dapper config file
    ---
    name: My Portfolio
    url: https://example.com/
    source : _source
    output : _output
    layout : _layout
    links :
        About : /about/
        Blog : /blog/
        GitHub : https://github.com/markdbenson
    ignore :
        - ^\.
        - ^_
        - ^design$
        - ^README.md$
        - ^Makefile$

A few settings change the way Dapper behaves:

Setting       | Default                             | Meaning
--------------|-------------------------------------|---------------------------------------------
`source`      | `_source`                           | Directory of source files
`output`      | `_output`                           | Directory the site is written to
`layout`      | `_layout`                           | Directory of layout templates
`urlpattern`  | `/:category/:year/:month/:slug/`    | URL (and output path) of pages with categories; see [Source](#source)
`extension`   | `.html`                             | Extension of output files
`ignore`      | `^\.`, `^_`, `^dapper$`             | Regular expressions for top-level files that are not copied to the output
`timezone`    | your computer's time zone         | Time zone of dates written without one, e.g. `America/Chicago`. A page may set its own `timezone`.
`url`         | (none)                              | The address the site is published at, e.g. `https://example.com`. Needed for the sitemap and feed, and for absolute links in `llms.txt` and `page.seo`.
`description` | (none)                              | A sentence about the site, used by `llms.txt`, the feed and `page.seo`
`author`      | (none)                              | Used by the feed and `page.seo`
`image`       | (none)                              | The default image for `page.seo` (Open Graph)
`data_dir`    | `_data`                             | Directory of [data files](#data-files)
`templates_in_content` | `false`                    | Run template code in all content and in `_config.yml` values, as Dapper did before 1.0; see [Template code in content](#template-code-in-content)
`markdown_twins` | `true`                           | Write a Markdown copy next to each page made from Markdown
`llms_txt`    | `true`                              | Write `/llms.txt` and `/llms-full.txt`
`sitemap`     | `true`                              | Write `/sitemap.xml` (when `url` is set)
`feed`        | (off)                               | `true`, or settings: `category`, `path` (default `/feed.xml`), `limit` (default 20), `title`
`category_pages`, `tag_pages` | (off)               | Generate a page per category or tag; see [Category and tag pages](#category-and-tag-pages)
`search`      | `false`                             | Build a search index with Pagefind; see [Search](#search)
`search_command` | `pagefind`                       | The command to run for search, e.g. `npx -y pagefind`
`clean`       | `true`                              | Remove files that an earlier build wrote and this one did not

Directories given on the command line (`-s`, `-o`, `-l`) take precedence
over these settings.

Any variable specified in `_config.yml` can be used in a template. In the
example above, name can be used like this:

    [% site.name %]

URL can be used like this:

    <a href="[% site.url %]">[% site.name %]</a>

The links (key/value pairs) can be listed like this:

    [% for link in site.links %]
        <a href="[% link.value %]">[% link.key %]</a><br />
    [% end %]

All of the items in the `ignore` array can be shown like this:

    <ul>
    [% for i in site.ignore %]
        <li>[% i %]</li>
    [% end %]
    </ul>

See the official [YAML](http://yaml.org/) specification, or the
[YAML::PP](https://metacpan.org/pod/YAML::PP) Perl module
documentation (Dapper's YAML parsing engine) for more information.

# Source

Source files in Dapper are written in
[Markdown](https://daringfireball.net/projects/markdown/). Markdown is a
markup language that allows you to write content in a natural way, and
have that text converted to XHTML for displaying on the web.

Writing with Markdown allows you to separate the content and structure of
your document from the formatting which allows you to focus on the actual
writing.

Source files that are pages start with [YAML](http://yaml.org/) "front
matter". The front matter is denoted by leading and trailing lines that
each contain a sequence of three dashes, and must begin on the very first
line of the file. Example:

```
---
layout: post
title: Post Title
---

Here is the text of the post.
```

The variables specified as YAML are available under the `page` namespace
in layouts. The body of the page (`Here is the text of
the post.`) in the above example, is available as `content` in Template
Toolkit templates.

Files in the source directory that do *not* start with front matter, such
as images, PDFs, zip files or plain text, are copied to the same place in
the output directory exactly as they are.

Variable definitions in source files that carry special meaning are as
follows:

* `extension: .html` is the default used if not specified. To override,
  specify a new value for `extension` for that particular page. `extension`
  may also be specified in the `_config.yml` file to apply it globally.

* `urlpattern: /:category/:year/:month/:slug/` defines the URL path for
  the file. This may also be specified in `_config.yml` as well. If not
  specified, the following is used: `/:category/:year/:month/:slug/`. A
  full list of pattern options are as follows:

    - `:category` - The category of the page as defined by the page's
      YAML.
    - `:year` - The year the page was published as defined either by the
      `date` field in the page's YAML part, or from the file modification
      timestamp.
    - `:month` - The month the page was published as defined either by
      the
      `date` field in the page's YAML part, or from the file modification
      timestamp.
    - `:day` - The day the page was published as defined either by the
      `date` field in the page's YAML part, or from the file modification
      timestamp.
    - `:hour` - The hour the page was published as defined either by the
      `date` field in the page's YAML part, or from the file modification
      timestamp.
    - `:minute` - The minute the page was published as defined either by
      the `date` field in the page's YAML part, or from the file
      modification timestamp.
    - `:second` - The second the page was published as defined either by
      the `date` field in the page's YAML part, or from the file
      modification timestamp.
    - `:slug` - The title of the page with all non-ASCII characters
      removed, all non-word characters removed, all spaces converted to
      hyphens (`-`), and converted to lowercase. If the page has no
      title, the source file name is used.

  Tokens without a value (for instance `:category` on a page with no
  categories) are removed along with their slash.

  **Where the page is written.** Pages that have `categories`, or their
  own `urlpattern` in their front matter, are written to the path their
  URL describes. A URL that ends in `/` is written as `index.html` (or
  `index` plus the page's `extension`) inside that directory. For
  example, `_source/posts/0001.md` with:

      ---
      title: Foo Bar Baz
      date: 2015-08-01T10:00:00
      urlpattern: /:year/:month/:slug.html
      ---

  is written to `_output/2015/08/foo-bar-baz.html`, and `page.url` is
  `/2015/08/foo-bar-baz.html`. All other pages keep the path of their
  source file (`_source/about/index.md` becomes `_output/about/index.html`
  with a `page.url` of `/about/`).

* `categories: blog` puts the page in `site.categories.blog`. A list
  (`categories: [news, blog]`) puts it in each; the first is used for
  `:category`.

* `date: 2014-05-02T10:30:00` sets the page's date. ISO 8601 date-times
  (optionally with a time zone, e.g. `2014-05-02T10:30:00-05:00`), the
  older `2014-05-02 10:30:00` format and plain dates (`2014-05-02`) are
  accepted. Without a `date`, the file's modification time is used.

* `layout: post` selects `_layout/post.html`. Without a `layout`,
  `_layout/index.html` is used.

* `template: true` runs the page's content as template code; see
  [Template code in content](#template-code-in-content).

* `tags: [perl, writing]` puts the page in `site.tags.perl` and
  `site.tags.writing`.

* `description`, `image` and `author` are used by `page.seo`, the feed
  and `llms.txt`. Without a `description`, the excerpt is used.

* `updated: 2014-06-01` is when the page last changed, for the sitemap,
  the feed and `page.seo`.

* `paginate` lists posts across several pages; see
  [Pagination](#pagination).

* `markdown_twin: false`, `llms: false` and `sitemap: false` leave the
  page out of the Markdown copies, `llms.txt` and the sitemap.

Here is an example that shows a few different types of YAML definitions
at the beginning of a source file and how to use those definitions in
templates.

```
---
name: My Site
menu:
    Home: /
    Portfolio: /portfolio/
    About: /about/
    Github: http://github.com/markdbenson
fruits:
    - Apple
    - Orange
    - Banana
---

<h2>Name</h2>
[% page.name %]<br />

<h2>Menu</h2>
<ul>
[% for link in page.menu %]
    <li><a href="[% link.value %]">[% link.key %]</a></li>
[% end %]
</ul>

<h2>Fruits</h2>
<ul>
[% for fruit in page.fruits %]
    <li>[% fruit %]</li>
[% end %]
</ul>
```

Front matter values are always available to layouts as `page.*`. To use
template directives in a page's own content, as in the example above, the
page needs `template: true` (see [Template code in
content](#template-code-in-content)). Only do that for content you trust,
especially with `EVAL_PERL` enabled (see [Perl code](#perl-code)). More information is available in [Appendix C:
Internals](#appendix-c-internals).

Dapper depends on
[MultiMarkdown](http://fletcherpenney.net/multimarkdown/). Or, more
specifically, the Perl module implementation of MultiMarkdown ([Text::
MultiMarkdown](https://metacpan.org/pod/Text::MultiMarkdown).

MultiMarkdown is based on the traditional definition of Markdown by
John Gruber of [Daring Fireball](http://daringfireball.net), but adds
additional nice features such as tables and footnotes.

The following sections describe the markup that Dapper accepts, including
headings, text, lists, footnotes, tables, and images. There are more
features of the MultiMarkdown engine that Dapper uses. See the
[MultiMarkdown documentation](http://fletcher.github.io/MultiMarkdown-4/)
on CPAN for details.

## Template code in content

Layouts are always processed as templates. A page's own content is not:
`[% ... %]` in a page is shown as it is, so you can write about template
code, or publish text from anywhere, without it running.

A page whose content should be processed as a template (a list of posts,
say) opts in with `template: true`:

    ---
    title: Home
    template: true
    ---
    [% FOR post IN site.categories.blog.reverse %]
    <a href="[% post.url %]">[% post.title | html %]</a>
    [% END %]

`templates_in_content: true` in `_config.yml` makes every page's content,
and every value in `_config.yml`, a template, as they were before Dapper
1.0. Use it for sites written for older versions; see [Upgrading to
1.0](#upgrading-to-10).

## Front matter schemas

A `_schema.yml` file in a source directory describes the front matter that
the pages in that directory (and in the directories below it, unless they
have a schema of their own) must have. For example,
`_source/blog/_schema.yml`:

    required: [title, date, categories]
    fields:
      title:
        type: string
        max_length: 100
      date:
        type: date
      categories:
        type: list
        values: [blog, notes]
      tags:
        type: list
      draft:
        type: boolean
      rating:
        type: integer
        min: 1
        max: 5

`required` lists the fields every page must set. Each entry in `fields`
can have:

Rule                       | Meaning
---------------------------|---------------------------------------------------
`type`                     | `string`, `number`, `integer`, `boolean`, `date`, `list`, `map` or `any`
`values`                   | The allowed values (for a `list`, the allowed items)
`pattern`                  | A regular expression a string must match
`min_length`, `max_length` | Limits on the length of a string
`min`, `max`               | Limits on a number

Fields not listed in `fields` are allowed, unless the schema says
`additional: false`.

A build stops if any page doesn't match, listing every problem on every
page at once:

    error: 2 problems with front matter (see the _schema.yml files):
      _source/blog/new.md: "date" is required
      _source/blog/new.md: "categories" has "news", which is not one of: blog, notes

`dapper check` reports the same problems, and the [MCP
server](#ai-assistants-mcp) refuses to write a page that doesn't match.

## Data files

YAML (`.yml`, `.yaml`) and JSON (`.json`) files in the `_data` directory are
available in templates as `site.data`, named after the file:
`_data/authors.yml` is `site.data.authors`, and `_data/menus/main.yml` is
`site.data.menus.main`. For example, with `_data/menu.yml`:

    - label: Home
      url: /
    - label: About
      url: /about.html

a layout can build the menu:

    [% FOR item IN site.data.menu %]
    <a href="[% item.url %]">[% item.label | html %]</a>
    [% END %]

The data directory is never copied to the output. Set `data_dir` in
`_config.yml` to use another directory.

## Source file types

What happens to a file in the source directory depends on whether it starts
with front matter and on its extension:

* **`.md` files with front matter** are pages. The body is converted from
  Markdown to HTML, then combined with the layout.
* **Other files with front matter** (`.html`, `.xml`, `.txt`, ...) are
  pages too, but the body is used as it is, without Markdown. Use these for
  pages that are mostly HTML or template directives, such as a list of
  posts, or for non-HTML output such as a feed. Set `extension` in the
  front matter (e.g. `extension: .xml`) to choose the output file name's
  extension; otherwise it is `.html`.
* **Files without front matter** are copied to the same place in the output
  directory, untouched.

A page that uses template directives in its content needs `template: true`
(see [Template code in content](#template-code-in-content)). Markdown runs
before the directives are processed, so directives in a `.md` file are fine
inline, but a block of HTML and directives (a loop that builds a list of
links, say) is best kept in an `.html` source file, where Markdown can't
rewrap it in `<p>` tags.

Every file and directory in the source directory is processed except those
whose names start with a period. Directories starting with an underscore
are *not* skipped inside the source directory.

## Assets

Stylesheets, scripts, images and other files can live in either of two
places:

* **In the project directory**, next to `_source` (e.g. `css/`, `js/`,
  `images/`). Every top-level file and directory is copied to the output as
  it is, except those matching the `ignore` patterns in `_config.yml` (by
  default: names starting with `.` or `_`). Add patterns for anything you
  don't want published, like `README.md`, `Makefile` or a `design`
  directory.
* **In the source directory**, alongside the pages. Files there without
  front matter are copied as they are, which keeps an article's images next
  to its text.

Link to assets with absolute paths (`/css/site.css`) so the links work from
pages at any depth.

## Drafts and clean builds

Dapper has no draft setting: every page in the source directory is
published. Keep work in progress outside the source directory (for
instance in a top-level `_drafts` directory, which the default `ignore`
patterns keep out of the output) and move it into `_source` when it's
ready.

When you rename or remove a source file, the next build removes the file it
used to produce. Dapper keeps a list of the files it writes (in
`.dapper/manifest.json` in the project directory) and only ever removes
files on that list, so anything you put in the output directory yourself,
such as a `.git` directory or a `CNAME` file, is left alone. Add `.dapper/`
to your `.gitignore`. Set `clean: false` in `_config.yml` to turn this off.

## Headings

Headings are specified by prefixing with pound signs (`#`):

```
# Heading 1
## Heading 2
### Heading 3
#### Heading 4
##### Heading 5
###### Heading 6
```

Alternatively, headings may be specified using an underline style:

```
Alternative H1
==============

Alternative H2
--------------
```

## Text

Text elements may be formatted as well. Here are some examples of bold,
italics, code, links, and blockquotes:

Markdown                                | Result
----------------------------------------|----------------------------------
This is a normal paragraph.             | This is a normal paragraph.
This text is `**bold**.`                | This text is **bold**.
This text is also `__bold__.`           | This text is also **bold**.
This text is `*italicized*.`            | This text is *italicized*.
This text is also `_italicized_.`       | This text is also _italicized_.
`` `This is some code.` ``              | `This is some code.`
Link to `[Example](https://example.com).` | Link to [Example](https://example.com/).
Link to `[Example][ln1].`               | Link to [Example][ln1].
Link to `<https://example.com>.`        | Link to https://example.com.
`> This is the first level of quoting.` | The first level of quoting.
`>> This is a nested blockquote.`       | A nested blockquote.

`[ln1]: https://example.com "Example"`
[ln1]: https://example.com "Example"

Code is placed in `backticks` (see [above](#text)), or as a "fenced code block" 
by surrounding an entire block of text with three backticks in a row.
Put the language after the opening backticks, and the block is marked with
a `language-*` class (here, `<pre><code class="language-perl">`), which
client-side highlighters such as [highlight.js](https://highlightjs.org/)
and [Prism](https://prismjs.com/) use to color it. The blog template
(`dapper init --template blog`) sets up highlight.js.

```perl
#!/usr/bin/perl -w
print "Hello, world!\n";
```

## Lists

Lists may be specified by prefixing lines with an asterisk (`*`), minus
(`-`), or plus (`+`). Hierarchical representations are accomplished
via indentation.

```
* Milk
* Bread
* Cheese
    - Cheddar
        + Mild
        + Medium
        + Sharp
    - Limburger
* Rice

```

Numbered lists are prefixed by numbers. The order of the numbers doesn't
matter -- just that they are numbers. Example:

```
1. One
2. Two
3. Three
    1. Three.One
    2. Three.Two
4. Four
```

A definition list is a line followed by a line that starts with a colon
and a list of definitions. Examples:

```
Apple
:   * Pomaceous fruit of plants of the genus Malus in the family Rosaceae.
    * Also the makers of really great products.

Banana
:   1. A delicious fruit that can be hazardous if left on the ground.
    2. A fruit that comes with it's own packaging

Orange
:   - The fruit of an evergreen tree of the genus Citrus.
```

## Tables

Here is an example table that has a header row and a reference. The first
column is left-justified, the middle column is centered, and the third
column is right justified:

```
| First Header | Second Header |         Third Header |
| :----------- | :-----------: | -------------------: |
| First row    |      Data     | Very long data entry |
| Second row   |    **Cell**   |               *Cell* |
[simple_table]
```

More information is available in the [MultiMarkdown
documentation](http://fletcher.github.io/MultiMarkdown-4/tables).

## Images

Images can be specified in HTML by simply including the HTML in the
text. Alternatively, here are some short-hand notations:

* Image: `![Image description.](img.png)`
* Image with title attribute: `![Image description.](img.png "This is a title")`
* Image with ID: `![Image description.][img_id]`

`[img_id]: img.png "This is a title" height=50px width=200px`

## Footnotes

Footnotes can be accomplished as follows:

```
Here is some text containing a footnote[^somesamplefootnote]. You can then 
continue your thought...

[^somesamplefootnote]: Here is the text of the footnote itself.

This is an example of an inline footnote.[^This is the *actual* footnote.]
```

# Layout

Layout templates in Dapper are based on a superset of the [Template
Toolkit](http://template-toolkit.org/) v3 (TT3) mini language as implemented by
[Template::Alloy](https://metacpan.org/pod/Template::Alloy). 
Although both Dapper and Template::Alloy are both written in Perl, you do 
not need to know Perl in order to use them.

Layout templates include a series of directives. Directives can be
used to print the contents of a variable, or perform more sophisticated
computation such as if/then/else, foreach, or case statements. Directives
are surrounded by matched pairs of hard brackets and percent signs. Here is
an example of printing a variable called `site.name`:

```
[% site.name %]
```

When printing variables, you may also use filters to transform the variable
or print information about it. For instance, you can convert a variable 
name to all uppercase letters using the `upper` filter. Example:

```
[% site.name | upper %]
```

Another class of "logic" directives are used in a similar fashion.
Here is an example of a for statement that loops through each `page` in 
`site.pages`. For each iteration of the loop, print the contents of `page.title`:

```
[% for page in site.pages %]
  [% page.title %]
[% end %]
```

The following sections show how to use directives in more depth.

## Variables

This section describes how to use variables, literals, and expressions in Dapper.

Variables are bits of text or numbers that are defined in the project
configuration file or in the source files that can be used in templates. Here is
an example of printing the contents of `page.title`:

```
[% page.title %]
```

In Dapper, there are two top-level variables (think of them as namespaces),
which are `site` and `page`. Everything defined in `_config.yml` is
available in layouts as `[% site.* %]`, and everything defined in the front
matter of a source file is available as `[% page.* %]`. Dapper adds the
following variables of its own.

**Site variables**

Variable           | Description
-------------------|-----------------------------------------------------------
`site.pages`       | A list of every page, in source path order. Each item has all of the `page.*` variables below.
`site.categories`  | A hash of category name to a list of its pages, oldest first, e.g. `[% FOR post IN site.categories.blog.reverse %]`.
`site.tags`        | A hash of tag to a list of its pages, oldest first.
`site.data`        | The contents of the [data files](#data-files).
`site.category_pages`, `site.tag_pages` | The URL of each generated [category or tag page](#category-and-tag-pages), e.g. `[% site.tag_pages.item('perl') %]`.
`site.time`        | The time the build started (a date; see [Dates](#dates)).
`site.source`      | The source directory being used.
`site.output`      | The output directory being used.
`site.layout`      | The layout directory being used.
`site.urlpattern`  | The default URL pattern (`/:category/:year/:month/:slug/`).
`site.extension`   | The default output extension (`.html`).
`site.ignore`      | The list of patterns for top-level files that are not copied to the output.

**Page variables**

Variable                      | Description
------------------------------|------------------------------------------------
`page.content`                | The body of the page, rendered from Markdown for `.md` files.
`page.excerpt`                | The first paragraph of a Markdown page (`<p>...</p>`).
`page.title`, `page.layout`, ...| Anything in the page's front matter.
`page.url`                    | The page's URL relative to the site root, e.g. `/blog/2015/08/my-post/`.
`page.slug`                   | The title, slugified (or the file name if there is no title).
`page.id`                     | A number unique to the page within a build, in source path order.
`page.date`                   | The page's date: its `date` setting, or the file's modification time.
`page.timezone`               | The time zone of `page.date` (from the page, the site, or your computer).
`page.year`, `page.month`, `page.day`, `page.hour`, `page.minute`, `page.second` | Parts of `page.date`, zero padded (e.g. `08`).
`page.categories`             | The page's categories, as written in its front matter.
`page.extension`              | The output extension for the page.
`page.filename`               | The output file the page is written to.
`page.dirname`                | The directory of `page.filename`.
`page.source`                 | The source file the page came from.
`page.source_file_extension`  | The source file's extension, e.g. `.md`.
`page.seo`                    | Tags for the page's `<head>`: description, canonical link, feed and Markdown links, Open Graph and Twitter tags, and JSON-LD structured data. See [SEO tags](#seo-tags).
`page.markdown_url`           | The URL of the page's [Markdown copy](#markdown-copies-and-llmstxt), if it has one.
`page.posts`                  | On a generated category or tag page: its pages, newest first.
`paginator`                   | On a paginated page: see [Pagination](#pagination).

### Dates

`page.date` and `site.time` are [DateTime](https://metacpan.org/pod/DateTime)
objects, so you can call DateTime methods on them, and they print as
`2014-05-02T10:30:00`. A date written without a time zone (`2014-05-02T10:30:00`)
is taken to be in the page's `timezone`, the site's `timezone`, or your
computer's time zone, in that order. They also have an `xmlschema` method that includes
the time zone, which is what Atom feeds need:

```
<updated>[% page.date.xmlschema %]</updated>
<p>Posted [% page.date.strftime('%B %e, %Y') %]</p>
```

Note that Dapper's filters (the ones marked [DSF] below) only apply to
text; given a date object they print nothing. So use
`[% page.date.xmlschema %]` rather than `[% page.date | date_to_xmlschema %]`.

Example `_config.yml`:

```
name: Mark Benson Portfolio
```

Example `_source/index.md`:

```
---
title: The title of my post
---

The body of my post.
```

Example `_layout/index.html`:

```
<html>
<head>
    <title>[% page.title %] - [% site.name %]</title>
</head>
<body>
    <h1>[% page.title %]</h1>
    <p>[% page.content %]</p>
</body>
</html>
```

This would produce the following:

```
<html>
<head>
    <title>The title of my post - Mark Benson Portfolio</title>
</head>
<body>
    <h1>The title of my post</h1>
    <p>The body of my post.</p>
</body>
</html>
```

Variables can also be defined within a template file. For example:

```
[% a = 42 %][% a %]
[% b = "Hello" %][% b %]
```

Result:

```
42
Hello
```

It's also possible to create arrays:

```
[% a = [1, 2, 3, 4, 5] %]
[% a.1 %]
[% a | length %]
```

Result:

```
2
5
```

And associative arrays (hashes):

```
[% link = {name => 'My Portfolio', 'url' => 'https://example.com/'} %]
<a href="[% link.url %]">[% link.name %]</a>
```

Result:

```
<a href="https://example.com/">My Portfolio</a>
```

*Literals*

The following are the types of literals (numbers and strings) allowed in
layouts:

```
[% 23423 %]          Prints an integer
[% 3.14159 %]        Prints a number
[% pi = 3.14159 %]   Sets the value of the variable
[% 3.13159.length %] Prints 7 (the string length of the number)
```

*Expressions*

Expressions are one or more variables or literals joined together with
operators. An expression can be used anywhere a variable can be used with
the exception of the left-hand side of a variable assignment directive
or a filename for one of the `process`, `include`, `wrapper`, or `insert`
directives.

Examples:

```
[% 1 + 2 %]       Prints 3
[% 1 + 2 * 3 %]   Prints 7
[% (1 + 2) * 3 %] Prints 9

[% x = 2 %]       Assignments don't return anything
[% (x = 2) %]     Unless they are in parens. Prints 2
[% y = 3 %]
[% x * (y - 1) %] Prints 4
```

For a full listing of operators, see
[Template::Alloy::Operator](https://metacpan.org/pod/Template::Alloy::Operator).

## Pagination

A page can list posts across several pages with `paginate` in its front
matter:

    ---
    title: Blog
    template: true
    paginate:
      category: blog      # or tag: perl; leave both out for every post
      per_page: 10
    ---

`paginate: 10` is short for every post, ten to a page. Page 1 keeps the
page's own URL; page 2 is written to `page/2/` below it (so `/blog/` is
followed by `/blog/page/2/`), and so on. The page (its layout, or its
content with `template: true`) gets a `paginator`:

Variable                   | Description
---------------------------|-----------------------------------------------
`paginator.items`          | The posts for this page, newest first
`paginator.page`           | This page's number, starting at 1
`paginator.total_pages`    | How many pages there are
`paginator.total_items`    | How many posts there are in all
`paginator.per_page`       | Posts per page
`paginator.previous_url`   | The URL of the previous page, if there is one
`paginator.next_url`       | The URL of the next page, if there is one
`paginator.first_url`, `paginator.last_url` | The first and last pages
`paginator.pages`          | Every page, as `number` and `url`

For example:

    [% FOR post IN paginator.items %]
    <h2><a href="[% post.url %]">[% post.title | html %]</a></h2>
    [% END %]
    [% IF paginator.previous_url %]<a href="[% paginator.previous_url %]">Newer</a>[% END %]
    [% IF paginator.next_url %]<a href="[% paginator.next_url %]">Older</a>[% END %]

## Category and tag pages

Dapper can generate a page for every category and every tag. Turn them on
in `_config.yml` and name the layout to use:

    category_pages:
      layout: list             # _layout/list.html
      urlpattern: /:category/  # the default
    tag_pages:
      layout: list
      urlpattern: /tags/:tag/  # the default
      per_page: 20             # optional: paginate each one

Each generated page has `page.title` (the category or tag), `page.category`
or `page.tag`, and `page.posts` (its posts, newest first). With `per_page`,
`page.posts` holds that page's share and there is a `paginator` too. A
simple `_layout/list.html`:

    ---
    layout: index
    ---
    <h1>[% page.title | html %]</h1>
    [% FOR post IN page.posts %]
    <p><a href="[% post.url %]">[% post.title | html %]</a></p>
    [% END %]

To link to them, `site.category_pages` and `site.tag_pages` hold their
URLs: `<a href="[% site.tag_pages.item(tag) %]">[% tag %]</a>`.

## Comments

Comments in Dapper are specified using the `comment` directive. Example:

    [% comment %]
       This text is commented out and won't be shown.
    [% end %]

## Filters

Variables can use filters. Filters are simple methods that take a string
as an input, along with zero or more optional parameters, and returns a
string as a result. Filters can be chained together. Examples:

```
[% site.name = " Mark Benson Portfolio    " %]
[% site.name | upper | trim %]
[% page.title = "My very long page title that should be truncated" %]
[% page.title | truncate(26) %]
```

Results:

```
MARK BENSON PORTFOLIO
My very long page title...
```

Here is a list of filters that are provided by default. Most are provided by
Template::Alloy. Others that are provided by Dapper are marked as [DSF].

*Text*

The following methods can be called on text/string variables.

Filter               | Description
---------------------|-----------------------------------------------------------------------
`abs`                | Returns the absolute value
`atan2(x)`           | Returns the arctangent. The item itself represents Y, the passed argument represents X.
`chunk(n)`           | Split string up into a list of chunks of text n chars wide.
`collapse`           | Strip leading and trailing whitespace and collapse all other space to one space.
`cos`                | Returns the cosine of the item.
`date_to_xmlschema`  | [DSF] Convert a date string to an XML Schema date that also includes the timezone. For `page.date` and `site.time` use `.xmlschema` instead (see [Dates](#dates))
`defined`            | Always true - because the undef sub translates all undefs to ''.
`eval`               | Process the string as though it was a template.
`evaltt`             | Same as the eval filter.
`exp`                | Returns "e" to the power of the item.
`fmt`                | Similar to format. Returns a string formatted with the passed pattern. Default pattern is %s. Opposite from of the sprintf vmethod.
`format`             | Print the string out in the specified format. It is similar to the "fmt" virtual method, except that the item is split on newline and each line is processed separately.
`hash`               | Returns a one item hash with a key of "value" and a value of the item.
`hex`                | Returns the decimal value of the passed hex numbers.
`html`               | Performs a very basic html encoding (swaps out `&`, `<`, `>` and `"` with the corresponding html entities).
`indent(n)`          | Indent by `n` spaces if an integer is passed (default is 4), or string if string is passed.
`int`                | Return the integer portion of the value (0 if none).
`json(1)`            | Returns a JSON encoded representation. Returns a pretty JSON encoded representation if `1` is passed.
`lc`                 | Same as the lower vmethod. Returns the lowercased version of the item.
`lcfirst`            | Lowercase the leading letter.
`length`             | Return the length of the string.
`list`               | Returns a list (arrayref) with a single value of the item.
`log`                | Returns the natural log base "e" of the item.
`lower`              | Return the string lowercased.
`match(p, 1)`        | Return a list of items matching the regular expression pattern `p`. If the second argument is `1`, match globally.
`none`               | Returns the item without modification.
`null`               | Return nothing.
`oct`                | Returns the decimal value of the octal string.
`rand`               | Returns a number greater or equal to 0 but less than the value of the item.
`remove(p)`          | Same as replace, but is global and replaces the regular expression `p` with nothing.
`repeat(n, s)`       | Repeat the item `n` times, separated with `s`. `s` is optional.
`replace(p, q)`      | Globally replace all `p` with `q`. `p` and `q` may be strings or regular expressions. An optional third argument of `0` may be passed to turn off global replacement.
`replace_last(a, b)` | [DSF] Replace the last occurrence of the string `a` with `b`
`return`             | Returns the item from the inner most block, macro, or file. Similar to the `return` directive.
`search(s)`          | Tests if the given pattern is in the string.
`sin`                | Returns the sine of the item.
`size`               | Always returns 1 for text variables.
`smart`              | [DSF] Replace `---` with an em dash and `--` with an en dash
`split(s, n)`        | Splits the item on regular expression `s` and returns an array with the chunks. If `n` is passed, processing stops after the first `n` chunks.
`sprintf(p, q, ...)` | Uses the pattern stored in self, and passes it to sprintf with the passed arguments. Opposite from the fmt vmethod.
`sqrt`               | Returns the square root of the number.
`srand`              | Calls the perl srand function to set the internal random seed. This will affect future calls to the rand vmethod.
`stderr`             | Print the item to the current STDERR handle.
`substr(i, n)`       | Returns a substring of item starting at `i` and going to the end of the string. If `n` is passed, the substring stops after `n` characters.
`trim`               | Strips leading and trailing whitespace.
`uc`                 | Same as the upper command. Returns uppercased string.
`ucfirst`            | Uppercase the leading letter.
`upper`              | Return the string uppercased.
`uri`                | Perform a very basic URI encoding.
`url`                | Perform a URI encoding - but some characters such as `:` and `/` are left intact.
`xml_escape`         | [DSF] Escape strings that may contain XML so the string can be included in XML files such as ATOM or RSS feeds
`xml`                | Performs a very basic xml encoding (swaps out `&`, `<`, `>`, `'` and `"` with the corresponding xml entities).

*List*

The following methods can be called on arrays (text/strings are automatically
converted to an array containing a single element containing the value of the
text/string).

Filter               | Description
---------------------|-----------------------------------------------------------------------
`fmt(s,t,u)`         | Returns a string of the values of the list formatted with the passed pattern and joined with the passed string. Default pattern is %s and the default join string is space.
`first(n)`           | Returns a list of the first `n` items in the list.
`grep(s)`            | Returns a list of all items matching the regex pattern.
`hash`               | Returns a hash with the array indexes as keys and the values as values.
`join(s)`            | Joins on `s`. `s` defaults to space.
`json(1)`            | Returns a JSON encoded representation. If `1` is passed, returns a JSON-encoded pretty representation.
`last(n)`            | Returns a list of the last `n` items in the list.
`list`               | Returns a reference to the list.
`map`                | `[% mylist.map(->{ this.upper }) %]` Returns a list with the macro played on each item.
`max`                | Returns the last item in the array.
`merge(a)`           | Returns a new list with all defined items from list `a` added.
`nsort(key)`         | Returns the numerically sorted items of the list.  If the items are hashes, a key containing the field to sort on can be passed.
`pop`                | Removes and returns the last element from the arrayref (the stash is modified).
`push(e)`            | Adds an element to the end of the arrayref (the stash is modified).
`pick(n)`            | Returns `n` random items from the list. `n` defaults to `1`.
`return`             | Returns the list from the inner most block, macro, or file. Similar to the RETURN directive.
`reverse`            | Returns the list in reverse order.
`shift`              | Removes and returns the first element of the arrayref (the stash is modified).
`size`               | Returns the number of elements in the array.
`slice(i,n)`         | Returns a list from the arrayref beginning at index `i` and continuing for `n` items.
`sort`               | Returns the alphabetically sorted items of the list. If the items are hashrefs, a key containing the field to sort on can be passed.
`splice(i,n)`        | Removes items from array beginning at `i` and continuing for `n` items.
`unique`             | Return a list of the unique items in the array.
`unshift(n)`         | Adds an item to the beginning of the arrayref.

*Hash*

The following methods can be called on hash type data structures. Additionally,
list virtual methods can be accessed via the Hash Virtual Object.

Filter               | Description
---------------------|-----------------------------------------------------------------------
`fmt`                | `[% myhash.fmt('%s => %s', "\n") %]` Passed a pattern and an string to join on. Returns a string of the key/value pairs of the hash formatted with the passed pattern and joined with the passed string. Default pattern is "%s\t%s" and the default join string is a newline.
`defined(a)`         | Checks if `a` is defined in the hash.
`delete(a)`          | Deletes the item `a` from the hash.
`each`               | Turns the contents of the hash into a list - subject to change.
`exists(a)`          | Checks if `a` is in the hash.
`hash`               | Returns a reference to the hash.
`import(h)`          | Overlays the keys of hash `h` over the keys of the hash item.
`item(k)`            | Returns the hash value for key `k`.
`items`              | Returns a list of the key and values (flattened hash).
`json(1)`            | Returns a JSON encoded representation. If `1` is passed, returns a pretty JSON-encoded representation.
`keys`               | Returns an arrayref of the keys of the hash.
`list`               | Returns an arrayref with the hash as a single value (subject to change).
`pairs`              | Returns an arrayref of hashrefs where each hash contains {key => $key, value => $value} for each value of the hash.
`nsort`              | Returns a list of keys numerically sorted by the values.
`return`             | Returns the hash from the inner most block, macro, or file. Similar to the RETURN directive.
`size`               | Returns the number of key/value pairs in the hash.
`sort`               | Returns a list of keys alphabetically sorted by the values.
`values`             | Returns an arrayref of the values of the hash.

## Conditionals

Conditional statements are possible in Dapper. A variety of options exist,
including `if/else`, `unless`, and `switch/case`, which are defined next.

### If/Else

`If` statements are used for controlling the flow of execution through a layout 
template. `If` statements take an expression. If true, the proceeding block 
is executed. If not, an `elsif` block is executed (if it exists). Finally,
an `else` block (if it exists) is executed if neither the `if` or the `elsif`
block is true. Example:

    [% page.category == "books" %]
        Category: Books
    [% end%]

Here is an if/else example:

    [% if page.category == "books" %]
        Category: Books
    [% elsif page.category == "movies" %]
        Category: Movies
    [% else %]
        Category: Unknown
    [% end %]

For brevity, `if` statements may also be used as post-operative directives.
Example:

    [% "Category: Books" if page.category == "books" %]

### Unless

Same as `if` statements, but the condition is reversed. The following block
is only evaluated if the expression is *not* true.

    [% unless page.category == "books" %]
        Category: (Not) Books
    [% end %]

`Unless` directives can also be used as post-operative directives. Example:

    [% "Category: (Not) Books" unless page.category == "books" %]

### Switch/Case

Switch statements are allowed in Dapper as well. Usage is best described with
an example:

    [% switch page.category %]
        [% case "books"  %] Category: Books
        [% case "movies" %] Category: Movies
        [% case default  %] Category: Unknown
    [% end %]

## Iteration

Iterative (looping) constructs are also available in Dapper. Options include
`for/foreach`, and `while`. Additionally, a `loop` variable is provided to
allow you to see information about the current loop. 

### For

`For` statements allow you to iterate over the contents of an array. If the 
variable is not already an array, it is automatically converted to an array
for you. `Foreach` is an alias for `for`. Example:

    [% for link in site.blogroll %]
        The link is [% link %]
    [% end %]

You can also use `=` in place of `in`:

    [% for link = site.blogroll %]
        The link is [% link %]
    [% end %]

The `for` statement also works on hashes:

    [% for [{a => 1}, {a => 2}] %]
        Key a = [% a %]
    [%~ END %]

Result:

        Key a = 1
        Key a = 2

During a `for` loop, a special variable called `loop` is available and provides
the following information:

Variable         | Definition
-----------------|-------------------------------------------------------------
`loop.index`     | The current index
`loop.max`       | The max index of the list
`loop.size`      | The number of items in the list
`loop.count`     | Index + 1
`loop.number`    | Index + 1
`loop.first`     | True if on the first item
`loop.last`      | True if on the last item
`loop.next`      | Return the next item in the list
`loop.prev`      | Return the previous item in the list
`loop.odd`       | Return 1 if the current count is odd, 0 otherwise
`loop.even`      | Return 1 if the current count is even, 0 otherwise
`loop.parity`    | Return "odd" if the current count is odd, "even" otherwise

Example:

    [% for [1 .. 3] %]
        [% loop.count %]/[% loop.size %]
    [% end %]

Result:

    1/3
    2/3
    3/3 

Additinoally, `break/last` and `next` directives may be used in loops. `Break` is 
an alias for `last` and exits the loop. `Next` skips the remainder of the current
loop and begins the next iteration in the loop. Example:

    [% for [1 .. 3] %]
        [% if loop.count == 2 %][% break %][% end %]
        [% loop.count %]/[% loop.size %]
    [% end %]

Result:

    1/3

Example:
 
    [% for [1 .. 3] %]
        [% if loop.count == 2 %][% next %][% end %]
        [% loop.count %]/[% loop.size %]
    [% end %]

Result:

    1/3
    3/3

### While 

The `while` directive will process a block of code while a condition continues
to be true. Example:

    [% i = 0 %]
    [% while i < 3 %]
        [% i = i + 1 %]
        i = [% i %]
    [% end %]

Result:

    i = 1
    i = 2
    i = 3

As with `for` statements, `break/last` and `next` statements are also available.

## Blocks

`Block` directives allow you to save a block of text under a name for later use 
in an `include` directive. Blocks may be placed anywhere within the template 
being processed. Example:

    [% block foo %]Some text[% end %]
    [% include foo %]

Anonymous `block` definitions can be used for capturing chunks of text:

    [% a = block %]Some text[% end %]
    [% a %]

## Perl code

You can execute perl code inside templates as of v0.19. In order to enable it,
make sure that `EVAL_PERL` is defined in your environment. For instance:

    $ export EVAL_PERL=true

Then, you can use `perl` or `rawperl` to include perl code in your templates.
For instance:

    [% a = "Apple" %]
    [%~ PERL %]
        my $a = "[% a %]";
        print "The variable \$a is \"$a\"";
        $stash->set('b', "Banana");
    [% END %]
    [% b %]

This would print the following:

    The variable $a is "Apple"
    Banana

During execution, anything printed to STDOUT will be inserted into the
template. Also, the $stash and $context variables are set and are references
to objects that mimic the interface provided by Template::Context and
Template::Stash. These are provided for compatibility only. $self contains
the current Template::Alloy object.

The `rawperl` block can be used as well. It operates the same as the `perl`
block does except that you will need to append to the $output variable rather
than just calling `print`.

## Includes

An `include` directive parses the contents of a file or `block` and inserts them
into the template. File names are relative to the layout directory
(`_layout`), so shared pieces such as a header or footer can live there
next to the layouts (e.g. `_layout/include-footer.html`, included with
`[% include "include-footer.html" %]`). Every file in the layout directory
can also be used as a layout, so give partials a name that makes their
purpose clear. Variables that are defined or modified within the included
bits are discarded after the include occurs. Example:

    [% include "path/to/template.html" %]

    [% file = "path/to/template.html" %]
    [% include $file %]

    [% block foo %]This is foo[% end %]
    [% include foo %]

Arguments may also be passed to the template:

    [% include "path/to/template.html" a = "An arg" b = "Another arg" %]

Multiple filenames can be passed by separating them with a plus, a space, or 
commas. Any supplied arguments will be used on all templates. Example:

    [% include "path/to/template1.html",
               "path/to/template2.html" a = "An arg" b = "Another arg" %]

If it's important that the included file *not* be parsed for directives, an
alternative directive may be used called `insert`. `Insert` directives act in
exactly the same way that `include` directives do, but does not process any 
directives that the inserted file might contain. Example:

    [% insert "path/to/template1.html",
              "path/to/template2.html" %]

## Macros

The `macro` directive can be thought of as a way to define a miniature function
that can be used elsewhere in the template. Example:

    [% macro foo(i, j) block %]You passed me [% i %] and [% j %].[% end %]
    [% foo(1, 2) %]

Result:

    You passed me 1 and 2.

Another example:

    [% macro bar(max) foreach i = [1 .. max] %]([% i %])[% end %]
    [% bar(4) %]

Result:

    (1)(2)(3)(4)

## Plugins

Layout plugins provide a way to get access to special functionality that are 
more complicated than what [filters](#filters) provide. This section defines some 
of the plugins that are distributed with Dapper. For a comprehensive list, see 
[Template::Toolkit plugin](http://template-toolkit.org/docs/manual/Plugins.html).

### Datafile

This plugin provides a simple facility to construct a list of hash references, 
each of which represents a data record of known structure from a specified data 
file. A filename must be specified. An optional delim parameter may also be 
provided to specify an alternate delimiter character.

The format of the file is intentionally simple. The first line defines the field 
names, delimited by colons with optional surrounding whitespace. Subsequent lines 
then defines records containing data items, also delimited by colons. For example:

    id : name
    mdb: Mark Benson
    lkb: Loomis Buschwa

Each line is read, split into composite fields, and then used to initialize a 
hash array containing the field names as relevant keys. The plugin returns a 
blessed list reference containing the hash references in the order as defined in 
the file. Example:

    [% use userlist = datafile('users.txt', delim = ':') %]
    [% for user in userlist %]
        [% user.id %] -> [% user.name %]
    [% end %]

Result:

    mdb -> Mark Benson
    lkb -> Loomis Buschwa

The first line of the file must contain the field definitions. After the first 
line, blank lines will be ignored, along with comment line which start with a '#'.

### Date

The Date plugin provides an easy way to generate formatted time and date strings 
by delegating to the POSIX strftime() routine.

The plugin can be loaded via the `use` directive.

    [% use date %]

This creates a plugin object with the default name of `date`. An alternate name 
can be specified like this:

    [% use myname = date %]

The plugin provides the format() method which accepts a time value, a format 
string and a locale name. All of these parameters are optional with the current 
system time, default format ('%H:%M:%S %d-%b-%Y') and current locale being used 
respectively, if undefined. Default values for the time, format and/or locale may 
be specified as named parameters in the use directive.

    [% use date(format = '%a %d-%b-%Y', locale = 'fr_FR') %]

When called without any parameters, the format() method returns a string 
representing the current system time, formatted by strftime() according to the 
default format and for the default locale (which may not be the current one, if 
locale is set in the use directive).

    [% date.format %]

The plugin allows a time/date to be specified as seconds since the epoch, as is 
returned by time().

    File last modified: [% date.format(filemod_time) %]

The time/date can also be specified as a string of the form `h:m:s d/m/y` or
`y/m/d h:m:s`. Any of the characters `:` `/` `-` or space may be used to delimit 
fields.

    [% use day = date(format => '%A', locale => 'en_GB') %]
    [% day.format('4:20:00 9-13-2000') %]

Output:

    Tuesday

A format string can also be passed to the format() method, and a locale 
specification may follow that.

    [% date.format(filemod, '%d-%b-%Y') %]
    [% date.format(filemod, '%d-%b-%Y', 'en_GB') %]

A fourth parameter allows you to force output in GMT, in the case of seconds-
since-the-epoch input:

    [% date.format(filemod, '%d-%b-%Y', 'en_GB', 1) %]

Note that in this case, if the local time is not GMT, then also specifying '%Z' 
(time zone) in the format parameter will lead to an extremely misleading result.

Any or all of these parameters may be named. Positional parameters should always 
be in the order ($time, $format, $locale).

    [% date.format(format => '%H:%M:%S') %]
    [% date.format(time => filemod, format => '%H:%M:%S') %]
    [% date.format(mytime, format => '%H:%M:%S') %]
    [% date.format(mytime, format => '%H:%M:%S', locale => 'fr_FR') %]
    [% date.format(mytime, format => '%H:%M:%S', gmt => 1) %]
    ...etc...

The now() method returns the current system time in seconds since the epoch.

    [% date.format(date.now, '%A') %]

The calc() method can be used to create an interface to the Date::Calc module (if 
installed on your system).

    [% calc = date.calc %]
    [% calc.Monday_of_Week(22, 2001).join('/') %]

The manip() method can be used to create an interface to the Date::Manip module 
(if installed on your system).

    [% manip = date.manip %]
    [% manip.UnixDate("Noon Yesterday","%Y %b %d %H:%M") %]

## Chomping

When using directives in templates, it can help to add whitespace around
the directives to make them more readable. However, adding this whitespace
can make the resulting output unreadable. To help with this, special uses of
the `+`, `-`, `=`, and `~` characters can be used to pre- and post-chomp
the whitespace as follows:

#### [%+ Chomp None +%]

Don't do any chomping.

```
Quick.

[%+ "Brown." +%]

Fox.
```

Result:

```
Quick.

Brown.

Fox.
```

#### [%- Chomp One -%]

Delete any whitespace up to the adjacent newline.

```
Quick.

[%- "Brown." -%]

Fox.
```

Result:

```
Quick.
Brown.
Fox.
```

#### [%= Chomp Collapse =%]

Collapse adjacent whitespace to a single space.

```
Quick.

[%= "Brown." =%]

Fox.
```

Result:

```
Quick. Brown. Fox.
```

#### [%~ Chomp Greedy ~%]

Remove all adjacent whitespace.

```
Quick.

[%~ "Brown." ~%]

Fox.
```

Result:

```
Quick.Brown.Fox.
```

## Dumping

The `dump` directive inserts a Data::Dumper printout of the variable or 
expression. If no argument is passed it will dump the entire contents of the 
current variable stash (with private keys removed). The output also includes the 
current file and line number that the DUMP directive was called from. Example:

    [% dump %]      # dump everything
    [% dump site %] # dump everything in the site
    [% dump page %] # dump everything in the current page

# Publishing for Search Engines and AI

Dapper writes the files that help search engines, feed readers and AI tools
find and understand your site. Most need `url` in `_config.yml`, so that
links can be absolute.

## Sitemap

With `url` set, every build writes `/sitemap.xml`, listing every HTML page
(except a `404.html`, and pages with `sitemap: false`), with the date each
was last changed (`updated`, or `date`). Turn it off with `sitemap: false`
in `_config.yml`.

## Feed

`feed` in `_config.yml` turns on an Atom feed:

    feed:
      category: blog    # leave out for every page with a category
      path: /feed.xml   # the default
      limit: 20         # the default
      title: My Blog    # the default is the site's name

`feed: true` is a feed of every page with a category, with the defaults.
Each entry has the post's title, link, dates, summary and full content. If
a page in the source directory already writes the same file, it is used
instead.

## SEO tags

Put `[% page.seo %]` in your layout's `<head>`:

    <head>
      <meta charset="utf-8">
      <title>[% page.title | html %]</title>
    [% page.seo %]
    </head>

and each page gets:

* a `description` (the page's `description`, or its excerpt)
* a `canonical` link to its own URL
* links to its Markdown copy and the site's feed
* Open Graph and Twitter tags, so links shared on social media show a
  title, description and image (`image` in the page or `_config.yml`)
* JSON-LD structured data: a `BlogPosting` for pages with a category
  (with dates, author and publisher), or a `WebPage`

## Markdown copies and llms.txt

AI tools read Markdown more easily than HTML. For each page made from a
Markdown file, Dapper writes a copy of it next to the HTML
(`/blog/2026/10/hello-world/index.md` beside `index.html`), with the title
as a heading. It also writes:

* `/llms.txt`: the site's name and description and a list of links to the
  Markdown copies, grouped by category, newest first (the
  [llms.txt](https://llmstxt.org/) convention)
* `/llms-full.txt`: every Markdown copy in one file

Pages whose Markdown is a template (`template: true` with directives in
it) get no copy, since it would show template code. Turn these off with
`markdown_twins: false` or `llms_txt: false` in `_config.yml`, or for one
page with `markdown_twin: false` or `llms: false`.

## Search

`search: true` in `_config.yml` builds a search index of the site with
[Pagefind](https://pagefind.app) after each build. Install Pagefind first
(for instance with `npm install -g pagefind`), or set `search_command`
(e.g. `search_command: npx -y pagefind`). If Pagefind isn't installed,
the build still finishes, with a warning.

Then add Pagefind's search box to a layout:

    <link rel="stylesheet" href="/pagefind/pagefind-ui.css">
    <div id="search"></div>
    <script src="/pagefind/pagefind-ui.js"></script>
    <script>new PagefindUI({ element: "#search" });</script>

# AI Assistants (MCP)

`dapper mcp` runs a [Model Context Protocol](https://modelcontextprotocol.io)
server, so that an AI assistant can read, write, check and build your site
through Dapper. Dapper's rules act as guardrails: pages are only ever
written inside the source directory, and a page that doesn't match its
[schema](#front-matter-schemas) is refused (with the reasons) rather than
written.

To add it to Claude Code:

    $ claude mcp add dapper -- dapper -C /path/to/site mcp

Other MCP clients take the command and its arguments in their settings:

    {
      "mcpServers": {
        "dapper": { "command": "dapper", "args": ["-C", "/path/to/site", "mcp"] }
      }
    }

The server offers these tools:

Tool          | What it does
--------------|-------------------------------------------------------------
`site_info`   | The site's settings, directories, categories, tags, layouts and schemas
`list_pages`  | Every page (or those in a `category` or with a `tag`), with source file, URL, title, date, categories and tags
`read_page`   | A page's front matter and body
`write_page`  | Create or replace a page from front matter and a body, after checking it against its schema
`build`       | Build the site
`check`       | Find problems without touching the output directory

Then ask, for example: "Write a post about our launch in the blog, check
the site, and build it."

# Deployment

To deploy your content, you have a number of options. This section outlines
a few of them.

## Amazon S3

It's possible to serve a static website using Amazon S3. Here's how.

1. In the AWS Console, create a bucket named after your domain (e.g.
   `mydomain.com`). Under 'Properties', enable 'Static website hosting' and
   set the 'Index document' to `index.html`.

2. New buckets block public access by default. To serve a website directly
   from the bucket, turn off 'Block public access' for it and add a bucket
   policy that allows `s3:GetObject` for everyone. Alternatively, keep the
   bucket private and put Amazon CloudFront in front of it, which also gives
   you HTTPS.

3. Optionally, create a second bucket named `www.mydomain.com` and set its
   static website hosting to 'Redirect requests' to `mydomain.com`.

4. Install and configure the [AWS CLI](https://aws.amazon.com/cli/) with
   your credentials:

       $ aws configure

5. Now any time you want to rebuild your content and push it to S3, it's a
   simple call to:

       $ dapper build
       $ aws s3 sync _output/ s3://mydomain.com --delete

    The `--delete` option removes files from the bucket that are no longer
    in `_output` (Dapper removes the output of source files you delete, so
    the two stay in step). If you upload files to the bucket independently
    of Dapper, leave `--delete` off.

If you use Amazon Route 53 for DNS, create an alias A record for
`mydomain.com` (and `www.mydomain.com`) that points at the bucket's website
endpoint, or at your CloudFront distribution.

To make it easy to publish to Amazon S3, one option is to create a Makefile
that encodes the publishing instructions. For example:

    S3_BUCKET=mydomain.com

    build:
    	dapper build

    clean:
    	rm -rf _output

    serve:
    	dapper serve

    publish: clean build
    	aws s3 sync _output/ s3://$(S3_BUCKET) --delete

    watch:
    	dapper watch

    .PHONY: build clean serve publish watch

## GitHub Pages

GitHub Pages is a free service that allows you to publish a static website for
free. By pushing your changes to a git repository, your website will be
automatically available on github.io. Here are the steps:

1. First, if you don’t have an account already, you should sign up for a [GitHub
   account](https://github.com/).

2. Next, create a new repository named `<username>.github.io` where you should 
   replace `<username>` with your actual Github username.

3. After that, push the contents of your `_output` directory to the new github
   repo. Steps:

       $ cd _output
       $ touch .nojekyll
       $ git init -b main
       $ git remote add origin https://github.com/<username>/<username>.github.io.git
       $ git add -A
       $ git commit -m "Initial revision"
       $ git push -u origin main

   The empty `.nojekyll` file tells GitHub Pages to publish the files as
   they are, rather than running them through Jekyll (which would skip
   files and directories that start with an underscore).
   Dapper never removes files it didn't write, so `.nojekyll` and `.git`
   survive later builds.

4. In the repository's Settings, under Pages, make sure the site is
   published from the `main` branch. Wait a few minutes, then find your new
   website at `https://<username>.github.io`.

# What Dapper Doesn't Do

Dapper is deliberately small. It does not have:

* **Drafts or scheduled posts.** See [Drafts and clean
  builds](#drafts-and-clean-builds).
* **Asset processing** (Sass, minification, image resizing, bundling). Run
  those tools separately and let Dapper copy their output.
* **Server-side code highlighting.** Code blocks are marked with their
  language for a client-side highlighter instead.
* **Incremental builds.** Every build processes the whole site, which is
  fast for sites of a few hundred pages.

# Upgrading to 1.0

Dapper 1.0 adds a lot, but changes one thing that can affect existing
sites:

* **Page content is no longer run as template code.** In 0.x, every page's
  content, and every value in `_config.yml`, was processed as a template
  (a second time, after the layout). Now only layouts are. If your pages
  use `[% ... %]` (to list posts, say), either add `template: true` to
  those pages, or add `templates_in_content: true` to `_config.yml` to get
  the old behavior back exactly. Template code in a `_config.yml` value
  (like a copyright line with the current year) also needs
  `templates_in_content: true`, or can move into a layout.

And builds now write more files than before:

* A Markdown copy next to each page made from Markdown, `/llms.txt`,
  `/llms-full.txt`, and (with `url` set) `/sitemap.xml`. Turn them off
  with `markdown_twins: false`, `llms_txt: false` and `sitemap: false`.
* Files left over from earlier builds are now removed (only files Dapper
  wrote; see [Drafts and clean builds](#drafts-and-clean-builds)). The
  list starts with your first 1.0 build, so delete the output directory
  once for a fully clean start. Add `.dapper/` to your `.gitignore`.

Run `dapper check` after upgrading; it finds broken links and other
problems without touching the output directory.

# Upgrading from 0.21

Version 0.22 fixes a number of long-standing bugs. Most sites build exactly
as before, but check these:

* **Directories in `_config.yml` are now used.** If your project file sets
  `source`, `output` or `layout`, Dapper now uses them for every command
  (before, they were mostly ignored). Command-line options still win.
* **Pages with their own `urlpattern` are written to their URL's path**,
  not to a path based on the source file name.
* **`page.id` follows sorted file order**, so the numbers may differ from
  0.21. If a feed uses `page.id` in entry IDs, readers may show those
  entries again once; `page.url` makes a more stable ID.
* **Front matter must begin on the first line** and end with a line
  containing only `---`. Files that don't start with front matter are now
  copied as they are, instead of stopping the build.
* **Dates without a time zone** are now in your site's `timezone` (or your
  computer's), instead of being treated as UTC by `xmlschema`.
* **Filters don't apply to dates.** If a layout used
  `[% page.date | date_to_xmlschema %]`, it printed nothing; use
  `[% page.date.xmlschema %]`.
* **`dapper` exits with an error** for unknown commands and options, and
  when a build fails, which matters if you run it from scripts or `make`.

The full list is in the [Changes](Changes) file.

# Troubleshooting

**`[% ... %]` shows up as text on a page.** Since Dapper 1.0, page content
isn't run as template code unless the page sets `template: true` (or the
site sets `templates_in_content: true`). See [Template code in
content](#template-code-in-content).

**`N problems with front matter (see the _schema.yml files)`.** Pages don't
match their schema. Each line names the file and the field; fix the front
matter or the schema. `dapper check` lists them too.

**`... and ... both write ...`.** Two pages have the same URL, often
because of a `urlpattern` without `:slug`, or two posts with the same title
and month. Give one of them a different title or `urlpattern`.

**`could not find the project file "_config.yml"`.** Run `dapper` in the
directory that contains `_config.yml`, point to it with `-c`, or create a
new project with `dapper init`.

**`could not parse front matter in "..."`.** The YAML at the top of that
file is invalid. The most common cause is a colon inside a value; put the
value in quotes: `title: "Dapper: A Story"`.

**`"..." has front matter that is never closed`.** Add a line containing
only `---` after the front matter.

**`... uses the layout "post", but there is no such file in _layout`.**
Create `_layout/post.html`, or fix the `layout` setting in that file.

**`layout "..." is part of a loop of layouts`.** Two or more layouts name
each other in their `layout` settings. One of them must not have a parent.

**`could not understand the date "..."`.** Write dates as
`2014-05-02T10:30:00`, `2014-05-02 10:30:00` or `2014-05-02`.

**`unknown time zone "..."`.** Use a name from the
[tz database](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones),
such as `Europe/London` or `America/New_York`.

**`could not process ... with layout ...: parse error`.** There is a
mistake in a template directive, either in the layout or in the source file
(if the page has `template: true`, or the site sets
`templates_in_content: true`). The message gives the
line and what was expected, e.g. `Missing END directive`.

**`could not start the webserver on port 8000`.** Something else is using
the port. Stop it, or pick another port: `dapper -p 9000 serve`.

**Markdown wraps my HTML or template loop in `<p>` tags.** Move that page to
an `.html` source file, which is not run through Markdown. See [Source file
types](#source-file-types).

**A filter prints nothing.** Dapper's filters only work on text. For dates
use their methods (`[% page.date.xmlschema %]`,
`[% page.date.strftime('%Y') %]`), and for hashes and lists use the
built-in methods (`[% page.json(1) %]`).

**A page I deleted is still on the site.** Dapper removes output only for
files it wrote since your first 1.0 build (see [Drafts and clean
builds](#drafts-and-clean-builds)), and not at all with `clean: false`.
Delete the output directory once and build again.

**Accented characters look garbled.** Save source files, layouts and
`_config.yml` as UTF-8. Dapper reads and writes UTF-8 and declares it in the
starter layout (`<meta charset="utf-8">`).

To see every variable available to a page, use the debug page in [Appendix
B](#appendix-b-debugging).

# Further Reading

You can look for more information here:

* [MetaCPAN](https://metacpan.org/dist/App-Dapper)

* [Github](https://github.com/markdbenson/dapper)

* [Issues](https://github.com/markdbenson/dapper/issues)

* [Historical Releases on BackPAN](http://backpan.perl.org/authors/id/M/MD/MDB/)

* [Continuous Integration Status](https://github.com/markdbenson/dapper/actions)

# Appendix A: Extending

Dapper may be used as a perl module directly from a script. Examples:

    use App::Dapper;

    # Create a Dapper object
    my $d = App::Dapper->new();

    # Initialize a new website in the current directory
    $d->init();

    # Build the site
    $d->build();

    # Serve the site locally at http://localhost:8000
    $d->serve();

After installing Dapper, you can find documentation for this module with the
perldoc command.

    perldoc App::Dapper

# Appendix B: Debugging

With templating, it's easy to outsmart yourself and forget what variables are
assigned to which collection and how that collection should be used in a
template. Here is a way to debug that uses the template engine's built-in
`json` method to display all of the variables that are available for you to
use.

First, create a debug page in your `_source` directory:

    $ mkdir -p _source/debug
    $ touch _source/debug/index.html

Then, edit the file and fill it with this content:

```html
---
title: Debug
layout: plain
---

<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Dapper Debug</title>
</head>
<body>

<h1>site</h1>
<pre>[% site.json(1) | html %]</pre>

<h1>page</h1>
<pre>[% page.json(1) | html %]</pre>

</body>
</html>
```

Create a plain layout template:

    $ echo "[% page.content %]" > _layout/plain.html

Then, build your site and view the content locally at
http://localhost:8000/debug/

Dates (`page.date`, `site.time`) are objects, so they show as `null` in the
JSON; print them directly (`[% page.date %]`) to see their values. The
`| html` filter escapes the JSON so the browser shows it as text.

# Appendix C: Internals

There are two important aspects of Dapper internals that are important
to understand. The first is that layouts are templates, but page content
is not, unless the page sets `template: true`, in which case its content is
rendered first and then placed in the layout. With
`templates_in_content: true`, Dapper works as it did before 1.0: the
layout is rendered, and then the result is rendered a second time, so that
directives in content and in `_config.yml` values run too.

The second important thing to understand about Dapper internals is that
after all of the source files are rendered to output, Dapper does a
copy operation which copies things like binary files, images, or other
files that need to be transferred into the output directory but do not
need to be processed by Markdown or the templating system. The rules for what to 
copy are simple: every top-level file and directory is copied except for
those that match the site.ignore list. The source, layout and output
directories and the project file are never copied. Copying is done by Dapper
itself, not the shell, so file names with spaces or special characters are
fine. By default, the following ignore list is used:

```
ignore :
    - ^\.
    - ^_
    - ^dapper$
```

More files and regular expression patterns may be specified in the project
configuration file. For instance, if you have a folder that holds your
design files and is called `design`, you might not want to have that copied
into the output directory. In this case, you would add the following lines
to your `_config.yml` file:

```
ignore :
    - ^design$
```

# Appendix D: Contributing

Bug reports and pull requests are welcome at
[GitHub](https://github.com/markdbenson/dapper/issues). When reporting a
bug, include the output of `dapper -v`, `perl -v`, and the smallest
`_config.yml`, source file and layout that show the problem.

To work on Dapper itself:

    $ git clone https://github.com/markdbenson/dapper.git
    $ cd dapper
    $ cpanm --installdeps .
    $ prove -l t

* `bin/dapper` runs the working copy directly, so you can try changes on a
  real site: `perl ~/dapper/bin/dapper build`.
* Tests live in `t/`; `t/lib/DapperTest.pm` has helpers for building
  throwaway sites in a temporary directory. Please add a test with any fix.
* Set `RELEASE_TESTING=1` to also check the POD.
* GitHub Actions runs the tests on every push and pull request on Perl 5.10
  through 5.40.

# Author

Dapper was written by Mark Benson
[mark@jayber.org](mailto:mark@jayber.org).

# License and Copyright

The MIT License (MIT)

Copyright (c) 2002-2025 Mark Benson

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE use OR OTHER
DEALINGS IN THE SOFTWARE.

