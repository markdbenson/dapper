package Text::Dapper;

use 5.006;
use strict;
use warnings FATAL => 'all';

use vars '$VERSION';

use IO::Dir;
use File::Spec::Functions qw/ canonpath /;
use Template::Liquid;
use Text::MultiMarkdown 'markdown';
use HTTP::Server::Brick;

# Defaults
my $DEFAULT_PORT         = 8000;
my $DEFAULT_OPTION_FILE  = "_dapper.cfg";
my $DEFAULT_PROJECT_FILE = "_project.cfg";

my %h_constant;      # symbolic constants
my %h_program;       # program configuration variables
my %h_sstyle;        # source tag style
my %h_tstyle;        # template tag style
my %h_project;       # project settings hash
my %h_define;        # definition hash
my %h_template;      # template hash (value=filename)
my %h_tpl_content;   # template hash (value=file contents)
my $def_template;    # holds the default template reference
my %ignore = ();     # List of files and directories to ignore (i.e. do not copy to output directory

#@dirs = ['_source',
#         '_templates'];
#
#%files = ('_dapper.cfg', \$dapper_config_content,
#          '_project.cfg', \$project_file_template_content,
#          '_source/index.txt', \$source_index_content,
#          '_templates/index.html', \$templates_index_content);

my $source_dir_name = "_source";
my $templates_dir_name = "_templates";

my $source_index_name = "$source_dir_name/index.txt";
my $source_index_content = <<'SOURCE_INDEX_CONTENT';
use default template

Hello world.
SOURCE_INDEX_CONTENT

my $templates_index_name = "$templates_dir_name/index.html";
my $templates_index_content = <<'TEMPLATES_INDEX_CONTENT';
<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
<head>
  <title>Title</title>
  <meta http-equiv="content-type" content="text/html; charset=iso-8859-1">
</head>

<body>

{{ content }}

</body>
</html>

TEMPLATES_INDEX_CONTENT

my $proj_file_template_name = "_project.cfg";
my $proj_file_template_content = <<'PROJ_FILE_TEMPLATE';
# Dapper project config file
#
# This is a configuration file to use with dapper.pl. Since I haven't
# written documentation for dapper yet,  you're probably best off just
# modifying the contents of this file or asking me how dapper works.
#
# Each line in this file is a directive. Here are the types of directives
# that dapper understands.
#
# constant:
#    These are similar to symbolic constants in c and c++. This is best
#    described using an example.  If you specify a constant like
#    "constant name billy", then dapper will convert "my name is $(name)"
#    to "my name is billy".
#
# project:
#    There are only three of these and they must exist in every dapper
#    configuration file.  the "project source <path>" and "project template
#    <path>" directives specify where the source files, and templates are
#    located, respectively.  "project output <path>" is the path for which
#    to place the output (compiled) files.  The directory structure in the
#    output directory will mirror the directory structure in the source
#    directory.
#
# template:
#    This directive which takes the form "template <name> <filename>"
#    defines the names of template files located in the template directory
#    described above that can be used in the project.  Each source file
#    uses the template that appears first in this file which is assumed
#    to be the default template.  If a source file needs to use a different
#    template, a directive is placed in the source file like "use <name>
#    template". At least one template must be defined in this file.
#
# define:
#    These directives make up the heart of dapper and tell it groupings of
#    text that should be replaced in templates.  Example:  if you define
#    "define StartBold <b>" and "define EndBold </b>" in this file, then
#    a template (or source) file that contains the line:
#    "my [$StartBold$]name[$EndBold$] is billy" will be changed to
#    "my <b>name</b> is billy".  As you can see, "define" directives contain
#    three parts: the directive ("define"), a reference name ("StartBold"),
#    and the value ("<b>").  If the third parameter is left out, then it
#    is taken to be an exmpty string.  Source files can re-define "define"
#    directives by containing lines like "[StartBold]<em>[/StartBold]" which
#    acts as an override to the definition in this file.  This is really the
#    heart of how dapper works.  Source files define pieces of text, and
#    templates embed that text into a structure (layout).  See the examples
#    in this project for more information.
#
# ignore:
#    This directory specifies file or directory names that should not be
#    transformed or copied.  This is useful for things like SrcSafe status
#    files.  Example: "ignore vssver.scc".

