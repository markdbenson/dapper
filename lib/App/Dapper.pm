package App::Dapper;

=head1 NAME

App::Dapper - A publishing tool for static websites.

=cut

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.010;
use strict;
use warnings;

use vars '$VERSION';

use Exporter qw(import);

use Template::Alloy;
use JSON ();

use App::Dapper::Markdown;
use App::Dapper::Schema;
use App::Dapper::Publish;
use App::Dapper::Collections;
use App::Dapper::Check;
use App::Dapper::MCP;
use App::Dapper::Agents;

use YAML::PP qw/ LoadFile /;
use File::Spec;
use File::Spec::Functions qw/ canonpath catfile /;
use File::Basename qw/ basename /;
use File::Find ();
use Cwd qw/ abs_path /;

use DateTime;
use DateTime::TimeZone;

use App::Dapper::Init;
use App::Dapper::Utils;
use App::Dapper::Defaults;
use App::Dapper::Filters;

my $DEFAULT_PORT = 8000;

=head1 VERSION

Version 1.00

=cut

our $VERSION = '1.00';

our @EXPORT = qw($VERSION);

=head1 SYNOPSIS

B<Dapper> allows you to transform simple text files into static websites. By installing the App::Dapper Perl module, an executable named C<dapper> will be available to you in your terminal window. You can use this executable in a number of ways:

    # Initialize the current directory with a fresh skeleton of a site
    $ dapper [-solc] init

    # ...or with a complete starter blog
    $ dapper init --template blog

    # Build the site
    $ dapper [-solc] build

    # Serve the site locally at http://localhost:8000
    $ dapper [-solcp] serve

    # Rebuild the site if anything (source, layout dirs; config file) changes
    $ dapper [-solc] watch

    # Check the site for problems, without touching the output directory
    $ dapper [-solc] check [--json]

    # Let AI assistants read, write, check and build the site over MCP
    $ dapper -C /path/to/site mcp

    # Get help on usage and switches
    $ dapper -h

    # Print the version
    $ dapper -v

Additionally, B<Dapper> may be used as a perl module directly from a script. Examples:

    use App::Dapper;

    # Create a Dapper object
    my $d = App::Dapper->new();

    # Initialize a new website in the current directory
    $d->init();

    # Build the site
    $d->build();

    # Serve the site locally at http://localhost:8000
    $d->serve();

=head1 DESCRIPTION

Dapper helps you build static websites. To get you started, you can use the
C<dapper init> command to initialize a directory. After running this command,
the following directory structure will be created:

    _config.yml
    _layout/
        index.html
    _source/
        index.md

In that same directory, you may then build the site using the C<dapper build>
command, which will combine the source files and the layout files and place
the results in the output directory (default: C<_output>). After you build
the default site, you'll then have the following directory structure:

    _config.yml
    _layout/
        index.html
    _source/
        index.md
    _output/
        index.html

To see what your website looks like, run the C<dapper serve> command which
will spin up a development webserver and serve the static files located in
the output directory (default: C<_output>) at L<http://localhost:8000>.

Now, let's walk through each file:

=over 4

=item B<_config.yml>

The configuration file is a YAML file that specifies key configuration
elements for your static website. The default configuration file is as
follows:

    ---
    name : My Site

If you want to use a separate source, layout, or output directory, you may
specify it in this file. For instance:

    ---
    name : My Site
    source : _source
    layout : _layout
    output : _output

Directories given on the command line take precedence over the ones in the
configuration file, which take precedence over the defaults.

All of the configurations in this file are available in layout templates
under the C<site> namespace. For instance, C<name> in the configuration file
may be used in a template as follows:

    [% site.name %]

=item B<_source/index.md>

A sample markdown file is available in the _source directory. Contents:

    ---
    layout: index
    title: Welcome
    ---

    Hello world.

There are a few things to note about this file:

=over 4

=item 1. There is a YAML configuration block (the "front matter") at the start of the file.

=item 2. The I<layout> configuration specifies which layout to use.

=item 3. The C<index> layout indicates that C<_layout/index.html> should be used.

=item 4. The C<title> configuration is the name of the post/page. It is optional.

=item 5. All of the configurations may be used in the corresponding layout file.

    <!-- Example use of "title" in a layout file -->
    <h1>[% page.title %]</h1>

=back

Files in the source directory that do not start with front matter (images,
PDFs, plain text files and so on) are copied to the output directory as they
are.

A page's content is not run as template code unless the page sets
C<template: true>; layouts always are. C<templates_in_content: true> in
C<_config.yml> restores the behavior of Dapper before 1.0, where all content
and C<_config.yml> values were templates too.

A C<_schema.yml> file in a source directory describes the front matter its
pages must have; see L<App::Dapper::Schema>. YAML and JSON files in C<_data>
are available as C<site.data>.

=item B<_layout/index.html>

Layout files are processed using the template language provided by
L<Template::Alloy> (the Template Toolkit mini-language). The initial layout
file that is given after you run the C<dapper init> command, is this:

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
is available using C<[% page.content %]>.

Definitions specified in the C<_config.yml> file can be referenced under the
"site" namespace (e.g. C<[% site.name %]>). Definitions specified in the
front matter of source files can be referenced under the "page" namespace
(e.g. C<[% page.title %]>).

=item B<_output/index.html>

