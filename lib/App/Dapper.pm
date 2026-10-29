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

use Text::MultiMarkdown 'markdown';

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

Version 0.22

=cut

our $VERSION = '0.22';

our @EXPORT = qw($VERSION);

=head1 SYNOPSIS

B<Dapper> allows you to transform simple text files into static websites. By installing the App::Dapper Perl module, an executable named C<dapper> will be available to you in your terminal window. You can use this executable in a number of ways:

    # Initialize the current directory with a fresh skeleton of a site
    $ dapper [-solc] init

    # Build the site
    $ dapper [-solc] build

    # Serve the site locally at http://localhost:8000
    $ dapper [-solcp] serve

    # Rebuild the site if anything (source, layout dirs; config file) changes
    $ dapper [-solc] watch

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

=back

=head2 URLs and output files

Pages with C<categories> or their own C<urlpattern> are written to the path
their URL describes. The pattern may use C<:category>, C<:year>, C<:month>,
C<:day>, C<:hour>, C<:minute>, C<:second> and C<:slug>. A URL ending in C</>
is written as C<index> plus the page extension inside that directory. Other
pages keep the path of their source file, with the page extension.

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

Initializes a new skeleton project in the current directory (of the calling script, and uses the defined source dir, output dir, layout dir, and config file. Example usage:

    use App::Dapper;

    my $d = App::Dapper->new();
    $d->init();

=cut

sub init {
    my ($self) = @_;

    App::Dapper::Init::init(
        $self->{source},
        $self->{output},
        $self->{layout},
        $self->{config}
    );

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

    $self->parse();
    $self->transform();
    $self->render();

    $self->_log("Project built.");
}

# sub parse - Parse the source directory, config file, and templates.

sub parse {
    my ($self) = @_;

    # load program and project configuration
    $self->read_project();

    # replaces the values of h_template with actual content
    $self->read_templates();
}

# sub transform - Walk the source and output directories and transform the text into the output files.

sub transform {
    my ($self) = @_;

    die "error: source directory \"$self->{source}\" does not exist\n" unless -d $self->{source};

    # recurse through the project tree and generate output (combine src with templates)
    $self->walk($self->{source}, $self->{output});
}

# sub render - Render the internal hash of source files, config file, and layouts into the actual output files on disk.

sub render {
    my ($self) = @_;

    my $tt = Template::Alloy->new({
        INCLUDE_PATH => $self->{layout},
        ANYCASE => 1,
        ENCODING => 'utf8',
        FILTERS => App::Dapper::Filters::filters(),
        EVAL_PERL => $ENV{EVAL_PERL} || 0,
    });

    for my $page (@{$self->{site}->{pages}}) {

        if (not $page->{layout}) {
            $page->{layout} = "index";
        }

        my $layout = $self->{layout_content}->{$page->{layout}};
        die "error: $page->{source} uses the layout \"$page->{layout}\", but there is no such file in $self->{layout}\n"
            unless defined $layout;

        my %tags = ();
        $tags{site} = $self->{site};
        $tags{page} = $page;

        my $destination1;

        $tt->process(\$layout, \%tags, \$destination1)
            || die "error: could not process $page->{source} with layout $page->{layout}: " . $tt->error() . "\n";

        # Parse and render once more to make sure that any template statements
        # in the source file (and in site variables) also get rendered
        my $destination;

        $tt->process(\$destination1, \%tags, \$destination)
            || die "error: could not process $page->{source} with layout $page->{layout} (2nd pass): " . $tt->error() . "\n";

        App::Dapper::Utils::write_file($page->{filename}, $destination);
        $self->_log("Wrote $page->{filename}");
    }

    # copy source files that have no front matter (images, etc.) as they are
    for my $file (@{$self->{static_files}}) {
        App::Dapper::Utils::copy_recursive($file->{source}, $file->{output});
        $self->_log("Copied $file->{source}");
    }

    # copy additional files and directories
    $self->copy(".", $self->{output});
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

    if (-f $self->{config}) {
        my $config = eval { LoadFile($self->{config}) };
        die "error: could not parse \"$self->{config}\": $@" if $@;

        $config = {} unless defined $config;
        die "error: \"$self->{config}\" must contain key: value pairs\n" unless ref $config eq 'HASH';

        # Graft together
        @{$self->{site}}{keys %{$config}} = values %$config;
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
}

# sub read_templates - Read the content of the layouts in the layout directory
# and expand layouts that name a parent layout in their front matter.

sub read_templates {
    my ($self) = @_;

    my %raw;

    opendir(my $dh, $self->{layout})
        or die "error: could not open layout directory \"$self->{layout}\": $!\n";
    my @files = sort grep { !/^\./ } readdir($dh);
    closedir($dh);

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

# sub walk - Walk the source directory and output directory and build the site hash.

sub walk {
    my ($self, $source_dir, $output_dir) = @_;

    opendir(my $dh, $source_dir)
        or die "error: could not open source directory \"$source_dir\": $!\n";
    my @entries = sort grep { !/^\./ } readdir($dh);
    closedir($dh);

    for my $entry (@entries) {
        my $source = "$source_dir/$entry";
        my $output = "$output_dir/$entry";

        if (-d $source) {
            $self->walk($source, $output);
        }
        elsif (-f $source) {
            $self->build_inventory($source, $output);
        }
    }
}

# sub build_inventory - Build the internal hash of files, configurations, and layouts.

sub build_inventory {
    my ($self, $source_file_name, $destination_file_name) = @_;

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

    if(not $page{timezone}) {
        $page{timezone} = DateTime::TimeZone->new( name => 'local' );
    }

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
        $page{content} = markdown($page{content});

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

    push @{$self->{site}->{pages}}, \%page;
}

=head2 expand_urlpattern

Takes a URL pattern (e.g. C</:category/:year/:month/:slug/>) and a hash of page
values, and returns the URL with each C<:name> token replaced. Tokens with no
value are removed along with their slash.

=cut

sub expand_urlpattern {
    my ($pattern, $page) = @_;

    my $url = defined $pattern ? $pattern : '';
    for my $token (qw/ category year month day hour minute second slug /) {
        my $value = $page->{$token};
        $value = '' unless defined $value;
        $url =~ s/:$token\b/$value/g;
    }

    $url =~ s{/{2,}}{/}g;
    $url = "/$url" unless $url =~ m{^/};

    return $url;
}

# sub copy(sourcedir, outputdir) - Copies files and directories from <sourcedir> to <outputdir> as long as they do not match what is contained in $self->{site}->{ignore}. The source, output and layout directories and the project file are never copied.

sub copy {
    my ($self, $dir, $output) = @_;

    my @skip = map { abs_path($_) } grep { -e $_ }
        ($self->{source}, $self->{output}, $self->{layout}, $self->{config});
    my %skip = map { $_ => 1 } grep { defined } @skip;

    opendir(my $dh, $dir) or die "error: could not open \"$dir\": $!\n";
    my @entries = sort readdir($dh);
    closedir($dh);

    ENTRY: for my $file (@entries) {
        next if $file eq '.' or $file eq '..';

        for my $i (@{ $self->{site}->{ignore} || [] }) {
            next ENTRY if ($file =~ m/$i/);
        }

        my $path = $dir eq '.' ? $file : "$dir/$file";
        my $abs = abs_path($path);
        next if defined $abs and $skip{$abs};

        App::Dapper::Utils::copy_recursive($path, catfile($output, $file), $self->{output});
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
