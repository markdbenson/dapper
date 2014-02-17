package App::Dapper;

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.006;
use strict;
use warnings FATAL => 'all';

use vars '$VERSION';

use IO::Dir;
use Template::Liquid;

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

=head1 NAME

App::Dapper - A publishing platform for static websites

=head1 VERSION

Version 0.02

=cut

our $VERSION = '0.02';

=head1 SYNOPSIS

Dapper allows you to transform simple text files into websites. By installing the App::Dapper Perl module, a dapper executable will be available to you in your Terminal window. You can use this executable in a number of ways:

    # Initialize the current directory with a fresh skeleton of a site
    $ dapper init

    # Build the site
    $ dapper build

    # Serve the site locally at http://localhost:8000
    $ dapper serve

    # Watch the source dir, layout dir, and config file for changes
    # If changes are detected, rebuild the site
    $ dapper watch

    # Get help on additional ways to use the dapper executable
    $ dapper -h

    # Print the version
    $ dapper -v

    # Build site using "posts" as the source directory
    # Note this may also be specified in the config file
    $ dapper -s "posts" build

    # Build site using "templates" as the layout directory
    # Note this may also be specified in the config file
    $ dapper -l templates build

    # Build site using "site" as the output directory
    # Note this may also be specified in the config file
    $ dapper -o site build

    # Build site using "project.yml" as the config file
    $ dapper -c project.yml build

See the documentation for L<bin/dapper> for more information.

Additionally, Dapper may be used as a perl module directly. Examples:

    use App::Dapper;

    # Initialize a skeleton Dapper site in the current directory
    my $d = App::Dapper->new();
    $d->init();
    undef $d;

    # Build the site
    my $d = App::Dapper->new();
    $d->build();
    undef $d;

    # Serve the site locally at http://localhost:8000
    my $d = App::Dapper->new();
    $d->serve();
    undef $d;

=cut

use Exporter qw(import);

our @EXPORT = qw($VERSION);

=head1 METHODS

=head2 new

Create a new Dapper object. Example:

    my $d = App::Dapper->new();

Alternatively, the source dir, output dir, layout dir, and configuration file
may be specified. Example:

    my $d = App::Dapper->new("_source", "_output", "_layout", "_config.yml");

Defaults are as follows:

=over 4

=item <source> = "_source"

=item <output> = "_output"

=item <layout> = "_layout"

=item  <config> = "_config.yml"

=back

After creating a Dapper object, the followin hash elements may be accessed:

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