# This constant is defined so that it's easier to create different layout
# variations.

constant revision

# this definition allows me to display a string to indicate which version
# of the configurator that these docs are meant to go along with.

define build 0.9.8

# these lines are the three core lines that dapper must have to operate.

project source    _source/
project output    _output/$(revision)
project templates _templates/$(revision)

# these are the templates used in the site. to use a template, it must
# appear here.

template default index.html   # default

# this special definition is used to let source files declare where they
# are located in relation to the root output directory.  i added this in so
# that i could create a documentation set that's all based off of relative
# associations.

define relative_doc_root 

# define some font attributes.  i still need to add defs for stylesheet
# stuff.

define font_face verdana, arial, helvetica, sans-serif
define font_size 1

# this is where all the colors on the page are defined.  the primary color
# is the main background color.  the secondary color is an additional color
# (also a background color) that interacts with the primary background
# color.  the highlight color usually only appears 1-3 times on the page to
# attract the eye, or give the design stability.
#
# also defined here are font colors, link colors, and the color to be used
# in horizontal rules.

define color_primary   eeeeee
define color_secondary ffffff
define color_highlight 666666
define color_link      000033
define color_link_inv  ffffff
define color_font      333333
define color_font_inv  ffffff # used for the build text
define color_hr        999999

# some definitions for horizontal rules.  color information defined above.

define hr_size       1
define hr_width      100%
define hr_pre_space  10
define hr_post_space 10
define hr <table cellspacing="0" cellpadding="0" width="[$hr_width$]"><tr><td><img src="images/spacer.gif" height="[$hr_pre_space$]" border="0" alt=""></td></tr><tr><td bgcolor="[$color_hr$]"><img src="images/spacer.gif" height="[$hr_size$]" border="0" alt=""></td></tr><tr><td><img src="images/spacer.gif" height="[$hr_post_space$]" border="0" alt=""></td></tr></table>

# used in the 'examples' section

define bullet <b>&raquo;</b>&nbsp;

# this special definition declares how many pixels high the main body of the
# page is.  if the text gets longer, the browser will expand vertically.
# if the text is shorter, the page will not get smaller than this amount.

define content_min_height 250

# these are the basic definitions that are used throughout the project. a
# definition must appear here in order for it to be used in a template.

define title      My new site
define content
define section    # lets source files control which nav button is highlighted
define footer_nav # used for introduction tutorial navigation

# this definitions are used mainly in the tag reference section.  each tag
# should use most of these.

define head
define example
define description
define attributes
define notes

# special definition used to define an entire stylesheet.

define css

ignore \.
ignore ^_ 
ignore dapper

PROJ_FILE_TEMPLATE

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
        _created     => 1,
        _source      => shift,
        _output      => shift,
        _templates   => shift,
        _project_cfg => shift,
    };

    $self->{_source}      = "_source"      unless defined($self->{_source});
    $self->{_output}      = "_output"      unless defined($self->{_output});
    $self->{_templates}   = "_templates"   unless defined($self->{_templates});
    $self->{_project_cfg} = "_project_cfg" unless defined($self->{_project_cfg});

    # Print all the values just for clarification.
    print "Source:      $self->{_source}\n";
    print "Output:      $self->{_output}\n";
    print "Templates:   $self->{_templates}\n";
    print "Project CFG: $self->{_project_cfg}\n";

    bless $self, $class;
    return $self;
}

=head2 function2

=cut

sub init {
    my ($self) = @_;

    $self->create_file($proj_file_template_name, $proj_file_template_content);

    $self->create_dir($source_dir_name);
    $self->create_file($source_index_name, $source_index_content);

    $self->create_dir($templates_dir_name);
    $self->create_file($templates_index_name, $templates_index_content);

    print "Project initialized.\n";
}

sub create_file {
    my ($self, $filename, $content) = @_;
    $filename = canonpath $filename;
    die "Invalid number of arguments to create_file" if @_ != 3;
    
    #open(my $fh, '+>:encoding(UTF-8)', $filename)
    open(my $fh, '+>', $filename)
        or die "Could not open file '$filename' $!";

    print $fh $content;
    close $fh;
}

