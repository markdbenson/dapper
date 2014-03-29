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

## Quick Start Guide

Get up and running in seconds:

    $ cpanm App::Dapper
    $ mkdir new-site
    $ cd new-site
    $ dapper init
    $ dapper serve
    
After that, browse to [http://localhost:8000](http://localhost:8000) to see your site.

The remainder of this document defines how to configure Dapper, write content,
develop templates, and create righteously static sites.

## References

After installing, you can find documentation for this module with the
perldoc command.

    perldoc App::Dapper

You can also look for information at:

* [Find the module on CPAN](http://search.cpan.org/dist/App-Dapper/)

* [Find source code on Github](https://github.com/markdbenson/dapper)

* [Submit an issue on Github](https://github.com/markdbenson/dapper/issues)

* [Find historical releases on BackPAN](http://backpan.perl.org/authors/id/M/MD/MDB/)

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

## License and Copyright

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

