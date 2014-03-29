# Dapper

Dapper is a publishing tool for static websites.

Distributed as a Perl module, App::Dapper comes with an application called
"dapper" which you can use from the command line and makes it easy to use
the App::Dapper perl module to create static websites.

Dapper was created to easily build static websites and has three goals:

1. **Simple**. Gets out of the way so you can write your content and
develop your templates. No hassle, simple, and straight-forward.

2. **Static**. Content is written in Markdown, templates are written in Liquid.
Dapper combines the two and creates a static website based on your instructions.

3. **Pragmatic**. Built for pragmatists by a pragmatist. The easy things
are easy, and the hard things are possible.

The rest of this document shows you how to get your site set up and running,
how to create and manage content, how to tweak the way it looks, and how to 
deploy to various environments. 

## Introduction

What is Dapper anyways?

## Installation

Get up and running in seconds:

    $ cpanm App::Dapper
    $ mkdir new-site
    $ cd new-site
    $ dapper init
    $ dapper serve
    
After that, browse to [http://localhost:8000](http://localhost:8000) to see your site.

The remainder of this document defines how to configure Dapper, write content,
develop templates, and create righteously static sites.

## Features

## Contact

If you have a feature request, or find issues with Dapper or with the documentation,
please submit an issue and I'll take a look.

You can also look for information at:

* [CPAN](http://search.cpan.org/dist/App-Dapper/)

* [Github](https://github.com/markdbenson/dapper)

* [Issues](https://github.com/markdbenson/dapper/issues)

* [Historical Releases on BackPAN](http://backpan.perl.org/authors/id/M/MD/MDB/)

# Tutorial

## Create a Project

## Build the Project

## View the Results

### Changing the Port

### Auto-reload Changes

## Customize the Content

## Customize the Layout

## Add New Content

## Write Plugins

## Publish The Results

# Reference

## Command Line Tool

## Configuration

## Writing Source Files in Markdown

## Writing Layouts in Liquid

# References

# Appendicies

## Appendix A: Install from Source

A list of past releases can be found on
[backpan](http://backpan.perl.org/authors/id/M/MD/MDB/). After downloading
and unpacking the release, do this:

    $ perl Makefile.PL
    $ make
    $ make test
    $ make install

Dapper requires Perl 5.14 or greater. To find which version of dapper you have 
installed, do this:

    $ dapper -v

## Appendix B: Working with the Perl Module

After installing Dapper, you can find documentation for this module with the
perldoc command.

    perldoc App::Dapper

# License and Copyright

The MIT License (MIT)

Copyright (c) 2002-2014 Mark Benson

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

