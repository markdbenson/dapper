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

my $DEFAULT_PORT = 8000;

my $option_file = "_dapper.cfg";
my $project_file = "_project.cfg";


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

my $dapper_config_name = "_dapper.cfg";
my $dapper_config_content = <<'DAPPER_CONFIG_CONTENT';
#-------------------------------------------------------------------------
# Dapper program configuration file
# Mark Benson [markbenson@vanilladraft.com]
#-------------------------------------------------------------------------

constant   program_title         dapper
constant   program_description   an extensible text preprocessor
constant   program_revision      0.0.1
constant   program_author        mark benson

constant   project_extension     .html

program    warnings              1

sstyle     define                [[r]][v][/[r]]
tstyle     define                [$[r]$]

dapper config content
define red #ff0000

DAPPER_CONFIG_CONTENT

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

our @EXPORT = qw(new build serve $VERSION);

=head1 SUBROUTINES/METHODS

=head2 function1

=cut

#sub new {
#    my ($class_name) = @_;
#    my ($self) = {};
#    bless ($self, $class_name);
#    $self->{'_created'} = 1;
#    return $self;
#}

=head2 function2

=cut

sub new {
    print "NEW\n";

    create_dir($source_dir_name);
    create_dir($templates_dir_name);

    create_file($source_index_name, $source_index_content);
    create_file($templates_index_name, $templates_index_content);

    create_file($dapper_config_name, $dapper_config_content);
    create_file($proj_file_template_name, $proj_file_template_content);

    print "Project initialized.\n";
}

sub create_file {
    my ($filename, $content) = @_;
    $filename = canonpath $filename;
    die "Invalid number of arguments to create_file" if @_ != 2;
    
    #open(my $fh, '+>:encoding(UTF-8)', $filename)
    open(my $fh, '+>', $filename)
        or die "Could not open file '$filename' $!";

    print $fh $content;
    close $fh;
}

sub create_dir {
    my ($dirname) = @_;
    $dirname = canonpath $dirname;
    die "Invalid number of arguments to create_dir" if @_ != 1;

    mkdir($dirname)
        or die "Could not create directory '$dirname' $!";
}

sub build {
    print "BUILD\n";
    # load program and project configuration
    read_config($option_file);   # loads h_constant, h_program, h_sstyle, and h_tstyle
    read_project($project_file); # loads h_constant, h_project, h_template, and h_define

    # expand symbolic constants
    precompile();

    # replaces the values of h_template with actual content
    read_templates();

    # recurse through the project tree and generate output (combine src with templates)
    rec($h_project{source}, $h_project{output});

    # copy additional files and directories
    copy(".", \%ignore, $h_project{output});

}

sub serve {
    my $port = shift;

    $port = $DEFAULT_PORT unless $port;

    my $s = HTTP::Server::Brick->new(port=>$port);
    $s->mount("/"=>{path=>"_output"});
    $s->start
}

# read_config reads the configuration file and places the values found
# into the appropriate hash.
sub read_config {
  my $option_file = shift;
  my $section   = '';             # holds the section name of the line in focus
  my $reference = '';             # holds the reference name of the line in focus
  my $value     = '';             # holds the value name of the line in focus
  my $constant_section_count = 0; # number of 'constant' declarations
  my $program_section_count  = 0; # number of 'program' declarations
  my $sstyle_section_count   = 0; # number of 'sstyle' declarations
  my $tstyle_section_count   = 0; # number of 'tstyle' declarations

  open(CONFIG, "<$option_file") or die "error: could not open \"$option_file\": $!\n";

  my $current_line_number;
  foreach(<CONFIG>) {
    $current_line_number++;

    s/^\s*(.*)$/$1/;   # strip leading space
    s/^(.*?)\#.*$/$1/; # strip comments
    s/^(.*?)\s*$/$1/;  # strip trailing space

    if($_ eq '') { next; } # if nothing left, proceed to next line

    /^\s*([a-zA-Z0-9]+)\s+([a-zA-Z0-9_\.\^]+)\s*(.*)$/
      or die "warning: regex did not match program configuration line: $current_line_number\n";

    $section = $1;
    $reference = $2;
    $value = $3;

    if($section eq 'constant')   { $h_constant{$reference} = $value; $constant_section_count++; }
    elsif($section eq 'program') { $h_program{$reference}  = $value; $program_section_count++;  }
    elsif($section eq 'sstyle')  { $h_sstyle{$reference}   = $value; $sstyle_section_count++;   }
    elsif($section eq 'tstyle')  { $h_tstyle{$reference}   = $value; $tstyle_section_count++;   }
    else { ; } # forgive the offending line
  }

  die "error: exactly one \"sstyle define\" must be defined in configuration file\n" unless $sstyle_section_count == 1;
  die "error: exactly one \"tstyle define\" must be defined in configuration file\n" unless $tstyle_section_count == 1;

  close CONFIG;
}

