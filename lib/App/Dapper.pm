package App::Dapper;

=head1 NAME

App::Dapper - A publishing tool for static websites.

=cut

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.8.0;
use strict;
use warnings FATAL => 'all';

use vars '$VERSION';

use Exporter qw(import);
use IO::Dir;

#use Template;
use Template::Alloy;
use Template::Constants qw( :debug );

use Text::MultiMarkdown 'markdown';
use HTTP::Server::Brick;
use YAML::Tiny qw(LoadFile Load Dump);
use File::Spec::Functions qw/ canonpath /;
use File::Path qw(make_path);

use Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Sortkeys = 1;

use DateTime;

use App::Dapper::Init;
use App::Dapper::Utils;
use App::Dapper::Defaults;
use App::Dapper::Filters;

my $DEFAULT_PORT = 8000;
my $ID = 0;

=head1 VERSION

Version 0.18

=cut

our $VERSION = '0.18';

our @EXPORT = qw($VERSION);

=head1 SYNOPSIS

B<Dapper> allows you to transform simple text files into static websites. By installing the App::Dapper Perl module, an executable named C<dapper> will be available to you in your terminal window. You can use this executable in a number of ways:

    # Initialize the current directory with a fresh skeleton of a site
    $ dapper [-solc] init

    # Build the site
    $ dapper [-solc] build

    # Serve the site locally at http://localhost:8000
    $ dapper [-solc] serve

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

All of the configurations in this file are available in layout templates,
based on the Liquid template system. For instance, C<name> in the
configuration file may be used in a template as follows:

    {{ site.name }}

=item B<_source/index.md>

A sample markdown file is available in the _source directory. Contents:

    ---
    layout: index
    title: Welcome
    ---

    Hello world.

There are a few things to note about this file:

=over 4

=item 1. There is a YAML configuration block at the start of the file.

=item 2. The I<layout> configuration specifies which layout to use.

=item 3. The C<index> layout indicates that C<_layout/index.html> should be used.

=item 4. The C<title> configuration is the name of the post/page. It is optional.

=item 5. All of the configurations may be used in the corresponding layout file.

    <!-- Example use of "name" in a layout file -->
    <h1>{{ page.name }}</h1>

=back

=item B<_layout/index.html>

Layout files are processed using the Liquid template system. The initial layout
file that is given after you run the C<dapper init> command, is this:

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
is available using C<{{ page.content }}>.

