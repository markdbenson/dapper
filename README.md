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

2. **Opinionated**. Content is written in
   [Markdown](http://search.cpan.org/~bobtfish/Text-MultiMarkdown/), and
   templates are written using
   [Liquid](http://search.cpan.org/dist/Template-Liquid/). Dapper
   combines these based on your instructions and helps you publish
   the results.

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
* Layouts are developed using the Liquid templating engine.
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
* Files in the output directory (`_output`) or any subfolder of the output directory.

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

    {{ site.name }}

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
    {{ page.name }}

**_layout/index.html**

Layout files are processed using the Liquid template system. The initial 
layout file that is given after you run the `dapper init` command, is this:

    <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
    <html>
    <head>
      <title>{{ page.title }}</title>
      <meta http-equiv="content-type" content="text/html; charset=iso-8859-1">
    </head>

    <body>

    {{ page.content }}

    </body>
    </html>

The main content of the text file that is being rendered with this template
is available using `{{ page.content }}`.

Definitions specified in the `_config.yml` file can be referenced under the
"site" namespace (e.g. {{ site.name }}. Definitions specified in the YAML
portion of text files can be referenced under the "page" namespace (e.g.
{{ page.title }}.

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

    {{ site.name }}

URL can be used like this:

    <a href="{{ site.url }}">{{ site.name }}</a>

The links (key/value pairs) can be listed like this:

    {% for link in site.links %}
        <a href="{{ link.value }}">{{ link.key }}</a><br />
    {% endfor %}

All of the items in the `ignore` array can be shown like this:

    <ul>
    {% for i in site.ignore %}
        <li>{{ i }}</li> 
    {% endfor %}
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

All source files must contain [YAM](http://yaml.org/) at the beginning. 
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
in Liquid templates. The body of the page (`Here is the text of the post.
`) in the above example, is available as `content` in Liquid templates.

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
{{ page.name }}<br />

<h2>Menu</h2>
<ul>
{% for link in page.menu %}
    <li><a href="{{ link.value }}">{{ link.key }}</a></li>
{% endfor %}
</ul>

<h2>Fruits</h2>
<ul>
{% for fruit in page.fruits %}
    <li>{{ fruit }}</li>
{% endfor %}
</ul>
```

Note that Dapper renders using the Liquid templating engine twice for each
source file in the project. The first time, the source file itself is 
rendered wherby all Liquid tags are processed.

After Dapper combines the source file with the template file, Dapper 
renders the Liquid tags a second time. The only difference between the tags
available to source files versus the tags available to layout files are
that `{{ page.content }}` is only available in layout files to prevent
circular references.

This double-rendering behavior of Dapper allows you to speciify Liquid 
tags in the source file in addition to the layout file, and gives you some 
extra flexibility. More information is available in [Appendix C: 
Internals](#appendix-c-internals).

## Introduction

Dapper depends on
[MultiMarkdown](http://fletcherpenney.net/multimarkdown/). Or, more 
specifically, the Perl module implementation of MultiMarkdown ([Text::
MultiMarkdown](http://search.cpan.org/~bobtfish/Text-MultiMarkdown/).

MultiMarkdown is based on the traditional definition of Markdown by
John Gruber of [Daring Fireball](http://daringfireball.net), but adds
additional nice features such as tables and footnotes.

## Markup

The following sections describe the markup that Dapper accepts, including
headings, text, lists, footnotes, tables, and images. There are more 
features of the MultiMarkdown engine that Dapper uses. See the
[MultiMarkdown documentation](http://fletcher.github.io/MultiMarkdown-4/) 
on CPAN for details.

### Headings

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

### Text

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

Code is placed in `backticks` (see [above](#text)), or as a "fenced code block" by surrounding an entire block of text with three backticks in a row.

```perl
```
#!/usr/bin/perl -w
print "Hello, world!\n";
``` ```

### Lists

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

### Footnotes

Footnotes can be accomplished as follows:

```
Here is some text containing a footnote[^somesamplefootnote]. You can then continue your thought...

[^somesamplefootnote]: Here is the text of the footnote itself.

This is an example of an inline footnote.[^This is the *actual* footnote.]
```

### Tables

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

### Images

Images can be specified in HTML by simply including the HTML in the 
text. Alternatively, here are some short-hand notations:

* Image: `![Image description.](img.png)`
* Image with title attribute: `![Image description.](img.png "This is a title")`
* Image with ID: `![Image description.][img_id]`

`[img_id]: img.png "This is a title" height=50px width=200px`

# Layout

Layout templates in Dapper are written using
[Liquid](http://liquidmarkup.org/), which is the template engine that 
powers [Shopify](http://shopify.com/). More specifically, Dapper uses the
[Template::Liquid](http://search.cpan.org/~sanko/Template-Liquid/) Perl
module, available on CPAN.

There are two types of markup in Liquid: Variables (also called
"Output"), and Logic Tags. Variables are surrounded by matched pairs of 
curly brackets. Example:

```liquid
{{ user.name }}
```

Logic Tags are surrounded by matched pairs of curly brackets and percent
signs. Example:

```liquid
{% for user in users %}
  {{ user.name }}
{% endfor %}
```

The following sections show how to use Liquid variables and tags in more
depth.

## Variables

Variables are bits of text or numbers that are defined in the project
configuration file or in the source files that can be used in templates.

(Note: In the original Liquid documentation, this type of markup is also
referred to as "output".)

In Dapper, there are two top-level variables (think of them as namespaces),
which are `site` and `page`. All `site` variables are defined in
`_config.yml`, and are available in layouts as `{{ site.* }}`. All page variables (defined at the beginning of source files) are available in
layouts as `{{ page.* }}`.

```liquid
Site-wide project name {{ site.name }}
Page title {{ page.title }}
```

## Filters

Variables can use filters. Filters are simple methods that take a string
as an input, along with zero or more optional parameters, and returns a 
string as a result. Filters can be chained together. Examples:

```liquid
Hello {{ site.name | upcase }}
The name of the site has {{ site.name | size }} letters
SEO page title is {{ page.title | append: ' -- An amazing site' | upcase }}
Hello {{ 'now' | date: "%Y %h" }}
```

Here is a list of filters that are available to you, as provided by
[Template::Liquid](http://search.cpan.org/~sanko/Template-Liquid/)
([filter documentation](http://search.cpan.org/~sanko/Template-Liquid/lib/Template/Liquid/Filters.pm))
and Dapper. Note that Dapper-specific filters are marked as [DSF]. Details 
on all others can be found in the
[Template::Liquid](http://search.cpan.org/~sanko/Template-Liquid/)
documentation.

Filter              | Description
--------------------|-----------------------------------------------------------------------
`append`            | Append a string *e.g.* <code>{{ 'foo' &#124; append:'bar' }} #=> 'foobar'</code>
`capitalize`        | Capitalize words in the input sentence
`date_to_xmlschema` | [DSF] Convert a date to an XML-formatted version of the date that also includes the timezone
`date`              | Reformat a date ([syntax reference](http://search.cpan.org/~sanko/Template-Liquid-v1.0.2/lib/Template/Liquid/Filters.pm))
`divided_by`        | Division *e.g.* <code>{{ 10 &#124; divided_by:2 }} #=> 5</code>
`downcase`          | Convert an input string to lowercase
`first`             | Get the first element of the passed in array
`join`              | Join elements of the array with certain character between them
`json`              | [DSF] Convert an object or string to a JSON representation
`last`              | Get the last element of the passed in array
`minus`             | Subtraction *e.g.*  <code>{{ 4 &#124; minus:2 }} #=> 2</code>
`modulo`            | Remainder, *e.g.* <code>{{ 3 &#124; modulo:2 }} #=> 1</code>
`newline_to_br`     | Replace each newline (\n) with html break
`plus`              | Addition *e.g.*  <code>{{ '1' &#124; plus:'1' }} #=> '11'</code>, <code>{{ 1 &#124; plus:1 }} #=> 2</code>
`prepend`           | Prepend a string *e.g.* <code>{{ 'bar' &#124; prepend:'foo' }} #=> 'foobar'</code>
`remove_first`      | Remove the first occurrence *e.g.* <code>{{ 'barbar' &#124; remove_first:'bar' }} #=> 'bar'</code>
`remove`            | Remove each occurrence *e.g.* <code>{{ 'foobarfoobar' &#124; remove:'foo' }} #=> 'barbar'</code>
`replace_first`     | Replace the first occurrence *e.g.* <code>{{ 'barbar' &#124; replace_first:'bar','foo' }} #=> 'foobar'</code>
`replace_last`      | [DSF] Replace the last occurrance of a string with another string
`replace`           | Replace each occurrence *e.g.* <code>{{ 'foofoo' &#124; replace:'foo','bar' }} #=> 'barbar'</code>
`size`              | Return the size of an array or string
`smart`             | [DSF] Replace dashes with mdashes and ndashes
`sort`              | Sort elements of the array
`split`             | Split a string on a matching pattern *e.g.* <code>{{ "a~b" &#124; split:"~" }} #=> ['a','b']</code>
`strip_html`        | Strip html from string
`strip_newlines`    | Strip all newlines (\n) from string
`times`             | Multiplication  *e.g* <code>{{ 5 &#124; times:4 }} #=> 20</code>
`truncate`          | Truncate a string down to x characters
`truncatewords`     | Truncate a string down to x words
`upcase`            | Convert an input string to uppercase
`xml_escape`        | [DSF] Escape strings that may contain XML so the string can be included in XML files such as ATOM or RSS feeds

## Logic Tags

Logic Tags are used for controlling the procedural flow through a template. 
Here is a list of supported tags:

* **assign** - Assigns some value to a variable
* **capture** - Block tag that captures text into a variable
* **case** - Block tag, its the standard case...when block
* **comment** - Block tag, comments out the text in the block
* **cycle** - Cycle is usually used within a loop to alternate between values, like colors or DOM classes.
* **for** - For loop
* **if** - Standard if/else block
* **include** - Includes another template; useful for partials
* **raw** - temporarily disable tag processing to avoid syntax conflicts.
* **unless** - Mirror of if statement

### Assign

In Liquid templates, data can be stored in variables. These variables
can then be used in output or other tags as appropriate. The simplest way to create a variable is with the `assign` tag. Example:

```liquid
{% assign category = 'featured' %}

{% for t in page.categories %}{% if t == category %}
  <p>{{ page.title }} is a featured article.</p>
{% endif %}{% endfor %}
```
Another way of doing this would be to assign `true / false` values to the
variable:

```liquid
{% assign flagged = false %}

{% for t in page.categories %}{% if t == 'featured' %}
  {% assign flagged = true %}
{% endif %}{% endfor %}

{% if flagged %}
  <p>{{ page.title }} is a featured article.</p>
{% endif %}
```

### Capture 

If you want to combine a number of strings into a single string and save 
it to a variable, you can do that with the `capture` tag. This tag is a 
block which "captures" whatever is rendered inside it, then assigns the 
captured value to the given variable instead of rendering it to the screen.

```liquid
  {% capture date_string %}Article published {{ page.date | date: "%d %B %Y" }}{% endcapture %}

  <h1>{{ page.title }}</h1>
  <p>{{ date_string }}</p>
```

### Case

Liquid has a built-in `case` construct, which can be used as follows:

```liquid
{% case template %}

{% when 'preface' %}
     Preface: {{ page.title }}
{% when 'product' %}
     {{ page.product_name }}
{% else %}
     No template given
{% endcase %}
```

### Comments

Comments in Liquid are also possible. Example:

```liquid
{% comment %}Here is a comment{% endcomment %}
A regular sentence that will be rendered in the final output.
```

### Cycle

Often you have to alternate between different colors or similar tasks
such as when coloring all even rows in a table. Liquid has built-in 
support for cycles. Example:

```liquid
{% cycle 'flip', 'flop' %}
{% cycle 'flip', 'flop' %}
{% cycle 'flip', 'flop' %}
{% cycle 'flip', 'flop' %}
```

... which will result in:

```
flip
flop
flip
flop
```

If no name is supplied for the cycle group, then it's assumed that multiple
calls with the same parameters are one group. If you want to have total 
control over cycle groups, you can optionally specify the name of the 
group. This can even be a variable.

```liquid
{% cycle 'group 1': 'one', 'two', 'three' %}
{% cycle 'group 1': 'one', 'two', 'three' %}
{% cycle 'group 2': 'one', 'two', 'three' %}
{% cycle 'group 2': 'one', 'two', 'three' %}
```

... which will result in:

```
one
two
one
two
```

### For

Liquid allows `for` loops over collections. Example:

```liquid
{% for item in array %}
  {{ item }}
{% endfor %}
```

When iterating a hash, `item[0]` contains the key, and `item[1]` contains 
the value:

```liquid
{% for item in hash %}
  {{ item[0] }}: {{ item[1] }}
{% endfor %}
```

During every `for` loop, the following helper variables are available for 
extra styling needs:

```liquid
forloop.length   # => length of the entire for loop
forloop.index    # => index of the current iteration
forloop.index0   # => index of the current iteration (zero based)
forloop.rindex   # => how many items are still left?
forloop.rindex0  # => how many items are still left? (zero based)
forloop.first    # => is this the first iteration?
forloop.last     # => is this the last iteration?
```

There are several attributes you can use to influence which items you 
receive in your loop:

* `limit:int` lets you restrict how many items you get.
* `offset:int` lets you start the collection with the nth item.

Example: 

```liquid
# array = [1,2,3,4,5,6]
{% for item in array limit:2 offset:2 %}
  {{ item }}
{% endfor %}
# results in 3,4
```

It's also possible to reverse the order of how you iterate through a loop:

```liquid
{% for item in collection reversed %} {{item}} {% endfor %}
```

Instead of looping over an existing collection, you can define a range of
numbers to loop through. The range can be defined by both literal and 
variable numbers:

```liquid
# if item.quantity is 4...
{% for i in (1..item.quantity) %}
  {{ i }}
{% endfor %}
# results in 1,2,3,4
```

### If/Else

Liquid also supports a standard `if / else` construct. Liquid allows you 
to write simple expressions in the `if` or `unless` (and optionally, `elsif` and `else`) clause. Example:

```liquid
{% if site.author %}
  Author: {{ site.author }}
{% endif %}
```

Here is the same thing, but done with a `!=`:

```
# Same as above
{% if site.author != null %}
  Author: {{ site.author }}
{% endif %}
```

Example if/else format:

```liquid
{% if site.author == 'markbenson' %}
  Author: MDB
{% elsif site.author == 'loomisbuschwa' %}
  Author: Loomis Buschwa
{% endif %}
```

Complex or/and logic: 

```liquid
{% if site.author == 'markbenson' or site.author == 'loomisbuschwa' %}
  Author: Mark or Loomis
{% endif %}
```

```liquid
{% if site.author == 'markbenson' and site.author == 'loomisbuschwa' %}
  Author: Mark and Loomis
{% endif %}
```

Not equal:

```liquid
{% if site.author != 'markbenson' %}
  Author: not MDB
{% endif %}
```

Same as above:

```liquid
{% unless site.author == 'markbenson' %}
  Author: not MDB
{% endunless %}
```

Check the size of an array:

```liquid
{% if site.links == empty %}
   No links defined. 
{% endif %}

{% if site.links.size > 1  %}
   Multiple links defined.
{% endif %}
```

```liquid
{% if site.authors contains 'markbenson'  %}
   MDB in the house.
{% endif %}
```

```liquid
{% if site.author contains 'mark' %}
   One of the author's name is Mark.
{% endif %}
```

### Raw

Raw temporarily disables tag processing.
This is useful for generating content (eg, Mustache, Handlebars) which uses conflicting syntax.

```liquid
{% raw %}
  In Handlebars, {{ this }} will be HTML-escaped, but {{{ that }}} will not.
{% endraw %}
```

### Unless

Mirror of [If](#if-else) statement. Example:

```
{% unless some.value == 3 %}
    Well, the value sure ain't three.
{% elseif some.value > 1 %}
    It's greater than one.
{% else %}
    Well, is greater than one but not equal to three.
    Psst! It's {{some.value}}.
{% endunless %}
```

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

An optional step is to route traffic to your website through Amazon's Route 53. To do this, follow these steps:

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

## FTP

FTP is perhaps the most simple option. Just upload the contents of your 
`_output` directory to the directory on your server that is served by your 
webserver application.
  
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

With templating, it's easy to outsmart yourself and forget what variables are assigned
to which collection and how that collection should be used in a template. Here is a way
to debug that makes use of the `json` template filter built in to Dapper. The resulting
page that we'll create displays all of the Liquid tags that are available for you to use.

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

<div id="editor">{{ site | json }}</div>
  
<script src="//cdnjs.cloudflare.com/ajax/libs/ace/1.1.3/ace.js" type="text/javascript" charset="utf-8"></script>
<script>
    var editor = ace.edit("editor");
    editor.setTheme("ace/theme/text_mate");
    editor.getSession().setMode("ace/mode/json");
    editor.setReadOnly(true);
    window.setTimeout(function() { editor.getSession().foldAll(2,editor.session.getLength()); }, 100);
</script>
</body>
</html>
```

Create a plain layout template:

    $ echo "{{ page.content }}" > _layout/plain.html

Then, build your site and view the content locally at http://localhost:8000/debug/

# Appendix C: Internals

There are two importatn aspects of Dapper internals that are important
to understand. The first is that source files are rendered using the 
Liquid templating system once, and then again after being combined with
a layout. This means that Liquid tags and output can be used in source
files.

The second important thing to understand about Dapper internals is that
after all of the source files are rendered to output, Dapper does a 
copy operation which copies things like binary files, images, or other
files that need to be transferred into the output directory but do not
need to be processed by Markdown or Liquid. The rules for what to copy are
simple: everything is copied except for those things that match the
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
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER 
DEALINGS IN THE SOFTWARE.