# read_project reads the project file and places the values found
# into the appropriate hash.
sub read_project {
  my $project_file = shift;
  my $section   = '';             # holds section name of line in focus
  my $reference = '';             # holds reference name of line in focus
  my $value     = '';             # holds value name of line in focus
  my $constant_section_count = 0; # number of 'constant' declarations
  my $project_section_count  = 0; # number of 'project' declarations
  my $define_section_count   = 0; # number of 'define' declarations
  my $template_section_count = 0; # number of 'template' declarations
  my $ignore_section_count   = 0; # number of 'ignore' declarations

  open(PROJECT, "<$project_file") or die "error: could not open \"$project_file\": $!\n";

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
sub rec {
  my $source = shift;
  my $destination = shift;
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
        rec("$source/$directory_element", "$destination/$directory_element");
      }
      elsif(-f "$source/$directory_element" and $directory_element ne "." and $directory_element ne "..") {
        #combine_source_and_template("$source/$directory_element", "$destination/$directory_element");
        render("$source/$directory_element", "$destination/$directory_element");
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
    my $source_file_name = shift;
    my $destination_file_name = shift;
    my $source_content;
    my $template_to_use;
    my $template_content;

    open(SOURCE, "<$source_file_name") or die("could not open source file: $!\n");
    foreach (<SOURCE>) { $source_content .= $_; }

    if($source_content =~ /^use\s+([a-zA-Z0-9_]+)\s+template/) { $template_to_use = $1; }
    else { $template_to_use = $def_template; }
    print "template to be used: $template_to_use\n";

    # Strip off all directives
    $source_content =~ s/^(use\s+[a-zA-Z0-9_]+\s+template)//;

    # Markdownify
    $source_content = markdown($source_content);
    print "HTML: $source_content\n";

    # strip any extension
    $destination_file_name =~ s#^(.*)\.[a-zA-Z0-9_]*$#$1#;

    print "template_to_use:$template_to_use\n";
    # print "h_template value:$h_template{$template_to_use}\n";
    $h_template{$template_to_use} =~ m#^[a-zA-Z0-9_]*(\.[a-zA-Z0-9_]*)$#;
    my $extension = $1;

    open(DESTINATION, ">$destination_file_name$extension") or die "error: could not open destination file:$destination_file_name$extension:$!\n";
    open(TEMPLATE, "<$h_project{templates}$h_template{$template_to_use}") or die "could not open template file $h_project{templates}$h_template{$template_to_use}: $!\n";

    foreach (<TEMPLATE>) { $template_content .= $_; }
    print $template_content;

    # Make sure we have a copy of the template file
    my $parsed_template = Template::Liquid->parse($template_content);

    # Render the output file using the template and the source
    my $destination = $parsed_template->render(content => $source_content);

    # Save the output file
    print(DESTINATION $destination) or die "error: could not print to $destination_file_name$extension: $!\n";

    # close file handles
    close (SOURCE) or die "error: could not close $source_file_name: $!\n";
    close(DESTINATION) or die "error: could not close $destination_file_name$extension: $!\n";
    close (TEMPLATE) or die "error: could not close $h_project{templates}$h_template{$template_to_use}: $!\n";
}

# loads the macro bins with source-file directives
sub combine_source_and_template {
  my $source = shift;
  my $destination = shift;
  my $file;
  my $template_to_use;
  my ($key, $ckey);
  my $extension;
  my ($if_tag, $endif_tag);

  ### BEGIN MDB ADDITIONS
  # load language strings, program and project configuration, and templates
  read_config($option_file);   # loads h_constant, h_program, h_sstyle, and h_tstyle
  read_project($project_file); # loads h_constant, h_project, h_template, and h_define

  # expand symbolic constants
  precompile();
  # replaces the values of h_template with actual content
  read_templates();
  ### END MDB ADDITIONS

  #print "received:src:$source:\n";
  #print "received:dst:$destination:\n";

  open(SOURCE, "<$source") or die("could not open source file: $!\n");

  foreach (<SOURCE>) { $file .= $_; }
  foreach $ckey (keys %h_constant) { $file =~ s/\$\($ckey\)/$h_constant{$ckey}/g; }

  # get program directives
  if($file =~ /^use\s+([a-zA-Z0-9_]+)\s+template/) { $template_to_use = $1; }
  else { $template_to_use = $def_template; }
  print "template to be used: $template_to_use\n";

  foreach $key (keys %h_define) {
    my $temp = $h_sstyle{define};

    # replace '[r]' with the reference to look for
    $temp =~ s/\[r\]/$key/g;

    # get the start and end tag
    $temp =~ /^(.*)\[v\](.*)$/;
    my $mlb = $1;
    my $mle = $2;
    # print "starting tag: $mlb\n";
    # print "end tag: $mle\n";

    # escape non-words
    $mlb =~ s/([^a-zA-Z0-9_\.\*\(\)\|\?]{1})/\\$1/g;
    $mle =~ s/([^a-zA-Z0-9_\.\*\(\)\|\?]{1})/\\$1/g;

    # try and get a match
    if($file =~ m/($mlb)(.*?)($mle)/s) {
      my $res = $2;
      $res =~ s/^\s*//; # strip leading space
      $res =~ s/\s*$//; # strip trailing space

      # print "found match between $mlb and $mle\n";
      # print "content is:$res:\n";

      $h_define{$key} = $res;
    }

    else {
      # print "didn't find match for $mlb$mle\n";
      # print "using default value of :$h_define{$key} instead\n";
    }
  }
  close SOURCE;

  $file = '';

  # strip any extension
  $destination =~ s#^(.*)\.[a-zA-Z0-9_]*$#$1#;

  # print "template_to_use:$template_to_use\n";
  # print "h_template value:$h_template{$template_to_use}\n";
  $h_template{$template_to_use} =~ m#^[a-zA-Z0-9_]*(\.[a-zA-Z0-9_]*)$#;
  $extension = $1;

  open(DESTINATION, ">$destination$extension") or die "error: could not open destination file:$destination$extension:$!\n";
  open(TEMPLATE, "<$h_project{templates}$h_template{$template_to_use}") or die "could not open template file $h_project{templates}$h_template{$template_to_use}: $!\n";

  foreach (<TEMPLATE>) { $file .= $_; }
  foreach $ckey (keys %h_constant) { $file =~ s/\$\($ckey\)/$h_constant{$ckey}/g; }

  my $none;
  while(1) {
    $none = 1;
    foreach $key (keys %h_define) {
      my $temp = $h_tstyle{define};

      # replace '[r]' with the reference to look for
      $temp =~ s/\[r\]/$key/g;

      # construct an if tag [$if tag$]
      $if_tag = $temp;
      $if_tag =~ s#^(.*)($key)(.*)$#$1if\ $2(=|!)=(\.\*?)$3#;

      # construct an endif tag [$endif$]
      my $temp2 = $h_tstyle{define};
      # replace '[r]' with endif
      $temp2 =~ s/\[r\]/endif/g;
      $endif_tag = $temp2;

      # escape non-words
      $temp      =~ s/([^a-zA-Z0-9_\.\*\(\)\|\?]{1})/\\$1/g;
      $if_tag    =~ s/([^a-zA-Z0-9_\.\*\(\)\|\?]{1})/\\$1/g;
      $endif_tag =~ s/([^a-zA-Z0-9_\.\*\(\)\|\?]{1})/\\$1/g;

      # print "if:$if_tag\n";
      # print "endif:$endif_tag\n";

      # process conditional statements
      my $test_value;
      my $conditional_content;
      my $working;
      my $logic;
      while(1) {
        $working = $file;
        if($working =~ m/$if_tag(.*?)$endif_tag/s) {
          $logic = $1;
          $test_value = $2;
          $conditional_content = $3;
          # print "test value:$test_value\n";
          # print "cond cont:$conditional_content\n";
          if((($h_define{$key} eq $test_value) and ($logic eq '=')) or
             (($h_define{$key} ne $test_value) and ($logic eq '!'))) {
            # simply strip out the if and endif tags
            $working =~ s/$if_tag(.*?)$endif_tag/$3/s;
            $none = 0;
          } else {
            # rip out the conditional crap
            $working =~ s/$if_tag(.*?)$endif_tag//s;
            $none = 0;
            # print "stripped out $if_tag$2$endif_tag\n";
          }
          $file = $working;
        } else {
          last;
        }
      }

      # replace occurances of definitions with their values
      while(1) {
        $_ = $file;
        # print "temp is: $temp\n";
        if(/($temp)/) {
          s/($temp)/$h_define{$key}/g;
          $file = $_;
          $none = 0;
          #print "replaced $temp with $h_define{$key}\n";
        }
        else {
          last;
        }
      }
    }
    if($none) { last; }
  }

  # construct the generic tag and see if we've skipped over any tags
  my $gen_tag = $h_tstyle{define};
  $gen_tag =~ s/\[r\]/\.\*\?/g;
  $gen_tag =~ s/([^a-zA-Z0-9_\.\*\(\)\|\?]{1})/\\$1/g;

  if($file =~ /($gen_tag)/) {
    print "found a tag ($1) in the template $h_template{$template_to_use} that doesn't have a definition in the source file ($source).\n";
  }


  print(DESTINATION $file) or die "error: could not print to $file: $!\n";
  close(DESTINATION) or die "error: could not close $destination$extension: $!\n";
  #print "printed to $file\n";

  close TEMPLATE or die "error: could not close template: $!\n";
}

# copy(sourcdir, ignore, outputdir)
#
# This subroutine copies all directories and files from
# sourcedir into outputdir as long as they do not match
# what is contained in ignore.
sub copy {
    my $dir = shift;
    my $ignore = shift;
    my $output = shift;

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