Definitions specified in the C<_config.yml> file can be referenced under the
"site" namespace (e.g. {{ site.name }}. Definitions specified in the YAML
portion of text files can be referenced under the "page" namespace (e.g.
{{ page.title }}.

=item B<_output/index.html>

The output file that is created is a mix of the input file and the layout that
is specified by the input file. For the default site, the following output
file is created:

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

=back

B<Dapper> provides a number of optional command line switches:

=head2 Options

=over 4

=item B<-s>, B<--source>=I<source directory>

Specify the directory containing source files to process. If this command line option is not present, it defaults to "_source".

=item B<-o>, B<--output>=I<output directory>

Specify the directory to place the output files in. If this command line option is not present, it defaults to "_output".

=item B<-l>, B<--layout>=I<layout directory>

Specify the directory containing source files to process. If this command line option is not present, it defaults to "_layout".

=item B<-h>

Get help on available commands and options.

=item B<-v>

Print the version and exit.

=back

=cut

=head1 METHODS

Dapper may be used directly from a script as well. The following methods are available:

=head2 new

Create a new B<Dapper> object. Example:

    my $d = App::Dapper->new();

Alternatively, the source dir, output dir, layout dir, and configuration file
may be specified. Example:

    my $d = App::Dapper->new("_source", "_output", "_layout", "_config.yml");

After creating a B<Dapper> object, the followin hash elements may be accessed:

    use App::Dapper;

    my $d = App::Dapper->new();

    print "Source directory: $d->{source}\n";
    print "Output directory: $d->{output}\n";
    print "Layout directory: $d->{layout}\n";
    print "Config file: $d->{config}\n";
    print "Object instantiation time: $d->{site}->{time}\n";

=cut

sub new {
    my $class = shift;
    my $self = {
        created=> 1,
        source => shift,
        output => shift,
        layout => shift,
        config => shift,
    };

    $self->{site} = App::Dapper::Defaults::get_defaults();
    $self->{site}->{time} = DateTime->now( time_zone => DateTime::TimeZone->new( name => 'local' ) );
    $self->{source} = "_source" unless defined($self->{source});
    $self->{output} = "_output" unless defined($self->{output});
    $self->{layout} = "_layout" unless defined($self->{layout});
    $self->{config} = "_config.yml" unless defined($self->{config});

    bless $self, $class;
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

    print "Project initialized.\n";
}

=head2 build

Build the site. Example:

    use App::Dapper;
    
    my $d = App::Dapper->new();
    $d->build();

When the site is built, it is done in three steps:

1. Parse. In this step, the configuration file is read. In addition, all the source files in the source directory as well as the layout files in the layout directory are reach and stored in the site hash.
 
2. Transform. Combine source and layout files.

3. Render. Save output files to the output directory.

=cut

sub build {
    my($self) = @_;
   
    $ID = 0; 

    $self->parse();
    $self->transform();
    $self->render();

    print "Project built.\n";
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
        #STRICT => 1,
        FILTERS => {
            'xml_escape' => \&App::Dapper::Filters::xml_escape,
            'date_to_xmlschema' => \&App::Dapper::Filters::date_to_xmlschema,
            'replace_last' => \&App::Dapper::Filters::replace_last,
            'smart' => \&App::Dapper::Filters::smart,
            'json' => \&App::Dapper::Filters::json,
        },
        #ERROR => 'alloy_errors.html', 
        #DEBUG => DEBUG_ALL,
    }) || die "$Template::ERROR\n";        

    for my $page (@{$self->{site}->{pages}}) {

        #print Dump $page->{content};

        if (not $page->{layout}) {
            $page->{layout} = "index";
            #print "WARNING: $page->{filename} does not have a page layout assigned: $page->{layout}.\n";
        }

        my $layout = $self->{layout_content}->{$page->{layout}};

        my %tags = ();
        $tags{site} = $self->{site};
        $tags{page} = $page;
        #$tags{page}->{content} = $content;

        my $destination1;

        $tt->process(\$layout, \%tags, \$destination1)
            || die "Error processing $tags{page}->{filename} with $page->{layout}:" . $tt->error() . "\n";

        #if ($page->{layout} ne "index" and $layout =~ m/circuits/) {
        #    print "DANGER WILL ROBINSON ";
        #    print "PROCESSED: $tags{page}->{filename} with $page->{layout}\n\n$layout\n\n\n";
        #}

        # Parse and render once more to make sure that any liquid statments
        # In the source file also gets rendered
        my $destination;

        $tt->process(\$destination1, \%tags, \$destination)
            || die "Error processing (2nd pass) $tags{page}->{filename} with $page->{layout}:" . $tt->error() . "\n";

        if ($page->{filename}) {
            make_path($page->{dirname}, { verbose => 1 });
            open(DESTINATION, ">$page->{filename}") or die "error: could not open destination file:$page->{filename}: $!\n";
            print(DESTINATION $destination) or die "error: could not print to $page->{filename}: $!\n";
            close(DESTINATION) or die "error: could not close $page->{filename}: $!\n";

            print "Wrote $page->{filename}\n";
        }
        else {
            print Dumper "No filename specified\n";
        }
    }

    #print Dumper $self->{site};

    #print Dumper($self->{site}); 
    # copy additional files and directories
    $self->copy(".", $self->{output});
}

# sub serve - Serve the site locally. Pass in the port number. The port number will be used to serve the site contents from the output directory like this: http://localhost:<port>. Here is an example, using the default port 8000:
# 
#    use App::Dapper;
#
#    my $d = App::Dapper->new();
#    $d->serve("8000");
#
# The following is equivalent:
#
#    $d->serve();

sub serve {
    my($self, $port) = @_;

    $port = $DEFAULT_PORT unless $port;

    my $s = HTTP::Server::Brick->new(port=>$port,fork=>1);
    $s->add_type('text/html' => qw(^[^\.]+$));
    $s->mount("/"=>{ path => $self->{output} });

    $s->start
}

