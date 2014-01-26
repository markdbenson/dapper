package Text::Dapper;

#use utf8;
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

use Data::Dumper;
#$Data::Dumper::Indent = 1;
#$Data::Dumper::Sortkeys = 1;

use Text::Dapper::Init;
use Text::Dapper::Utils;

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
        _created=> 1,
        _source => shift,
        _output => shift,
        _layout => shift,
        _config => shift,
    };

    $self->{_source} = "_source" unless defined($self->{_source});
    $self->{_output} = "_output" unless defined($self->{_output});
    $self->{_layout} = "_layout" unless defined($self->{_layout});
    $self->{_config} = "_config" unless defined($self->{_config});

    # Print all the values just for clarification.
    #print "Source: $self->{_source}\n";
    #print "Output: $self->{_output}\n";
    #print "Layout: $self->{_layout}\n";
    #print "Config: $self->{_config}\n";

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
    $self->walk($self->{_source}, $self->{_output});

    # render output
    $self->render();

    # copy additional files and directories
    $self->copy(".", $self->{_output});

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
    $self->{_settings} = LoadFile($self->{_config}) or die "error: could not load \"$self->{_config}\": $!\n";

    die "error: \"source\" must be defined in project file\n" unless defined $self->{_source};
    die "error: \"output\" must be defined in project file\n" unless defined $self->{_output};
    die "error: \"layout\" must be defined in project file\n" unless defined $self->{_layout};

    #print Dump($self->{_settings});
}

# read_templates reads the content of the templates specified in the project configuration file.
sub read_templates {
    my ($self) = @_;
    my ($key, $ckey);

    opendir(DIR, $self->{_layout}) or die $!;
    my @files = sort(grep(!/^(\.|\.\.)$/, readdir(DIR)));

    for my $file (@files) {
        my $stem = Text::Dapper::Utils::filter_stem($file);
        $file = $self->{_layout} . "/" . $file;
        $self->{_layout_content}->{$stem} = Text::Dapper::Utils::read_file($file);
        #print "$stem layout content:\n";
        #print $self->{_layout_content}->{$stem};
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

    # Get last modified time
    #use File::stat;
    #use Time::localtime;
    #use POSIX qw(strftime);
    #$now_string = strftime "%a %b %e %H:%M:%S %Y", localtime;
    #print "FILE/TIMESTAMP: $source_file_name/$timestamp\n";

    $source_content =~ /(---.*)---(.*)/s;

    my ($frontmatter) = Load($1);

    for my $key (keys $frontmatter) {
        $page{$key} = $frontmatter->{$key};
    }

    $page{content} = $2;
    $page{filename} = $destination_file_name;
    $page{url} = "/replace/with/url/pattern";

    #print "== PAGE($page{filename})\n";

    if ($page{categories}) {
        push @{$self->{_settings}->{categories}->{$page{categories}}}, \%page;
    }
    
    push @{$self->{_settings}->{posts}}, \%page;

    #print Dumper($self->{_settings}); 
}

sub render {
    my ($self) = @_;

    for my $page (@{$self->{_settings}->{posts}}) {

        my $content = markdown($page->{content});
        $self->{content} = $content;

        if (not $page->{layout}) { $page->{layout} = "index"; }
        my $layout = $self->{_layout_content}->{$page->{layout}};
        
        # Make sure we have a copy of the template file
        my $parsed_template = Template::Liquid->parse($layout);

        my %tags = ();
        $tags{site} = $self->{_settings};
        $tags{page} = $page;
        $tags{page}->{content} = $content;

        # Render the output file using the template and the source
        my $destination = $parsed_template->render(%tags);

        if ($page->{filename}) {
            open(DESTINATION, ">$page->{filename}") or die "error: could not open destination file:$page->{filename}: $!\n";
            print(DESTINATION $destination) or die "error: could not print to $page->{filename}: $!\n";
            close(DESTINATION) or die "error: could not close $page->{filename}: $!\n";

            print "Wrote $page->{filename}\n";
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
        for my $i (@{ $self->{_settings}->{ignore} }) {
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