sub create_dir {
    my ($self, $dirname) = @_;
    $dirname = canonpath $dirname;
    die "Invalid number of arguments to create_dir" if @_ != 2;

    mkdir($dirname)
        or die "Could not create directory '$dirname' $!";
}

sub build {
    my($self) = @_;

    # load program and project configuration
    $self->read_project(); # loads h_constant, h_project, h_template, and h_define

    # expand symbolic constants
    $self->precompile();

    # replaces the values of h_template with actual content
    $self->read_templates();

    # recurse through the project tree and generate output (combine src with templates)
    $self->walk($h_project{source}, $h_project{output});

    # copy additional files and directories
    $self->copy(".", \%ignore, $h_project{output});

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
  my $section   = '';             # holds section name of line in focus
  my $reference = '';             # holds reference name of line in focus
  my $value     = '';             # holds value name of line in focus
  my $constant_section_count = 0; # number of 'constant' declarations
  my $project_section_count  = 0; # number of 'project' declarations
  my $define_section_count   = 0; # number of 'define' declarations
  my $template_section_count = 0; # number of 'template' declarations
  my $ignore_section_count   = 0; # number of 'ignore' declarations

  open(PROJECT, "<$self->{_project_cfg}") or die "error: could not open \"$self->{_project_cfg}\": $!\n";

  my $current_line_number;
  foreach(<PROJECT>) {
    $current_line_number++;

    s/^\s*(.*)$/$1/;   # strip leading space
    s/^(.*?)\#.*$/$1/; # strip comments
    s/^(.*?)\s*$/$1/;  # strip trailing space

    if($_ eq '') { next; } # if nothing left, proceed to next line

    /^\s*([a-zA-Z0-9]+)\s+([a-zA-Z0-9_\.\^\\]+)\s*(.*)$/
      or warn "warning: regex did not match project configuration line ($_): $current_line_number\n";

    $section = $1;
    $reference = $2;
    $value = $3;

    if($section eq 'constant')    { $h_constant{$reference} = $value;      $constant_section_count++;   }
    elsif($section eq 'project')  { $h_project{$reference}  = $value;      $project_section_count++;    }
    elsif($section eq 'define')   { $h_define{$reference}   = $value;      $define_section_count++;     }
    elsif($section eq 'ignore')   { $ignore{$reference}     = "";          $ignore_section_count++;     }
    elsif($section eq 'template') { $h_template{$reference} = $value;      $template_section_count++;
                                    if($template_section_count == 1) { $def_template = $reference; } }
    else { ; } # forgive the offending line
  }

  die "error: \"project source\" must be defined in project file\n"    unless defined $h_project{source};
  die "error: \"project output\" must be defined in project file\n"    unless defined $h_project{output};
  die "error: \"project templates\" must be defined in project file\n" unless defined $h_project{templates};

  die "error: at least one \"define\" must appear in project file\n"   unless $define_section_count;
  die "error: at least one \"template\" must appear in project file\n" unless $template_section_count;

  close PROJECT;
}

# read_templates reads the content of the templates specified in the project configuration file.
sub read_templates {
    my ($self) = @_;
    my ($key, $ckey);

    foreach $key (keys %h_template) {
        open(TEMPLATE, "<$h_project{templates}$h_template{$key}")
            or die "error: could not open template: $h_project{templates}$h_template{$key}\n";
    
        foreach(<TEMPLATE>) { $h_tpl_content{$key} .= $_; }
        close TEMPLATE;
    }
}