# sub read_project - Read the project file.

sub read_project {
    my ($self) = @_;

    my $config = LoadFile($self->{config}) or die "error: could not load \"$self->{config}\": $!\n";

    # Graft together
    @{$self->{site}}{keys %{$config}} = values %$config;

    die "error: \"source\" must be defined in project file\n" unless defined $self->{source};
    die "error: \"output\" must be defined in project file\n" unless defined $self->{output};
    die "error: \"layout\" must be defined in project file\n" unless defined $self->{layout};

    #print Dump($self->{site});
}

# sub read_templates - Read the content of the templates specified in the project configuration file.

sub read_templates {
    my ($self) = @_;
    my ($key, $ckey);

    opendir(DIR, $self->{layout}) or die $!;
    my @files = sort(grep(!/^\..*$/, readdir(DIR)));

    for my $file (@files) {
        my $stem = App::Dapper::Utils::filter_stem($file);
        $file = $self->{layout} . "/" . $file;
        $self->{layout_content}->{$stem} = App::Dapper::Utils::read_file($file);
    }

    # Expand sub layouts
    for my $key (keys %{$self->{layout_content}}) {
        my $value = $self->{layout_content}->{$key};
        my $frontmatter;
        my $content;

        $value =~ /(---.*?)---(.*)/s;

        if (not defined $1) { next; }
        if (not defined $2) { next; }

        $frontmatter = Load($1);
        $content  = $2;

        if (not defined $frontmatter->{layout}) { next; }
        if (not defined $self->{layout_content}->{$frontmatter->{layout}}) { next; }

        my $master = $self->{layout_content}->{$frontmatter->{layout}};
        $master =~ s/\[\% *page\.content *\%\]/$content/g;
        $self->{layout_content}->{$key} = $master;

        #print "$key Result:\n" . $self->{layout_content}->{$frontmatter->{layout}} . "\n\n\n\n\n\n";
    }
}

# sub walk - Walk the source directory and output directory and build the site hash.

sub walk {
  my ($self, $source_dir, $output_dir) = @_;
  my $source_handle = new IO::Dir "$source_dir";;
  my $output_handle = new IO::Dir "$output_dir";;
  my $directory_element;

  # if the directory does not exist, create it
  if (!(defined $output_handle)) {
    mkdir($output_dir);
    $output_handle = new IO::Dir "$output_dir";
  }

  if (defined $source_handle) {

    # cycle through each element in the current directory
    while(defined($directory_element = $source_handle->read)) {

      # print "directory element:$source/$directory_element\n";
      if(-d "$source_dir/$directory_element" and $directory_element ne "." and $directory_element ne "..") {
        $self->walk("$source_dir/$directory_element", "$output_dir/$directory_element");
      }
      elsif(-f "$source_dir/$directory_element" and $directory_element ne "." and $directory_element ne "..") {
   
        # Skip dot files
        if ($directory_element =~ /^\./) { next; }
    
        # Construct output file name, which is a combination
        # of the stem of the source file and the extension of the template.
        # Example:
        #   - Source: index.md
        #   - Template: layout.html
        #   - Destination: index.html
        my $source = "$source_dir/$directory_element";
        my $output = "$output_dir/$directory_element";
      
        $self->build_inventory($source, $output);
      }
    }
    undef $source_handle;
  }
  else {
    die "error: could not get a handle on $source_dir/$directory_element";
  }
  #undef %b_ddm;
}

# sub build_inventory - Build the internal hash of files, configurations, and layouts.

