# Dapper

A publishing tool for static websites

[Distributed as a Perl module](http://search.cpan.org/~mdb/App-Dapper/),
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
   [Markdown](http://search.cpan.org/~bobtfish/Text-MultiMarkdown/), and
   templates are written using the TT3 mini-language from
   [Template::Alloy](http://search.cpan.org/~abw/Template-Toolkit/) for 
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
industrial sensing equipment. In addition, it is the tool that powers
[Vanilla Draft](http://vanilladraft.com/).

In 2014, Dapper was submitted as a Perl module (App::Dapper) to
[CPAN](http://cpan.org/) under the MIT license for anyone to use for any
purpose.

**Features**

* Written in perl, available as a command line utility after installing.
* Content is written in Markdown.
* Layouts are developed using TT3 from the Template::Alloy templating engine.
* Configuration files and attributes are encoded with YAML.

The rest of this document shows you how to get your site up and running,
how to manage the content and the way it looks, and how to deploy the
result to your favorite web host.

# Getting Started

The following sections show you how to install, upgrade, and downgrade the
version of Dapper you have, as well as how to use the `dapper` command-
line utility and work with the directory structure it depends on.

## Install

Install Dapper in seconds:

    $ cpanm App::Dapper

Then, create a new site, build it, and view it locally like so:

    $ mkdir new-site && cd new-site
    $ dapper init
    $ dapper build
    $ dapper serve

After that, browse to [http://localhost:8000](http://localhost:8000) to
see your site.  To modify the content, look at `_source/index.md`. To
modify the layout, edit `_layout/index.html`.

### Upgrade

Find out which version of Dapper you have, by using the `-v` option:

    $ dapper -v

You can compare this with the latest version from CPAN like this:

    $ cpan -D App::Dapper

    ...
    M/MD/MDB/App-Dapper-0.13.tar.gz
    /Library/Perl/5.16/App/Dapper.pm
    Installed: 0.12
    CPAN:      0.13  Not up to date
    Mark Benson (MDB)
    markbenson@vanilladraft.com

In this example, you can see there is a newer version available. Upgrade
like this:

    $ cpan App::Dapper

Stable releases are available on CPAN, but development happens at
[Github](https://github.com/markdbenson/dapper). If you like living on the
edge, install from the latest development tip like this:

    $ cpanm git://github.com/markdbenson/dapper.git

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
directory and all subdirectories and files except:

* Files that begin with a period (.).
* Files that begin with an underscore (_).
* Files in the output directory (`_output`) or any subfolder of the output 
  directory.

### Serve

The `dapper serve` command builds the site, serves the contents of the
`_output` directory using Dapper's built-in webserver, and handles auto-
rebuilding your site if anything changes. You can think of the `dapper
serve` command as a combination of `build`, `watch`, and `serve`.

    # Serve the site locally at http://localhost:8000
    $ dapper serve

If you want to use a different port number (e.g. 9000), specifiy it using
the *-p* option:

    # Serve the site locally at http://localhost:9000
    $ dapper -p 9000 serve

### Help

To get more information about command-line options available, the current
version of Dapper that you have installed on your system, or further
documentation available, see the followig:

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

1. There is a YAML configuration block at the start of the file.

2. The *layout* configuration specifies which layout to use.

3. The `index` layout indicates that `_layout/index.html` should be used.

4. The `title` configuration is the name of the post/page. It is optional.

5. All of the configurations may be used in the corresponding layout file.

    <!-- Example use of "name" in a layout file -->
    [% page.name %]

**_layout/index.html**

Layout files are processed using the TT3 mini-language from the Template::Alloy 
template system. The initial layout file that is given after you run the `dapper 
init` command, is this:

    <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
    <html>
    <head>
      <title>[% page.title %]</title>
      <meta http-equiv="content-type" content="text/html; charset=iso-8859-1">
    </head>

    <body>

    [% page.content %]

    </body>
    </html>

The main content of the text file that is being rendered with this template
is available using `[% page.content %]`.

Definitions specified in the `_config.yml` file can be referenced under the
"site" namespace (e.g. `[% site.name %]`. Definitions specified in the YAML
portion of text files can be referenced under the "page" namespace (e.g.
`[% page.title %]`.

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

    <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
    <html>
    <head>
      <title>Welcome</title>
      <meta http-equiv="content-type" content="text/html; charset=iso-8859-1">
    </head>

    <body>

    <p>Hello world.</p>

    </body>
    </html>

# Configuration

Dapper allows you to create static websites in just about any way that you
want to. The project configuration file (`_config.yml`) allows you to
specify special instructions to Dapper and also to guide the process of
rendering the site using the source files (`_source/`) and the layout
templates (`_layout/`).

Variables specified in `_config.yml` are done using YAML. Here is the
default configuration file created after a `dapper init` command:

    # Dapper configuration file.
    ---
    name: My Site

Note that lines beginning with `#` are comments. Lines with `---` mark the
beginning/end of a YAML "document". What follows are `<key>:<value>`
pairs or arrays, arranged hierarchically:

    # Dapper config file
    ---
    name: Vanilla Draft
    url: http://vanilladraft.com/
    source : _source/
    output : _output/
    layout : _layout/
    links :
        Preface : /preface/
        Feed : http://feeds.feedburner.com/vanilladraft
        Amazon : http://amazon.com/author/markbenson
        Github : http://github.com/markdbenson
        LinkedIn : http://linkedin.com/in/markbenson
        Twitter : https://twitter.com/markbenson
    ignore :
        - "^\."
        - "^_"
        - "^design$"
        - "^README.md$"
        - "^Makefile$"

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
[YAML::Tiny](http://search.cpan.org/~ether/YAML-Tiny/) Perl module
documentation (Dapper's YAML parsing engine) for more information.

# Source

Source files in Dapper are written in
[Markdown](https://daringfireball.net/projects/markdown/). Markdown is a
markup language that allows you to write content in a natural way, and
have that text converted to XHTML for displaying on the web.

Writing with Markdown allows you to separate the content and structure of
your document from the formatting which allows you to focus on the actual
writing.

All source files must contain [YAML](http://yaml.org/) at the beginning.
The YAML at the beginning of the source files is denoted by leading
and trailing lines that each contain a sequence of three dashes. Example:

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
      hyphens (`-`), and converted to lowercase.

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

Note that Dapper renders templates twice for each source file in the project. The 
first time, the source file itself is rendered wherby all directives are 
processed.

After Dapper combines the source file with the template file, Dapper
renders the template directives a second time. The only difference 
between the variables available to source files versus the variables available to 
layout files are that `[% page.content %]` is only available in layout files to 
prevent circular references.

This double-rendering behavior of Dapper allows you to speciify layout 
directives in the source file in addition to the layout file, and gives you some
extra flexibility. More information is available in [Appendix C:
Internals](#appendix-c-internals).

Dapper depends on
[MultiMarkdown](http://fletcherpenney.net/multimarkdown/). Or, more
specifically, the Perl module implementation of MultiMarkdown ([Text::
MultiMarkdown](http://search.cpan.org/~bobtfish/Text-MultiMarkdown/).

MultiMarkdown is based on the traditional definition of Markdown by
John Gruber of [Daring Fireball](http://daringfireball.net), but adds
additional nice features such as tables and footnotes.

The following sections describe the markup that Dapper accepts, including
headings, text, lists, footnotes, tables, and images. There are more
features of the MultiMarkdown engine that Dapper uses. See the
[MultiMarkdown documentation](http://fletcher.github.io/MultiMarkdown-4/)
on CPAN for details.

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
Link to `[Vanilla Draft](http://vanilladraft.com).` | Link to [Vanilla Draft](http://vanilladraft.com).
Link to `[Vanilla Draft][ln1].`         | Link to [Vanilla Draft][ln1].
Link to `<http://vanilladraft.com>.`    | Link to http://vanilladraft.com.
`> This is the first level of quoting.` | The first level of quoting.
`>> This is a nested blockquote.`       | A nested blockquote.

`[ln1]: http://vanilladraft.com "Vanilla Draft"`
[ln1]: http://vanilladraft.com "Vanilla Draft"

Code is placed in `backticks` (see [above](#text)), or as a "fenced code block" 
by surrounding an entire block of text with three backticks in a row.

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
matter -- just that they are numbers. Exmaple:

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
[Template::Alloy](http://search.cpan.org/~rhandom/Template-Alloy/). 
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
which are `site` and `page`. All `site` variables are defined in
`_config.yml`, and are available in layouts as `[% site.* %]`. All page
variables (defined at the beginning of source files) are available in
layouts as `[% page.* %]`.

Example `_config.yml`:

```
name: Vanilla Draft
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
    <title>The title of my post - Vanilla Draft</title>
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
[% link = {name => 'Vanilla Draft', 'url' => 'http://vanilladraft.com/'} %]
<a href="[% link.url %]">[% link.name %]</a>
```

Result:

```
<a href="http://vanilladraft.com/">Vanilla Draft</a>
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
[Template::Alloy::Operator](http://search.cpan.org/~rhandom/Template-Alloy/lib/Template/Alloy/Operator.pm).

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
[% site.name = " Vanilla Draft    " %]
[% site.name | upper | trim %]
[% page.title = "My very long page title that should be truncated" %]
[% page.title | truncate(26) %]
```

Results:

```
VANILLA DRAFT
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
`date_to_xmlschema`  | [DSF] Convert a date to an XML-formatted version of the date that also includes the timezone
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
`json`               | [DSF] Convert an object or string to a JSON representation
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
`replace_last`       | [DSF] Replace the last occurrance of a string with another string
`return`             | Returns the item from the inner most block, macro, or file. Similar to the `return` directive.
`search(s)`          | Tests if the given pattern is in the string.
`sin`                | Returns the sine of the item.
`size`               | Always returns 1 for text variables.
`smart`              | [DSF] Replace dashes with mdashes and ndashes
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

## Includes

An `include` directive parses the contents of a file or `block` and inserts them
into the template. Variables that are defined or modified within the included
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

# Deployment

To deploy your content, you have a number of options. This section outlines
a few of them.

## Amazon S3

It's possible to serve a static website using Amazon S3. Here's how.

1. Go to Amazon's AWS Console and create 2 buckets: 'www.mydomain.com' and
   'mydomain.com'. Content will be loaded into the 'mydomain.com' bucket and
   'www.mydomain.com' will just point to it.

2. Under the properties for the 'www.mydomain.com' bucket, choose 'redirect
   all requests to another host name' under 'Static Web Hosting'.

3. Under properties for 'mysite.com', choose 'enable website hosting' under
   'Static Web Hosting', and set 'Index Document' to 'index.html'.

4. Install [s3cmd](http://s3tools.org/s3cmd). On Mac OSX, using
   [Homebrew](http://brew.sh/), install like this:

       $ pip install s3cmd

5. Configure `s3cmd` with your Amazon credentials (AWS access key, secret
   key):

       $ s3cmd --configure

6. Now any time you want to rebuild your content and push it to s3, it's a
   simple call to:

       $ s3cmd sync _output/ s3://mydomain.com --reduced-redundancy --acl-public --delete-removed

    A few notes about the options. First, `--reduced-redundancy` tells
    Amazon that your website content is non-critical and easily
    reproducible if there is a problem. It means your charges from Amazon
    will be less and is a good option for most static sites.

    Second, the `--acl-public` option makes everything in the bucket
    public, which is what we want for a static website. We want the world
    to have read access to the contents of the bucket, and `--acl-public`
    accomplishes this.

    Third, the `--delete-removed` option tells `s3cmd` to delete files in
    the bucket that are not stored locally. This cleans things up so that
    you don't have lots of extra crap sitting in your bucket that isn't
    being used, but is costing you money. If you upload image files
    independently of Dapper or `s3cmd`, you may want to not use this option.

An optional step is to route traffic to your website through Amazon's Route 53. 
To do this, follow these steps:

1. Create 2 A records, one for 'mydomain.com' and one for 'www.mydomain.
   com'.

2. For each A record, set 'Alias' to yes, and set 'Alias Target' to the S3
   bucket with the same name.

To make it easy to publish to Amazon S3, one option is to create a Makefile
that encodes the publishing instructions. Here is a Makefile that I use for
[Vanilla Draft](http://vanilladraft.com/):

    BASEDIR=$(CURDIR)
    INPUTDIR=$(BASEDIR)/_source
    OUTPUTDIR=$(BASEDIR)/_output

    S3_BUCKET=vanilladraft.com

    build:
    	dapper build

    serve: build
    	dapper serve

    publish: build
    	s3cmd sync $(OUTPUTDIR)/ s3://$(S3_BUCKET) --reduced-redundancy --acl-public --delete-removed

    watch:
    	dapper watch

    .PHONY: build serve publish watch

## Github Pages

Github Pages is a free service that allows you to publish a static website for
free. By pushing your changes to a git repository, your website will be
automatically available on github.io. Here are the steps:

1. First, if you don’t have an account already, you should sign up for a [Github 
   account](http://github.com/).

2. Next, create a new repository named `<username>.github.io` where you should 
   replace `<username>` with your actual Github username.

3. After that, push the contents of your `_output` directory to the new github
   repo. Steps:

       $ cd _output
       $ git init
       $ git remote add origin https://github.com/<username>/<username>.github.io.git
       $ git add *
       $ git commit -m"Initial revision"
       $ git push

4. Wait a few minutes. Then, find your new website on github.io at the following 
   address: `http://<username>.github.io`.

# Further Reading

You can look for more information here:

* [CPAN](http://search.cpan.org/dist/App-Dapper/)

* [Github](https://github.com/markdbenson/dapper)

* [Issues](https://github.com/markdbenson/dapper/issues)

* [Historical Releases on BackPAN](http://backpan.perl.org/authors/id/M/MD/MDB/)

* [Continuous Integration Status](https://travis-ci.org/markdbenson/dapper)

# Appendix B: Extending

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
template. Here is a way to debug that makes use of the `json` template filter 
built in to Dapper. The resulting page that we'll create displays all of the 
varialbes that are available for you to use.  

First, create a debug page in your `_source` directory:

    $ echo "" > _source/debug/index.html

Then, edit the file and fill it with this content:

```html
---
name: Debug
layout: plain
---

<!DOCTYPE html>
<html lang="en">
<head>
<title>Dapper Debug</title>
<style type="text/css" media="screen">
    #editor {
        position: absolute;
        top: 0;
        right: 0;
        bottom: 0;
        left: 0;
    }
</style>
</head>
<body>

<div id="editor">[% dump site | json(1)%]</div>

<script src="//cdnjs.cloudflare.com/ajax/libs/ace/1.1.3/ace.js"
    type="text/javascript" charset="utf-8"></script>
<script>
    var editor = ace.edit("editor");
    editor.setTheme("ace/theme/text_mate");
    editor.getSession().setMode("ace/mode/json");
    editor.setReadOnly(true);
    window.setTimeout(function() {
        editor.getSession().foldAll(2,editor.session.getLength());
    }, 100);
</script>
</body>
</html>
```

Create a plain layout template:

    $ echo "[% page.content %]" > _layout/plain.html

Then, build your site and view the content locally at http://localhost:8000/debug/

# Appendix C: Internals

There are two importatn aspects of Dapper internals that are important
to understand. The first is that source files are rendered using the
templating system once, and then again after being combined with
a layout. This means that layout variables and directives can be used in source
files.

The second important thing to understand about Dapper internals is that
after all of the source files are rendered to output, Dapper does a
copy operation which copies things like binary files, images, or other
files that need to be transferred into the output directory but do not
need to be processed by Markdown or the templating system. The rules for what to 
copy are simple: everything is copied except for those things that match the
site.ignore list. By default, the following ignore list is used:

```
ignore :
    - "^\."
    - "^_"
    - "^dapper$"
```

More files and regular expression patterns may be specified in the project
configuration file. For instance, if you have a folder that holds your
design files and is called `design`, you might not want to have that copied
into the output directory. In this case, you would add the following lines
to your `_config.yml` file:

```
ignore :
    - "^design$"
```

# Author

Dapper was written by Mark Benson
[markbenson@vanilladraft.com](mailto:markbenson@vanilladraft.com).

# License and Copyright

The MIT License (MIT)

Copyright (c) 2002-2014 Mark Benson

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

