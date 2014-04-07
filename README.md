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

3. **Pragmatic**. The easy things are easy and the hard things are possible.
   Dapper was created to solve problems in a straight-forward and intuitive 
   way.

Why static? Decent question. Here are some reasons:

1. **Fast**. Static pages are fast to load and easy to cache. Content 
   management systems, on the other hand, may contact the database at least 
   one time per page request, process the results, merge with a templating 
   system, and serve the result to the user's web browser.

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

4. **Portable**. With a static website, it's way easier to move the site to 
   a new host in the future. All web hosts now and in the future support 
   serving up a static website -- think of it as the lowest common 
   denominator -- and so there's no need to pick a premium host with 
   premium services.

Dapper was first written in 2002 to facilitate the creation of a series
of static websites that each had their own look and feel, but shared 
content. Since then, Dapper has been used to create websites for speakers, 
artists, authors, illusionists, web designers, piano tuners, photographers, 
entertainment agencies, and API documentation for industrial sensing 
equipment. In addition, it is the tool that powers
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
version of Dapper you have, as well as how to use the `dapper` command-line 
utility and work with the directory structure it depends on.

## Install

Install Dapper in seconds:

    $ cpanm App::Dapper

Then, create a new site, build it, and view it locally like so:

    $ mkdir new-site && cd new-site
    $ dapper init
    $ dapper build
    $ dapper serve
    
After that, browse to [http://localhost:8000](http://localhost:8000) to see 
your site.  To modify the content, look at `_source/index.md`. To modify 
the layout, edit `_layout/index.html`.

Dapper requires Perl 5.8.0 or greater. To find which version of Perl you have, do this:

    $ perl -v

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
`dapper` will be available to you in your terminal window. You can use this 
executable in a number of ways. The following sections show you how.

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
command. Dapper takes care of reading the source files, combining them with 
the layout template(s), and saving the result in the `_output` directory.

    # Build the site
    $ dapper build

### Watch

The `dapper watch` command builds the site and then watches all the files
in the `_source/*` and `_layout/*` directories for changes. If any changes 
occur, the site is rebuilt again. The `dapper watch` command will do this 
repeatedly until you exit using *Ctrl-C*.

    # Rebuild the site if anything (source, layout dirs; config file) changes
    $ dapper watch

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

In that same directory, you may then build the site using the `dapper build`
command, which will combine the source files and the layout files and place
the results in the output directory (default: `_output`). After you build
the default site, you'll then have the following directory structure:

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

## Next Steps

Now that you have Dapper installed and have a project that builds and can 
be viewed, try out a few things:

1. Modify the content
2. Modify the layout
3. Add content

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

# Appendix B: Working with the Perl Module Directly

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