sub build_inventory {
    my ($self, $source_file_name, $destination_file_name) = @_;

    my %page = ();

    my $source_content = App::Dapper::Utils::read_file($source_file_name);

    $source_content =~ /(---.*?)---(.*)/s;

    my ($frontmatter) = Load($1);
    $page{content} = $2;

    for my $key (keys %{$frontmatter}) {
        $page{$key} = $frontmatter->{$key};
    }

    $page{slug} = App::Dapper::Utils::slugify($page{title});

    if (not $page{date}) {
        my $date = App::Dapper::Utils::get_modified_time($source_file_name);
        # print "Didn't find date for $source_file_name. Setting to file modified date of $date\n";
        $page{date} = $date;
    }
   
    if($page{date} =~ /^(\d\d\d\d)-(\d\d)-(\d\d) (\d\d)\:(\d\d)\:(\d\d)$/) {
        $page{year} = $1;
        $page{month} = $2;
        $page{day} = $3;
        $page{hour} = $4;
        $page{minute} = $5;
        $page{second} = $6;
        $page{nanosecond} = 0;
    }

    if(not $page{timezone}) {
        $page{timezone} = DateTime::TimeZone->new( name => 'local' );
    }

    $page{date} = DateTime->new(
        year       => $page{year},
        month      => $page{month},
        day        => $page{day},
        hour       => $page{hour},
        minute     => $page{minute},
        second     => $page{second},
        nanosecond => $page{nanosecond},
        time_zone  => $page{timezone},
    );

    $page{url} = defined $page{urlpattern} ? $page{urlpattern} : $self->{site}->{urlpattern};
    $page{url} =~ s/\:category/$page{categories}/g unless not defined $page{categories};
    $page{url} =~ s/\:year/$page{year}/g unless not defined $page{year};
    $page{url} =~ s/\:month/$page{month}/g unless not defined $page{month};
    $page{url} =~ s/\:day/$page{day}/g unless not defined $page{day};
    $page{url} =~ s/\:hour/$page{hour}/g unless not defined $page{hour};
    $page{url} =~ s/\:minute/$page{minute}/g unless not defined $page{minute};
    $page{url} =~ s/\:second/$page{second}/g unless not defined $page{second};
    $page{url} =~ s/\:slug/$page{slug}/g unless not defined $page{slug};

    $page{id} = ++$ID; #$page{url};

    if (not defined $page{extension}) { $page{extension} = $self->{site}->{extension}; }

    $page{source_file_extension} = App::Dapper::Utils::filter_extension($source_file_name);

    $page{filename} = App::Dapper::Utils::filter_stem("$destination_file_name") . $page{extension};
    
    if(defined $page{categories}) {
        my $filename = $self->{site}->{output} . $page{url};
        $filename =~ s/\/$/\/index.html/; 
        $page{filename} = canonpath $filename;
    }

    my ($volume, $dirname, $file) = File::Spec->splitpath( $page{filename} );
    $page{dirname} = $dirname;

    if ($page{source_file_extension} eq ".md") { 
        $page{content} = markdown($page{content});

        # Save first paragraph of content as excerpt
        $page{content} =~ /(<p>.*?<\/p>)/s;
        $page{excerpt} = $1;
    }
    else {
        print "Did not run markdown on $page{filename} since the extension was not .md\n";
    }

    # Remove leading spaces and newline
    $page{content} =~ s/^[ \n]*//;
    
    if ($page{categories}) {
        push @{$self->{site}->{categories}->{$page{categories}}}, \%page;

        # Keep the array sorted
        @{$self->{site}->{categories}->{$page{categories}}} = sort { $a->{date} <=> $b->{date} } @{$self->{site}->{categories}->{$page{categories}}};
    }

    push @{$self->{site}->{pages}}, \%page;
}

# sub copy(sourcedir, outputdir) - Copies files and directories from <sourcedir> to <outputdir> as long as they do not made what is contained in $self->{site}->{ignore}.

sub copy {
    my ($self, $dir, $output) = @_;

    opendir(DIR, $dir) or die $!;

    DIR: while (my $file = readdir(DIR)) {
        for my $i (@{ $self->{site}->{ignore} }) {
            next DIR if ($file =~ m/$i/);
        }

        $output =~ s/\/$//;
        my $command = "cp -r $file $output";
        print $command . "\n";
        system($command);
    }

    closedir(DIR);
}

=head1 AUTHOR

Mark Benson, C<< <markbenson at vanilladraft.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-text-dapper at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=App-Dapper>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc App::Dapper

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Dapper>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/App-Dapper>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/App-Dapper>

=item * Search CPAN

L<http://search.cpan.org/dist/App-Dapper/>

=back

=head1 LICENSE AND COPYRIGHT

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

=cut

1; # End of App::Dapper

