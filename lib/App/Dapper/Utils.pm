package App::Dapper::Utils;

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.14.0;
use strict;
use warnings FATAL => 'all';

use POSIX;
use Unicode::Normalize;
use File::Spec::Functions qw/ canonpath /;

my $DEFAULT_LAYOUT = "index";

=head2 read_file

Read a file and return a scalar with the file's contents.

=cut

# Takes a file name and returns a string of the contents
sub read_file {
  my ($file_name) = @_;
    my $file_contents;

    #print "Reading contents of $file_name\n";

    open(FILE, "<:encoding(UTF-8)", "$file_name") or die("could not open file: $!\n");
    foreach (<FILE>) { $file_contents .= $_; }
    close(FILE) or die("could not close file: $!\n");

    return $file_contents;
}

=head2 get_modified_time

Takes a file and returns the last modified time of the file.

=cut

sub get_modified_time {
    my ($file) = @_;
    my $date = POSIX::strftime( "%Y-%m-%d %H:%M:%S", localtime((stat $file)[9]));
    return $date;
}

=head2 slugify

Takes an input string (e.g. the title of a blog post) and "slugifies" it, meaning that
it removes non-ASCII characters, removes all non-word characters (e.g. '_', '-', etc.), 
and removes leading and trailing whitespace.

=cut

sub slugify {
    my ($input) = @_;

    if (not defined $input) { return; }

    #print "Slugifying $input\n";

    $input = NFKD($input);         # Normalize the Unicode string
    $input =~ tr/\000-\177//cd;    # Strip non-ASCII characters (>127)
    $input =~ s/[^\w\s-]//g;       # Remove all characters that are not word characters (includes _), spaces, or hyphens
    $input =~ s/^\s+|\s+$//g;      # Trim whitespace from both ends
    $input = lc($input);
    $input =~ s/[-\s]+/-/g;        # Replace all occurrences of spaces and hyphens with a single hyphen

    return $input;
}

=head2 find_template_statement

Takes a string, returns <template> part of the first "use <template> template" line.

=cut

sub find_template_statement {
    my ($string) = @_;

    if($string =~ /^use\s+([a-zA-Z0-9_]+)\s+template/) { return $1; }
    
    return $DEFAULT_LAYOUT;
}

=head2 filter_template_statements

Takes a string, removes all "use <template> template" statements and returns what's left.

=cut

sub filter_template_statements {
    my ($string) = @_;

    $string =~ s/^(use\s+[a-zA-Z0-9_]+\s+template)//g;
    
    return $string;
}

=head2 filter_extension

Takes a string (filename) and returns the extension.

=cut

sub filter_extension {
    my ($filename) = @_;
    $filename = canonpath $filename;

   my ($ext) = $filename =~ /(\.[^.]+)$/;
   
    return $ext;
}

=head2 filter_stem

Takes a filename and returns the stem of the file name (without the extension).

=cut

sub filter_stem {
    my ($filename) = @_;
    $filename = canonpath $filename;
    
    (my $stem = $filename) =~ s/\.[^.]+$//;

    return $stem;
}

=head2 create_file

Takes a file name and a string of the content and writes it to disk.

=cut
 
sub create_file {
    my ($filename, $content) = @_;
    $filename = canonpath $filename;
    print "Creating $filename\n";
    die "Invalid number of arguments to create_file" if @_ != 2;
    
    #open(my $fh, '+>:encoding(UTF-8)', $filename)
    open(my $fh, '+>', $filename)
        or die "Could not open file '$filename' $!";

    print $fh $content;
    close $fh;
}

=head2 create_dir

Takes a directory name and creates it on disk.

=cut

sub create_dir {
    my ($dirname) = @_;
    $dirname = canonpath $dirname;
    die "Invalid number of arguments to create_dir" if @_ != 1;

    mkdir($dirname)
        or die "Could not create directory '$dirname' $!";
}

1;