The output file that is created is a mix of the input file and the layout that
is specified by the input file. For the default site, the following output
file is created:

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

=back

=head2 Variables

The following variables are available in layouts and source files.

=over 4

=item B<site.*>

Everything defined in C<_config.yml>, plus:

    site.time         The time the build started (a DateTime)
    site.pages        Every page, in source path order
    site.categories   A hash of category name to its pages, sorted by date
    site.tags         A hash of tag to its pages, sorted by date
    site.data         The contents of the files in _data
    site.category_pages, site.tag_pages   URLs of generated list pages
    site.source       The resolved source directory
    site.output       The resolved output directory
    site.layout       The resolved layout directory
    site.urlpattern   Default URL pattern (/:category/:year/:month/:slug/)
    site.extension    Default output extension (.html)
    site.ignore       Patterns of top-level files not copied to the output

=item B<page.*>

Everything defined in the page's front matter, plus:

    page.content      The rendered body of the page
    page.excerpt      The first paragraph of a markdown page
    page.url          The URL of the page, relative to the site root
    page.slug         The title, slugified (or the file name if no title)
    page.id           A number unique to the page within a build
    page.date         The page date (front matter, or the file's mtime)
    page.year, page.month, page.day,
    page.hour, page.minute, page.second   Parts of page.date, zero padded
    page.filename     The output file the page is written to
    page.dirname      The directory of page.filename
    page.source_file_extension   The source file's extension (e.g. .md)
    page.seo          Tags for <head>: description, canonical, Open Graph, JSON-LD
    page.markdown_url The URL of the page's Markdown copy, if it has one
    page.posts        On a generated category or tag page: its pages
    paginator         On a paginated page; see App::Dapper::Collections

=back

=head2 URLs and output files

Pages with C<categories> or their own C<urlpattern> are written to the path
their URL describes. The pattern may use C<:category>, C<:year>, C<:month>,
C<:day>, C<:hour>, C<:minute>, C<:second> and C<:slug>. A URL ending in C</>
is written as C<index> plus the page extension inside that directory. Other
pages keep the path of their source file, with the page extension.

=head2 Generated files

After the pages, Dapper writes a sitemap, a feed (if C<feed> is set),
Markdown copies of pages and C<llms.txt> (see L<App::Dapper::Publish>), can
generate category and tag pages and paginate lists (see
L<App::Dapper::Collections>), and can build a search index with Pagefind.
Files that an earlier build wrote and this one did not are removed.

=head2 Options

B<Dapper> provides a number of optional command line switches:

=over 4

=item B<-s>, B<--source>=I<source directory>

Specify the directory containing source files to process. If this command line option is not present, it defaults to the C<source> setting in the config file, or "_source".

=item B<-o>, B<--output>=I<output directory>

Specify the directory to place the output files in. If this command line option is not present, it defaults to the C<output> setting in the config file, or "_output".

=item B<-l>, B<--layout>=I<layout directory>

Specify the directory containing layout files. If this command line option is not present, it defaults to the C<layout> setting in the config file, or "_layout".

=item B<-c>, B<--config>=I<config file>

Specify the config file name to use. If this command line option is not present, it defaults to "_config.yml".

=item B<-p>, B<--port>=I<port>

Specify the port to use for the serve command. Defaults to 8000.

=item B<-q>, B<--quiet>

Only print errors.

=item B<-C>, B<--directory>=I<directory>

Run in this directory instead of the current one.

=item B<-t>, B<--template>=I<name>

For the init command: the starter project to create, C<default> or C<blog>.

=item B<--json>

For the check command: print the report as JSON.

=item B<-h>, B<--help>

Get help on available commands and options.

=item B<-v>, B<--version>

Print the version and exit.

=back

=cut

=head1 METHODS

Dapper may be used directly from a script as well. The following methods are available:

=head2 new

Create a new B<Dapper> object. Example:

    my $d = App::Dapper->new();

Alternatively, the source dir, output dir, layout dir, and configuration file
may be specified. Any of them may be C<undef>, in which case the value from
the configuration file (or the default) is used. Example:

    my $d = App::Dapper->new("_source", "_output", "_layout", "_config.yml");

After creating a B<Dapper> object, the following hash elements may be accessed:

    use App::Dapper;

    my $d = App::Dapper->new();

    print "Source directory: $d->{source}\n";
    print "Output directory: $d->{output}\n";
    print "Layout directory: $d->{layout}\n";
    print "Config file: $d->{config}\n";
    print "Object instantiation time: $d->{site}->{time}\n";

The directories are updated from the configuration file when the site is
built or served. Set C<< $d->{quiet} >> to a true value to suppress progress
messages.

=cut

sub new {
    my $class = shift;
    my ($source, $output, $layout, $config) = @_;

    my $self = {
        created  => 1,
        quiet    => 0,
        explicit => {
            source => defined $source,
            output => defined $output,
            layout => defined $layout,
            config => defined $config,
        },
        source => defined $source ? $source : "_source",
        output => defined $output ? $output : "_output",
        layout => defined $layout ? $layout : "_layout",
        config => defined $config ? $config : "_config.yml",
    };

    bless $self, $class;
    $self->reset_site();
    return $self;
}

=head2 init

Initializes a new skeleton project in the current directory of the calling
script, using the source dir, layout dir and config file given to L</new>.
Nothing is written if any of the files already exist. Example usage:

    use App::Dapper;

    my $d = App::Dapper->new();
    $d->init();

Set C<< $d->{template} >> to C<blog> first for a complete starter blog (see
L<App::Dapper::Init>).

=cut

sub init {
    my ($self) = @_;

    local $App::Dapper::Utils::QUIET = $self->{quiet};

    my $notes = App::Dapper::Init::init(
        $self->{source},
        $self->{output},
        $self->{layout},
        $self->{config},
        $self->{template}
    );

    # Explain the new project to AI coding agents
    for my $file (App::Dapper::Agents::update($self, $notes)) {
        $self->_log("Creating $file");
    }

    $self->_log("Project initialized.");
}

=head2 build

Build the site. Example:

    use App::Dapper;

    my $d = App::Dapper->new();
    $d->build();

When the site is built, it is done in three steps:

1. Parse. In this step, the configuration file is read. In addition, all the source files in the source directory as well as the layout files in the layout directory are read and stored in the site hash.

2. Transform. Combine source and layout files.

3. Render. Save output files to the output directory.

A Dapper object may be built any number of times; each build starts fresh.

=cut

sub build {
    my($self) = @_;

    $self->{problems} = [];
    $self->{written} = {};
    $self->{page_owner} = {};

    $self->parse();
    $self->transform();
    $self->render();

    $self->_log("Project built.");
    return $self;
}

# sub parse - Parse the source directory, config file, and templates.

sub parse {
    my ($self) = @_;

    # load the defaults and the project file, and resolve the directories
    $self->read_project();

    # read the layouts, expanding layouts that are wrapped in other layouts
    $self->read_templates();
}

# sub transform - Walk the source directory and record every page (and every
# file to copy as it is) in the site hash.

sub transform {
    my ($self) = @_;

    die "error: source directory \"$self->{source}\" does not exist\n" unless -d $self->{source};

    $self->{schema_errors} = [];

    # recurse through the source tree, mapping each file to its output path
    $self->walk($self->{source}, $self->{output});

    my @errors = @{$self->{schema_errors}};
    die "error: " . scalar(@errors) . " problem" . (@errors == 1 ? '' : 's') . " with front matter (see the _schema.yml files):\n"
        . join('', map { "  $_\n" } @errors) if @errors;

    # category pages, tag pages and pagination
    $self->attempt($self->{config}, sub { App::Dapper::Collections::generate($self) });
}

# sub render - Combine each page with its layout and write it to the output
# directory, then copy the files that are not pages.

sub render {
    my ($self) = @_;

    # Template::Alloy's built-in json method returns UTF-8 bytes, which would
    # be encoded a second time when the page is written. Give it encoders
    # that return characters instead.
    $Template::Alloy::VMethod::JSON  = JSON->new->allow_nonref->allow_unknown->allow_blessed->convert_blessed->canonical;
    $Template::Alloy::VMethod::JSONP = JSON->new->allow_nonref->allow_unknown->allow_blessed->convert_blessed->canonical->pretty;

    my $tt = Template::Alloy->new({
        INCLUDE_PATH => $self->{layout},
        ANYCASE => 1,
        ENCODING => 'utf8',
        FILTERS => App::Dapper::Filters::filters(),
        EVAL_PERL => $ENV{EVAL_PERL} || 0,
    });

    # Work out what layouts can show about each page before any are rendered
    for my $page (@{$self->{site}->{pages}}) {
        $page->{markdown_url} = App::Dapper::Publish::twin_url($page)
            if App::Dapper::Publish::has_twin($self->{site}, $page);
        $page->{seo} = App::Dapper::Publish::seo($self->{site}, $page);
    }

    for my $page (@{$self->{site}->{pages}}) {
        $self->attempt($page->{source}, sub { $self->render_page($tt, $page) });
    }

    # copy source files that have no front matter (images, etc.) as they are
    for my $file (@{$self->{static_files}}) {
        $self->record_written(App::Dapper::Utils::copy_recursive($file->{source}, $file->{output}));
        $self->_log("Copied $file->{source}");
    }

    # copy additional files and directories
    $self->copy(".", $self->{output});

    # sitemap, feed and llms.txt
    $self->attempt($self->{config}, sub { $self->write_generated() });

    # with live reload on, a new value here tells open pages to reload
    if ($self->{live_reload}) {
        $self->write_output(catfile($self->{output}, '.dapper-reload'), time() . '-' . int(rand(1_000_000)) . "\n");
    }

    # remove what earlier builds wrote that this one did not
    $self->clean_output() unless $self->{collect};

    # search index
    $self->run_search() unless $self->{collect};
}

# sub run_search - With "search: true", run Pagefind (https://pagefind.app) over
# the output directory to build a search index. "search_command" can name a
# different command, such as "npx -y pagefind".

sub run_search {
    my ($self) = @_;

    my $site = $self->{site};
    return unless $site->{search} and App::Dapper::Publish::enabled($site, 'search');

    my @command = defined $site->{search_command} ? split(' ', $site->{search_command}) : ('pagefind');
    my $found = $command[0] =~ m{/} ? -x $command[0] : grep { -x catfile($_, $command[0]) } File::Spec->path();
    if (not $found) {
        $self->problem('warning', $self->{config},
            "search: true needs Pagefind; install it (see https://pagefind.app) or set search_command");
        return;
    }

    $self->_log("Building the search index with @command");
    my @quiet = $self->{quiet} ? ('--quiet') : ();
    system(@command, '--site', $self->{output}, @quiet) == 0
        or $self->problem('warning', $self->{config}, "@command did not finish (exit status " . ($? >> 8) . ")");
}

# sub clean_output - Remove files that an earlier build wrote to the output
# directory but this build did not (the output of a page that was renamed or
# deleted, say). Only files Dapper itself wrote are ever removed: the list is
# kept in .dapper/manifest.json in the project directory. "clean: false" in
# the project file turns this off.

sub clean_output {
    my ($self) = @_;

    return unless App::Dapper::Publish::enabled($self->{site}, 'clean');

    my $manifest_file = catfile('.dapper', 'manifest.json');
    my $output = abs_path($self->{output});
    return unless defined $output;

    my $manifest = {};
    if (-f $manifest_file) {
        $manifest = eval { JSON->new->decode(App::Dapper::Utils::read_file($manifest_file)) } || {};
        $manifest = {} unless ref $manifest eq 'HASH';
    }

    my $old = $manifest->{$output};
    my $removed = 0;
    my %dirs;
    if (ref $old eq 'ARRAY') {
        for my $path (@$old) {
            next if $self->{written}->{$path};
            next if $path =~ m{(?:^|/)\.\.(?:/|$)} or $path =~ m{^/};
            my $file = catfile($self->{output}, $path);
            next unless -f $file;
            unlink $file or next;
            $removed++;
            (my $dir = $path) =~ s{/?[^/]*$}{};
            while (length $dir) {
                $dirs{$dir} = 1;
                $dir =~ s{/?[^/]*$}{};
            }
        }
    }

    # Remove directories the removed files leave empty, deepest first
    for my $dir (sort { length $b <=> length $a } keys %dirs) {
        rmdir catfile($self->{output}, $dir);
    }

    $self->_log("Removed $removed file" . ($removed == 1 ? '' : 's') . " left over from an earlier build") if $removed;

    $manifest->{$output} = [ sort keys %{$self->{written}} ];
    App::Dapper::Utils::write_file($manifest_file, JSON->new->canonical->pretty->encode($manifest));
}

# sub live_reload_script - The script added to pages while "dapper serve" is
# running. It asks for /.dapper-reload every second and reloads the page when
# a new build changes it.

sub live_reload_script {
    return <<'HTML';
<script>
(function () {
  var last = null;
  function poll() {
    fetch('/.dapper-reload?' + Date.now(), { cache: 'no-store' })
      .then(function (r) { return r.ok ? r.text() : last; })
      .then(function (t) { if (last !== null && t !== last) { location.reload(); } last = t; })
      .catch(function () {})
      .then(function () { setTimeout(poll, 1000); });
  }
  poll();
})();
</script>
HTML
}

# sub write_generated - Write the files Dapper makes for the whole site:
# redirects, the sitemap, the feed, and llms.txt and llms-full.txt. A page that writes the
# same file wins, with a warning.

sub write_generated {
    my ($self) = @_;

    my $site  = $self->{site};
    my @pages = @{$site->{pages}};
    my %taken = map { $_->{filename} => 1 } @pages;
    my $has_url = defined $site->{url} && length $site->{url};

    my $write = sub {
        my ($path, $content) = @_;
        my $file = canonpath(catfile($self->{output}, $path));
        if ($taken{$file}) {
            $self->problem('warning', $file, "a page in the source directory already writes $file, so Dapper did not generate one");
            return;
        }
        $self->write_output($file, $content);
        $self->_log("Wrote $file");
    };

    my $redirects = App::Dapper::Publish::redirects($site);
    for my $from (sort keys %$redirects) {
        my $file = canonpath(catfile($self->{output}, App::Dapper::Publish::redirect_path($from)));
        if ($taken{$file}) {
            $self->problem('warning', $file, "a page is still at $from, so the redirect from it to $redirects->{$from} was not written");
            next;
        }
        $self->write_output($file, App::Dapper::Publish::redirect_page($site, $redirects->{$from}));
        $self->{page_owner}->{$file} = "the redirect from $from";
        $taken{$file} = 1;
    }

    if (App::Dapper::Publish::enabled($site, 'llms_txt')) {
        my @twins = grep { $_->{markdown_url} } @pages;
        if (@twins) {
            $write->('llms.txt', App::Dapper::Publish::llms_txt($site, \@twins));
            $write->('llms-full.txt', App::Dapper::Publish::llms_full_txt($site, \@twins));
        }
    }

    if (App::Dapper::Publish::enabled($site, 'sitemap')) {
        if ($has_url) {
            $write->('sitemap.xml', App::Dapper::Publish::sitemap($site, \@pages));
        }
        elsif ($self->{configured}->{sitemap}) {
            $self->problem('warning', $self->{config}, "the sitemap needs the site's address; set url in $self->{config}");
        }
    }

    if (my $settings = App::Dapper::Publish::feed_settings($site)) {
        if ($has_url) {
            my $pages = App::Dapper::Publish::feed_pages($site, $settings);
            $write->($settings->{path}, App::Dapper::Publish::feed($site, $settings, $pages));
        }
        else {
            $self->problem('warning', $self->{config}, "the feed needs the site's address; set url in $self->{config}");
        }
    }
}

# sub render_page - Render one page with its layout and write it to disk.
#
# Layouts are always processed as templates. The page's content is processed
# as a template only if the page sets "template: true". With
# "templates_in_content: true" in the project file, Dapper instead works as it
# did before 1.0: the layout is rendered, and then the result is rendered a
# second time, so that template code in content and in site variables runs.

sub render_page {
    my ($self, $tt, $page) = @_;

    $page->{layout} = "index" unless $page->{layout};

    my $layout = $self->{layout_content}->{$page->{layout}};
    die "error: $page->{source} uses the layout \"$page->{layout}\", but there is no such file in $self->{layout}\n"
        unless defined $layout;

    my %vars = (
        site      => $self->{site},
        page      => $page,
        paginator => $page->{paginator},
    );

    my $output;

    if ($self->{site}->{templates_in_content}) {
        my $first;
        $tt->process(\$layout, \%vars, \$first)
            || die "error: could not process $page->{source} with layout $page->{layout}: " . $tt->error() . "\n";
        $tt->process(\$first, \%vars, \$output)
            || die "error: could not process $page->{source} with layout $page->{layout} (2nd pass): " . $tt->error() . "\n";
    }
    else {
        if ($page->{template}) {
            my $content;
            $tt->process(\$page->{content}, \%vars, \$content)
                || die "error: could not process the content of $page->{source}: " . $tt->error() . "\n";
            $page->{content} = $content;
        }
        $tt->process(\$layout, \%vars, \$output)
            || die "error: could not process $page->{source} with layout $page->{layout}: " . $tt->error() . "\n";
    }

    if ($self->{live_reload} and App::Dapper::Publish::is_html($page)) {
        my $script = live_reload_script();
        $output =~ s{(</body>)}{$script$1}i or $output .= $script;
    }

    my $owner = $self->{page_owner}->{$page->{filename}};
    die "error: $page->{source} and $owner both write $page->{filename}\n" if defined $owner;
    $self->{page_owner}->{$page->{filename}} = $page->{source};

    $self->write_output($page->{filename}, $output);
    $self->_log("Wrote $page->{filename}");

    if ($page->{markdown_url}) {
        my $twin = App::Dapper::Publish::twin_path($page);
        $self->write_output($twin, App::Dapper::Publish::twin($self->{site}, $page));
        $self->_log("Wrote $twin");
    }
}

# sub write_output - Write a file to the output directory and remember that
# Dapper wrote it.

sub write_output {
    my ($self, $filename, $content) = @_;

    App::Dapper::Utils::write_file($filename, $content);
    $self->record_written($filename);
}

# sub record_written - Remember files written to the output directory, so that
# files left over from earlier builds can be found.

sub record_written {
    my ($self, @files) = @_;

    for my $file (@files) {
        my $relative = File::Spec->abs2rel($file, $self->{output});
        $self->{written}->{ join('/', File::Spec->splitdir($relative)) } = 1;
    }
}

# sub attempt - Run a step of the build for a file. Normally an error stops the
# build. When collecting problems (as "dapper check" does), the error is
# recorded and the build carries on.

sub attempt {
    my ($self, $file, $code) = @_;

    return $code->() unless $self->{collect};

    eval { $code->(); 1 } or $self->problem('error', $file, $@);
}

# sub problem - Record a problem found during the build. Errors stop the build
# unless problems are being collected; warnings are printed.

sub problem {
    my ($self, $severity, $file, $message) = @_;

    $message =~ s/^(?:error|warning): //;
    $message =~ s/\s+\z//;

    if ($self->{collect}) {
        push @{$self->{problems}}, { severity => $severity, file => $file, message => $message };
        return;
    }

    die "error: $message\n" if $severity eq 'error';
    warn "warning: $message\n";
}

=head2 check

Build the site into a temporary directory and return a report of every
problem found, without touching the output directory. See
L<App::Dapper::Check>.

    my $report = $d->check();
    print "ok\n" if $report->{ok};

=cut

sub check {
    my ($self) = @_;
    return App::Dapper::Check::run($self);
}

=head2 agents

Write or update C<AGENTS.md> (and a C<CLAUDE.md> if there isn't one), which
explains the project to AI coding agents. See L<App::Dapper::Agents>.

=cut

sub agents {
    my ($self) = @_;
    for my $file (App::Dapper::Agents::update($self)) {
        $self->_log("Wrote $file");
    }
}

=head2 mcp

Run a Model Context Protocol server on standard input and output, so that AI
assistants can read, write, build and check the site. See
L<App::Dapper::MCP>.

=cut

sub mcp {
    my ($self) = @_;
    App::Dapper::MCP::serve($self);
}

=head2 serve

Serve the site locally. Pass in the port number. The port number will be used
to serve the site contents from the output directory like this:
http://localhost:<port>. Here is an example, using the default port 8000:

    use App::Dapper;

    my $d = App::Dapper->new();
    $d->serve("8000");

The following is equivalent:

    $d->serve();

This method only serves what is already in the output directory (as read from
the project file, if there is one); it does not build the site. The C<dapper
serve> command builds and watches the site in a separate process while it
serves.

=cut

sub serve {
    my($self, $port) = @_;

    require Net::HTTPServer;

    $port = $DEFAULT_PORT unless $port;

    $self->read_project(1);

    print "Starting webserver at http://localhost:$port\n";

    my $s = Net::HTTPServer->new(
                    port=>$port,
                    docroot=>$self->{output},
                    type=>"forking",
                    log=>"STDOUT",
                    );
    $s->Start() or die "error: could not start the webserver on port $port\n";
    $s->Process();
}

=head2 watch

Build the site, then rebuild it whenever a file in the project changes, is
added, or is removed. The output directory and dot files are not watched.
Errors in a rebuild are reported without stopping the watch. Pass the
polling interval in seconds (default: 1).

    $d->watch();

=cut

sub watch {
    my ($self, $interval) = @_;

    $interval = 1 unless $interval;

    my $previous;
    while (1) {
        my $current = $self->snapshot();
        if (not defined $previous or not _same_snapshot($previous, $current)) {
            eval { $self->build(); 1 } or warn $@;
            $previous = $self->snapshot();
        }
        sleep $interval;
    }
}

=head2 snapshot

Returns a hash reference of every watched file in the project mapped to its
modification time and size. Used by L</watch> to detect changes.

=cut

sub snapshot {
    my ($self) = @_;

    my $output = abs_path($self->{output});
    my %files;

    File::Find::find({
        no_chdir => 1,
        wanted   => sub {
            my $path = $File::Find::name;
            my $name = basename($path);

            if (-d $path) {
                return if $path eq '.';
                my $abs = abs_path($path);
                $File::Find::prune = 1
                    if $name =~ /^\./ or (defined $output and defined $abs and $abs eq $output);
                return;
            }

            return if $name =~ /^\./;
            my @stat = stat $path;
            $files{$path} = "$stat[9]:$stat[7]" if @stat;
        },
    }, '.');

    return \%files;
}

sub _same_snapshot {
    my ($old, $new) = @_;

    return 0 unless keys %$old == keys %$new;
    for my $key (keys %$old) {
        return 0 unless defined $new->{$key} and $new->{$key} eq $old->{$key};
    }
    return 1;
}

# sub reset_site - Start a fresh site hash from the defaults.

sub reset_site {
    my ($self) = @_;

    $self->{site} = App::Dapper::Defaults::get_defaults();
    $self->{site}->{time} = App::Dapper::Utils::parse_date(
        DateTime->now( time_zone => DateTime::TimeZone->new( name => 'local' ) ));
    $self->{site}->{pages} = [];
    $self->{site}->{categories} = {};
    $self->{site}->{tags} = {};
    $self->{layout_content} = {};
    $self->{static_files} = [];
    $self->{id} = 0;
}

# sub read_project - Read the project file and resolve the source, output and
# layout directories. Precedence: values passed to new() (the command line),
# then the project file, then the defaults. Pass a true value to allow the
# project file to be missing.

sub read_project {
    my ($self, $optional) = @_;

    $self->reset_site();
    $self->{configured} = {};

    if (-f $self->{config}) {
        my $config = eval { LoadFile($self->{config}) };
        die "error: could not parse \"$self->{config}\": $@" if $@;

        $config = {} unless defined $config;
        die "error: \"$self->{config}\" must contain key: value pairs\n" unless ref $config eq 'HASH';

        # Settings in the project file override the defaults
        @{$self->{site}}{keys %{$config}} = values %$config;
        $self->{configured} = { map { $_ => 1 } keys %$config };
    }
    elsif (not $optional) {
        die "error: could not find the project file \"$self->{config}\". Run \"dapper init\" to create a new project.\n";
    }

    for my $key (qw/ source output layout /) {
        my $value = $self->{explicit}->{$key} ? $self->{$key} : $self->{site}->{$key};
        die "error: \"$key\" must be defined in project file\n" unless defined $value and length $value;
        $value = canonpath($value);
        $self->{$key} = $value;
        $self->{site}->{$key} = $value;
    }

    $self->{site}->{pages} = [];
    $self->{site}->{categories} = {};
    $self->{site}->{tags} = {};

    $self->{data_dir} = canonpath($self->{site}->{data_dir});
    $self->{site}->{data} = -d $self->{data_dir} ? read_data($self->{data_dir}) : {};
}

# sub read_data(dir) - Read every YAML (.yml, .yaml) and JSON (.json) file in a
# directory into a hash keyed by file name without the extension, so that
# _data/authors.yml is available as site.data.authors. Directories become
# nested hashes: _data/menus/main.yml is site.data.menus.main.

sub read_data {
    my ($dir) = @_;

    my %data;

    my @entries = grep { !/^\./ } App::Dapper::Utils::read_dir($dir);

    for my $entry (@entries) {
        my $path = "$dir/$entry";
        if (-d $path) {
            $data{$entry} = read_data($path);
        }
        elsif ($entry =~ /^(.+)\.(?:ya?ml)$/i) {
            my $value = eval { LoadFile($path) };
            die "error: could not parse the data file \"$path\": $@" if $@;
            $data{$1} = $value;
        }
        elsif ($entry =~ /^(.+)\.json$/i) {
            my $value = eval { JSON->new->decode(App::Dapper::Utils::read_file($path)) };
            die "error: could not parse the data file \"$path\": $@" if $@;
            $data{$1} = $value;
        }
    }

    return \%data;
}

# sub read_templates - Read the content of the layouts in the layout directory
# and expand layouts that name a parent layout in their front matter.

sub read_templates {
    my ($self) = @_;

    my %raw;

    die "error: could not open layout directory \"$self->{layout}\"\n" unless -d $self->{layout};
    my @files = grep { !/^\./ } App::Dapper::Utils::read_dir($self->{layout});

    for my $file (@files) {
        my $path = "$self->{layout}/$file";
        next unless -f $path;
        $raw{App::Dapper::Utils::filter_stem($file)} = App::Dapper::Utils::read_file($path);
    }

    $self->{layout_content} = {};
    for my $key (keys %raw) {
        $self->{layout_content}->{$key} = $self->expand_layout($key, \%raw, {});
    }
}

# sub expand_layout - Return the content of a layout with its chain of parent
# layouts applied, so that a layout may be wrapped by another layout, which
# may in turn be wrapped by another.

sub expand_layout {
    my ($self, $name, $raw, $seen) = @_;

    die "error: layout \"$name\" is part of a loop of layouts\n" if $seen->{$name};

    my ($frontmatter, $content) =
        App::Dapper::Utils::split_frontmatter($raw->{$name}, "$self->{layout}/$name");

    return $raw->{$name} unless defined $frontmatter;

    my $parent = $frontmatter->{layout};
    return $content unless defined $parent;

    if (not exists $raw->{$parent}) {
        warn "warning: layout \"$name\" names the layout \"$parent\", which does not exist\n";
        return $content;
    }

    my $master = $self->expand_layout($parent, $raw, { %$seen, $name => 1 });
    $master =~ s/\[%[-+=~]?\s*page\.content\s*[-+=~]?%\]/$content/g;

    return $master;
}

# sub walk - Walk the source directory in sorted order, passing each file and
# its output path to build_inventory. Dot files and directories are skipped.

sub walk {
    my ($self, $source_dir, $output_dir, $schema) = @_;

    die "error: could not open source directory \"$source_dir\"\n" unless -d $source_dir;
    my @entries = grep { !/^\./ } App::Dapper::Utils::read_dir($source_dir);

    # A _schema.yml applies to this directory and those below it, unless they
    # have a schema of their own
    my $schema_file = "$source_dir/_schema.yml";
    if (-f $schema_file) {
        $self->attempt($schema_file, sub { $schema = App::Dapper::Schema::load($schema_file) });
    }

    for my $entry (@entries) {
        next if $entry eq '_schema.yml';

        my $source = "$source_dir/$entry";
        my $output = "$output_dir/$entry";

        if (-d $source) {
            $self->walk($source, $output, $schema);
        }
        elsif (-f $source) {
            $self->attempt($source, sub { $self->build_inventory($source, $output, $schema) });
        }
    }
}

# sub build_inventory - Read one source file and add it to the site hash as a
# page, working out its date, slug, URL and output file. A file without front
# matter is recorded to be copied as it is instead.

sub build_inventory {
    my ($self, $source_file_name, $destination_file_name, $schema) = @_;

    # Files without front matter (images, PDFs, etc.) are copied as they are
    if (not App::Dapper::Utils::has_frontmatter($source_file_name)) {
        push @{$self->{static_files}}, { source => $source_file_name, output => $destination_file_name };
        return;
    }

    $self->_log("Processing $source_file_name");

    my $source_content = App::Dapper::Utils::read_file($source_file_name);

    my ($frontmatter, $content) =
        App::Dapper::Utils::split_frontmatter($source_content, $source_file_name);
    die "error: \"$source_file_name\" has front matter that is never closed with a line containing ---\n"
        unless defined $frontmatter;

    # A page that does not match its schema is reported and goes no further
    if ($schema) {
        my @messages = App::Dapper::Schema::validate($schema, $frontmatter);
        for my $message (@messages) {
            if ($self->{collect}) {
                $self->problem('error', $source_file_name, "$message (see $schema->{file})");
            }
            else {
                push @{$self->{schema_errors}}, "$source_file_name: $message";
            }
        }
        return if @messages;
    }

    my %page = %$frontmatter;
    $page{content} = $content;
    $page{source} = $source_file_name;

    my @categories = ref $page{categories} eq 'ARRAY' ? @{$page{categories}}
                   : defined $page{categories}        ? ($page{categories})
                   : ();
    @categories = grep { defined and length } @categories;

    $page{slug} = App::Dapper::Utils::slugify($page{title});
    if (not defined $page{slug} or not length $page{slug}) {
        $page{slug} = App::Dapper::Utils::slugify(basename(App::Dapper::Utils::filter_stem($source_file_name)));
    }

    my $date = App::Dapper::Utils::parse_date(
        defined $page{date} ? $page{date} : App::Dapper::Utils::get_modified_time($source_file_name),
        $source_file_name);

    # A date written without a time zone is in the page's time zone: its
    # "timezone" setting, the site's, or the local time zone
    my $zone = $page{timezone} || $self->{site}->{timezone} || 'local';
    my $timezone = ref $zone ? $zone : eval { DateTime::TimeZone->new( name => $zone ) }
        or die "error: unknown time zone \"$zone\" in \"$source_file_name\"\n";
    $date->set_time_zone($timezone) if $date->time_zone->is_floating;
    $page{timezone} = $timezone;

    $page{date}   = $date;
    $page{year}   = $date->year();
    $page{month}  = $date->month();
    $page{day}    = $date->day();
    $page{hour}   = $date->hour();
    $page{minute} = $date->minute();
    $page{second} = $date->second();

    # Insert zero to beginning if year, month, day,
    # hour, minute or second is less than 10
    $page{$_} < 10 and $page{$_} = '0' . $page{$_}
      for ('year', 'month', 'day', 'hour', 'minute', 'second');

    $page{id} = ++$self->{id};

    if (not defined $page{extension}) { $page{extension} = $self->{site}->{extension}; }
    $page{extension} = '' unless defined $page{extension};

    $page{source_file_extension} = App::Dapper::Utils::filter_extension($source_file_name);
    $page{source_file_extension} = '' unless defined $page{source_file_extension};

    if (@categories or defined $page{urlpattern}) {
        # The URL decides where the page is written
        my $pattern = defined $page{urlpattern} ? $page{urlpattern} : $self->{site}->{urlpattern};
        $page{url} = expand_urlpattern($pattern, { %page, category => $categories[0] });

        my $filename = $page{url};
        $filename .= "index$page{extension}" if $filename =~ m{/$};
        $page{filename} = canonpath(catfile($self->{output}, $filename));
    }
    else {
        # The path of the source file decides where the page is written
        $page{filename} = canonpath(App::Dapper::Utils::filter_stem($destination_file_name) . $page{extension});

        my $url = File::Spec->abs2rel($page{filename}, $self->{output});
        $url = join('/', File::Spec->splitdir($url));
        $url =~ s{(^|/)index\Q$page{extension}\E$}{$1} if length $page{extension};
        $page{url} = "/$url";
    }

    my ($volume, $dirname, $file) = File::Spec->splitpath( $page{filename} );
    $page{dirname} = $dirname;

    if ($page{source_file_extension} eq ".md") {
        $page{markdown} = $page{content};
        $page{content} = App::Dapper::Markdown::to_html($page{content});

        # Save first paragraph of content as excerpt
        $page{excerpt} = $1 if $page{content} =~ /(<p>.*?<\/p>)/s;
    }

    # Remove leading spaces and newline
    $page{content} =~ s/^[ \n]*//;

    for my $category (@categories) {
        my $list = $self->{site}->{categories}->{$category} ||= [];
        push @$list, \%page;

        # Keep the array sorted
        @$list = sort { $a->{date} <=> $b->{date} } @$list;
    }

    my @tags = ref $page{tags} eq 'ARRAY' ? @{$page{tags}}
             : defined $page{tags}        ? ($page{tags})
             : ();
    for my $tag (grep { defined and !ref and length } @tags) {
        my $list = $self->{site}->{tags}->{$tag} ||= [];
        push @$list, \%page;
        @$list = sort { $a->{date} <=> $b->{date} } @$list;
    }

    push @{$self->{site}->{pages}}, \%page;
}

=head2 expand_urlpattern

Takes a URL pattern (e.g. C</:category/:year/:month/:slug/>) and a hash of page
values, and returns the URL with each C<:name> token replaced. The tokens are
C<:category>, C<:tag>, C<:year>, C<:month>, C<:day>, C<:hour>, C<:minute>,
C<:second> and C<:slug>. Tokens with no
value are removed along with their slash.

=cut

sub expand_urlpattern {
    my ($pattern, $page) = @_;

    my $url = defined $pattern ? $pattern : '';
    for my $token (qw/ category tag year month day hour minute second slug /) {
        my $value = $page->{$token};
        $value = '' unless defined $value;
        $url =~ s/:$token\b/$value/g;
    }

    $url =~ s{/{2,}}{/}g;
    $url = "/$url" unless $url =~ m{^/};

    return $url;
}

# sub copy(sourcedir, outputdir) - Copy the files and directories in <sourcedir>
# to <outputdir>, except those whose names match a pattern in
# $self->{site}->{ignore}. The source, output and layout directories and the
# project file are never copied.

sub copy {
    my ($self, $dir, $output) = @_;

    my @skip = map { abs_path($_) } grep { -e $_ }
        ($self->{source}, $self->{output}, $self->{layout}, $self->{config}, $self->{data_dir});
    my %skip = map { $_ => 1 } grep { defined } @skip;

    ENTRY: for my $file (App::Dapper::Utils::read_dir($dir)) {

        for my $i (@{ $self->{site}->{ignore} || [] }) {
            next ENTRY if ($file =~ m/$i/);
        }

        my $path = $dir eq '.' ? $file : "$dir/$file";
        my $abs = abs_path($path);
        next if defined $abs and $skip{$abs};

        $self->record_written(App::Dapper::Utils::copy_recursive($path, catfile($output, $file), $self->{output}));
        $self->_log("Copied $path");
    }
}

# sub _log - Print a progress message unless quiet.

sub _log {
    my ($self, $message) = @_;

    print "$message\n" unless $self->{quiet};
}

=head1 AUTHOR

Mark Benson, C<< <mark at jayber.org> >>

=head1 BUGS

Please report any bugs or feature requests at
L<https://github.com/markdbenson/dapper/issues>.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc App::Dapper

You can also look for information at:

=over 4

=item * GitHub: source code and issue tracker

L<https://github.com/markdbenson/dapper>

=item * MetaCPAN

L<https://metacpan.org/dist/App-Dapper>

=back

=head1 LICENSE AND COPYRIGHT

The MIT License (MIT)

Copyright (c) 2002-2026 Mark Benson

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

=cut

1; # End of App::Dapper