# expand symbolic constants -- this function uses iteration to continue to expand symbolic constants until
# they are all resolved.
sub precompile {
  my ($akey, $ckey, $found);

  while(1) {
    $found = 0;
    foreach $ckey (keys %h_constant) {
      # program configuration
      foreach $akey (keys %h_program)  { if($h_program{$akey}  =~ s/\$\($ckey\)/$h_constant{$ckey}/g) { $found = 1; } }
      foreach $akey (keys %h_sstyle)   { if($h_sstyle{$akey}   =~ s/\$\($ckey\)/$h_constant{$ckey}/g) { $found = 1; } }
      foreach $akey (keys %h_tstyle)   { if($h_tstyle{$akey}   =~ s/\$\($ckey\)/$h_constant{$ckey}/g) { $found = 1; } }

      # project configuration
      foreach $akey (keys %h_project)  { if($h_project{$akey}  =~ s/\$\($ckey\)/$h_constant{$ckey}/g) { $found = 1; } }
      foreach $akey (keys %h_template) { if($h_template{$akey} =~ s/\$\($ckey\)/$h_constant{$ckey}/g) { $found = 1; } }
      foreach $akey (keys %h_define)   { if($h_define{$akey}   =~ s/\$\($ckey\)/$h_constant{$ckey}/g) { $found = 1; } }

      # constants
      foreach $akey (keys %h_constant) { if($h_constant{$akey} =~ s/\$\($ckey\)/$h_constant{$ckey}/g) { $found = 1; } }

      # template content
      #foreach $akey (keys %h_tpl_content) { $h_tpl_content{$akey} =~ s/\$\($ckey\)/$h_constant{$ckey}/g; }
    }
    if($found == 0) { last; }
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

    $source_content = $self->read_file($source_file_name);

    $template_to_use = $self->find_template_statement($source_content);
    $template_content = $self->read_file("$h_project{templates}$h_template{$template_to_use}");
    print "template to be used: $template_to_use\n";
    print "template content: $template_content\n";

    print "\nsource content before template statements stripped\n";
    print $source_content;
    $source_content = $self->filter_template_statements($source_content);
    print "\nsource content after template statements stripped\n";
    print $source_content;

    # Markdownify
    $source_content = markdown($source_content);
    print "source content after being markdownified\n";
    print $source_content;

    # Construct destination file name, which is a combination
    # of the stem of the source file and the extension of the template.
    # Example:
    #   - Source: index.md
    #   - Template: layout.html
    #   - Destination: index.html
    my $stem = $self->filter_stem($destination_file_name);
    my $ext  = $self->filter_extension($h_template{$template_to_use});
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

# Takes a file name and returns a string of the contents
sub read_file {
  my ($self, $file_name) = @_;
    my $file_contents;

    open(FILE, "<$file_name") or die("could not open file: $!\n");
    foreach (<FILE>) { $file_contents .= $_; }
    close(FILE) or die("could not close file: $!\n");

    return $file_contents;
}

# Takes a string, replaces all occurrances of defined constants and returns the modified string.
sub replace_constants {
    my ($self, $string) = @_;

    foreach my $ckey (keys %h_constant) { $string =~ s/\$\($ckey\)/$h_constant{$ckey}/g; }

    return $string;
}

# Takes a string, returns <template> part of the first "use <template> template" line.
sub find_template_statement {
    my ($self, $string) = @_;

    if($string =~ /^use\s+([a-zA-Z0-9_]+)\s+template/) { return $1; }
    
    return $def_template;
}

# Takes a string, removes all "use <template> template" statements and returns what's left.
sub filter_template_statements {
    my ($self, $string) = @_;

    $string =~ s/^(use\s+[a-zA-Z0-9_]+\s+template)//g;
    
    return $string;
}

sub filter_extension {
    my ($self, $filename) = @_;

    my ($ext) = $filename =~ /(\.[^.]+)$/;
   
    return $ext;
}

sub filter_stem {
    my ($self, $filename) = @_;
    
    print "filter_stem before: $filename\n";

    (my $stem = $filename) =~ s/\.[^.]+$//;

    print "filter_stem after: $filename\n";

    return $stem;
}
 
# copy(sourcdir, ignore, outputdir)
#
# This subroutine copies all directories and files from
# sourcedir into outputdir as long as they do not match
# what is contained in ignore.
sub copy {
    my ($self, $dir, $ignore, $output) = @_;

    opendir(DIR, $dir) or die $!;

    DIR: while (my $file = readdir(DIR)) {
        foreach my $key (keys(%ignore)) {
            next DIR if ($file =~ m/$key/);
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

