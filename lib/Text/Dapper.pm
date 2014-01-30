package Text::Dapper;

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
#$Data::Dumper::Indent = 1;
#$Data::Dumper::Sortkeys = 1;

use Text::Dapper::Init;
use Text::Dapper::Utils;
use Text::Dapper::Defaults;

my $DEFAULT_PORT   = 8000;

=head1 NAME

Text::Dapper - A static site generator

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

Quick summary of what the module does.

Perhaps a little code snippet.

    use Text::Dapper;

    my $foo = Text::Dapper->new();
    ...

=head1 EXPORT

A list of functions that can be exported.  You can delete this section
if you don't export anything, such as for a purely object-oriented module.

=cut

use Exporter qw(import);

our @EXPORT = qw($VERSION);

=head1 SUBROUTINES/METHODS

=head2 function1

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

    $self->{site} = Text::Dapper::Defaults::get_defaults();
    $self->{source} = "_source" unless defined($self->{source});
    $self->{output} = "_output" unless defined($self->{output});
    $self->{layout} = "_layout" unless defined($self->{layout});
    $self->{config} = "_config" unless defined($self->{config});

    bless $self, $class;
    return $self;
}

=head2 function2

=cut

sub init {
    my ($self) = @_;

    Text::Dapper::Init::init();

    print "Project initialized.\n";
}

sub build {
    my($self) = @_;

    # load program and project configuration
    $self->read_project();

    # replaces the values of h_template with actual content
    $self->read_templates();

    # recurse through the project tree and generate output (combine src with templates)
    $self->walk($self->{source}, $self->{output});

    # render output
    $self->render();

    #print Dumper $self->{site};

    #print Dumper($self->{site}); 
    # copy additional files and directories
    $self->copy(".", $self->{output});

    print "Project built.\n";
}

sub serve {
    my($self, $port) = @_;

    $port = $DEFAULT_PORT unless $port;

    my $s = HTTP::Server::Brick->new(port=>$port);
    $s->mount("/"=>{path=>"_output"});
    $s->start
}

# read_project reads the project file and places the values found
# into the appropriate hash.
sub read_project {
    my ($self) = @_;

    my $config = LoadFile($self->{config}) or die "error: could not load \"$self->{config}\": $!\n";

    # Graft together
    #@hash1{keys %hash2} = values %hash2;
    @{$self->{site}}{keys %$config} = values %$config;

    die "error: \"source\" must be defined in project file\n" unless defined $self->{source};
    die "error: \"output\" must be defined in project file\n" unless defined $self->{output};
    die "error: \"layout\" must be defined in project file\n" unless defined $self->{layout};

    #print Dump($self->{site});
}

# read_templates reads the content of the templates specified in the project configuration file.
sub read_templates {
    my ($self) = @_;
    my ($key, $ckey);

    opendir(DIR, $self->{layout}) or die $!;
    my @files = sort(grep(!/^(\.|\.\.)$/, readdir(DIR)));

    for my $file (@files) {
        my $stem = Text::Dapper::Utils::filter_stem($file);
        $file = $self->{layout} . "/" . $file;
        $self->{layout_content}->{$stem} = Text::Dapper::Utils::read_file($file);
        #print "$stem layout content:\n";
        #print $self->{layout_content}->{$stem};
    }
}

# recursive descent
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
        #combine_source_and_template("$source/$directory_element", "$output/$directory_element");
    
        # Construct output file name, which is a combination
        # of the stem of the source file and the extension of the template.
        # Example:
        #   - Source: index.md
        #   - Template: layout.html
        #   - Destination: index.html
        my $source = "$source_dir/$directory_element";
        my $output = "$output_dir/$directory_element";
      
        $output = Text::Dapper::Utils::filter_stem("$output") . ".html";

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

# Takes a source file and destination file and adds an appropriate meta data entries to the taj mahal multi-tiered site hash.
sub taj_mahal {
    my ($self, $source_file_name, $destination_file_name) = @_;

    my %page = ();

    my $source_content = Text::Dapper::Utils::read_file($source_file_name);

    $source_content =~ /(---.*)---(.*)/s;

    my ($frontmatter) = Load($1);

    for my $key (keys $frontmatter) {
        $page{$key} = $frontmatter->{$key};
    }

    $page{content} = $2;

    $page{slug} = Text::Dapper::Utils::slugify($page{title});

    if (not $page{date}) {
        my $date = Text::Dapper::Utils::get_modified_time($source_file_name);
        print "Didn't find date for $source_file_name. Setting to file modified date of $date\n";
        $page{date} = $date;
    }
    
    if($page{date} =~ /^(\d\d\d\d)-(\d\d)-(\d\d).*$/) {
        $page{year} = $1;
        $page{month} = $2;
        $page{day} = $3;
    }

    $page{url} = $self->{site}->{urlpattern};
    $page{url} =~ s/\:category/$page{categories}/g unless not defined $page{categories};
    $page{url} =~ s/\:year/$page{year}/g unless not defined $page{year};
    $page{url} =~ s/\:month/$page{month}/g unless not defined $page{month};
    $page{url} =~ s/\:day/$page{day}/g unless not defined $page{day};
    $page{url} =~ s/\:slug/$page{slug}/g unless not defined $page{slug};

    $page{filename} = $destination_file_name;
    if(defined $page{categories}) {
        my $filename = $self->{site}->{output} . $page{url};
        $page{filename} = canonpath $filename;
    }

    my ($volume, $dirname, $file) = File::Spec->splitpath( $page{filename} );
    $page{dirname} = $dirname;

    if ($page{categories}) {
        push @{$self->{site}->{categories}->{$page{categories}}}, \%page;
    }

    push @{$self->{site}->{pages}}, \%page;
}

sub render {
    my ($self) = @_;

    for my $page (@{$self->{site}->{pages}}) {

        $page->{content} = markdown($page->{content});

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
}

# copy(sourcdir, outputdir)
#
# This subroutine copies all directories and files from
# sourcedir into outputdir as long as they do not match
# what is contained in ignore.
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
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Text-Dapper>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Text::Dapper


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Text-Dapper>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Text-Dapper>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Text-Dapper>

=item * Search CPAN

L<http://search.cpan.org/dist/Text-Dapper/>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

The MIT License (MIT)

Copyright (c) 2014 Mark Benson

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

1; # End of Text::Dapper