Initializes a new skeleton project in the current directory (of the calling script, and
uses the defined source dir, output dir, layout dir, and config file. Example usage:

    use App::Dapper;

    my $d = App::Dapper->new();
    $d->init();

After running this method, the following directory structure will be created:

    ├── _config.yml
    ├── _layout/
    │  └── index.html
    └── _source/
        └── index.md

=cut

sub init {
    my ($self) = @_;

    print "SOURCE is ($self->{source})\n";

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
    
    $self->parse();
    $self->transform();
    $self->render();

    print "Project built.\n";
}

=head2 parse

Parse the source directory, config file, and templates.

=cut

sub parse {
    my ($self) = @_;

    # load program and project configuration
    $self->read_project();

    # replaces the values of h_template with actual content
    $self->read_templates();
}

=head2 transform

Walk the source and output directories and transform the text into the output files.

=cut

sub transform {
    my ($self) = @_;

    # recurse through the project tree and generate output (combine src with templates)
    $self->walk($self->{source}, $self->{output});
}

=head2 render

Render the internal hash of source files, config file, and layouts into the actual output files
on disk.

=cut

sub render {
    my ($self) = @_;

    for my $page (@{$self->{site}->{pages}}) {

        #print Dump $page->{content};

        if (not $page->{layout}) { $page->{layout} = "index"; }
        my $layout = $self->{layout_content}->{$page->{layout}};
        
        # Make sure we have a copy of the template file
        my $parsed_template = Template::Liquid->parse($layout);

        my %tags = ();
        $tags{site} = $self->{site};
        $tags{page} = $page;
        #$tags{page}->{content} = $content;

        # Render the output file using the template and the source
        my $destination = $parsed_template->render(%tags);

        # Parse and render once more to make sure that any liquid statments
        # In the source file also gets rendered
        $parsed_template = Template::Liquid->parse($destination);
        $destination = $parsed_template->render(%tags);

        if ($page->{filename}) {
            make_path($page->{dirname}, { verbose => 1 });
            open(DESTINATION, ">$page->{filename}") or die "error: could not open destination file:$page->{filename}: $!\n";
            print(DESTINATION $destination) or die "error: could not print to $page->{filename}: $!\n";
            close(DESTINATION) or die "error: could not close $page->{filename}: $!\n";

            print "Wrote $page->{filename}\n";
            #print Dumper $page;
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

=head2 serve

Serve the site locally. Pass in the port number. The port number will be used to serve the site contents from the output directory like this: http://localhost:<port>. Here is an example, using the default port 8000:

    use App::Dapper;

    my $d = App::Dapper->new();
    $d->serve("8000");

The following is equivalent:

    $d->serve();

=cut

sub serve {
    my($self, $port) = @_;

    $port = $DEFAULT_PORT unless $port;

    my $s = HTTP::Server::Brick->new(port=>$port);
    $s->add_type('text/html' => qw(^[^\.]+$));
    $s->mount("/"=>{ path => $self->{output} });

    $s->start
}

=head2 read_project

Read the project file.

=cut

sub read_project {
    my ($self) = @_;

    my $config = LoadFile($self->{config}) or die "error: could not load \"$self->{config}\": $!\n";

    # Graft together
    @{$self->{site}}{keys %$config} = values %$config;

    die "error: \"source\" must be defined in project file\n" unless defined $self->{source};
    die "error: \"output\" must be defined in project file\n" unless defined $self->{output};
    die "error: \"layout\" must be defined in project file\n" unless defined $self->{layout};

    #print Dump($self->{site});
}

=head2 read_templates

Read the content of the templates specified in the project configuration file.

=cut

sub read_templates {
    my ($self) = @_;
    my ($key, $ckey);

    opendir(DIR, $self->{layout}) or die $!;
    my @files = sort(grep(!/^\..*$/, readdir(DIR)));

    for my $file (@files) {
        my $stem = App::Dapper::Utils::filter_stem($file);
        $file = $self->{layout} . "/" . $file;
        $self->{layout_content}->{$stem} = App::Dapper::Utils::read_file($file);
        #print "$stem layout content:\n";
        #print $self->{layout_content}->{$stem};
    }

    # Expand sub layouts
    for my $key (keys $self->{layout_content}) {
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
        $master =~ s/\{\{ *page\.content *\}\}/$content/g;
        $self->{layout_content}->{$key} = $master;

        #print "$key Result:\n" . $self->{layout_content}->{$frontmatter->{layout}} . "\n\n\n\n\n\n";
    }
}

=head2 walk

Walk the source directory and output directory and build the site hash.

=cut

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
      
        $self->taj_mahal($source, $output);
      }
    }
    undef $source_handle;
  }
  else {
    die "error: could not get a handle on $source_dir/$directory_element";
  }
  #undef %b_ddm;
}

=head2 taj_mahal

Build the internal hash of files, configurations, and layouts.

=cut

sub taj_mahal {
    my ($self, $source_file_name, $destination_file_name) = @_;

    my %page = ();

    my $source_content = App::Dapper::Utils::read_file($source_file_name);

    $source_content =~ /(---.*?)---(.*)/s;

    my ($frontmatter) = Load($1);
    $page{content} = $2;

    for my $key (keys $frontmatter) {
        $page{$key} = $frontmatter->{$key};
    }

    $page{slug} = App::Dapper::Utils::slugify($page{title});

    if (not $page{date}) {
        my $date = App::Dapper::Utils::get_modified_time($source_file_name);
        #print "Didn't find date for $source_file_name. Setting to file modified date of $date\n";
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

    $page{url} = $self->{site}->{urlpattern};
    $page{url} =~ s/\:category/$page{categories}/g unless not defined $page{categories};
    $page{url} =~ s/\:year/$page{year}/g unless not defined $page{year};
    $page{url} =~ s/\:month/$page{month}/g unless not defined $page{month};
    $page{url} =~ s/\:day/$page{day}/g unless not defined $page{day};
    $page{url} =~ s/\:slug/$page{slug}/g unless not defined $page{slug};

    $page{id} = $page{url};

    if (not defined $page{extension}) { $page{extension} = ".html"; }

    $page{source_file_extension} = App::Dapper::Utils::filter_extension($source_file_name);

    $page{filename} = App::Dapper::Utils::filter_stem("$destination_file_name") . $page{extension};
    
    #print "FILENAME BEFORE: " . $page{filename} . "\n";
    #print "FILENAME AFTER: " . $page{filename} . "\n";

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
    }

    push @{$self->{site}->{pages}}, \%page;
}

=head2 copy(sourcedir, outputdir)

Copies files and directories from <sourcedir> to <outputdir> as long as they do not
made what is contained in $self->{site}->{ignore}.

=cut

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

