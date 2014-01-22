package Text::Dapper;

use 5.006;
use strict;
use warnings FATAL => 'all';

use vars '$VERSION';

use IO::Dir;
use Template::Liquid;
use Text::MultiMarkdown 'markdown';
use HTTP::Server::Brick;
use YAML qw(LoadFile Dump);

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
  my ($self, $source, $destination) = @_;
  my $source_handle = new IO::Dir "$source";;
  my $destination_handle = new IO::Dir "$destination";;
  my $directory_element;

  #print "received:src:$source:\n";
  #print "received:dst:$destination:\n";

  # if the directory does not exist, create it
  if (!(defined $destination_handle)) {
    mkdir($destination);
    $destination_handle = new IO::Dir "$destination";
  }

  if (defined $source_handle) {

    # cycle through each element in the current directory
    while(defined($directory_element = $source_handle->read)) {

      # print "directory element:$source/$directory_element\n";
      if(-d "$source/$directory_element" and $directory_element ne "." and $directory_element ne "..") {
        $self->walk("$source/$directory_element", "$destination/$directory_element");
      }
      elsif(-f "$source/$directory_element" and $directory_element ne "." and $directory_element ne "..") {
        #combine_source_and_template("$source/$directory_element", "$destination/$directory_element");
        $self->render("$source/$directory_element", "$destination/$directory_element");
      }
    }
    undef $source_handle;
  }
  else {
    die "error: could not get a handle on $source/$directory_element";
  }
  #undef %b_ddm;
}

sub render {
    my ($self, $source_file_name, $destination_file_name) = @_;
    my $source_content;
    my $template_to_use;
    my $template_content;

    $source_content = Text::Dapper::Utils::read_file($source_file_name);

    $template_to_use = Text::Dapper::Utils::find_template_statement($source_content);
    #print "template to be used: $template_to_use\n";
    $template_content = $self->{_layout_content}->{$template_to_use};
    #print "template content: $template_content\n";

    $source_content = Text::Dapper::Utils::filter_template_statements($source_content);

    # Markdownify
    $source_content = markdown($source_content);

    # Construct destination file name, which is a combination
    # of the stem of the source file and the extension of the template.
    # Example:
    #   - Source: index.md
    #   - Template: layout.html
    #   - Destination: index.html
    my $stem = Text::Dapper::Utils::filter_stem($destination_file_name);
    my $ext  = ".html";
    $destination_file_name = "$stem$ext";

    # Make sure we have a copy of the template file
    my $parsed_template = Template::Liquid->parse($template_content);

    # Render the output file using the template and the source
    my $destination = $parsed_template->render(content => $source_content);

    # Save the output file
    open(DESTINATION, ">$destination_file_name") or die "error: could not open destination file:$destination_file_name: $!\n";
    print(DESTINATION $destination) or die "error: could not print to $destination_file_name: $!\n";
    close(DESTINATION) or die "error: could not close $destination_file_name: $!\n";
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

