package Text::Dapper::Utils;

use 5.006;
use strict;
use warnings FATAL => 'all';

use File::Spec::Functions qw/ canonpath /;

my $DEFAULT_LAYOUT = "index";

# Takes a file name and returns a string of the contents
sub read_file {
  my ($file_name) = @_;
    my $file_contents;

    open(FILE, "<$file_name") or die("could not open file: $!\n");
    foreach (<FILE>) { $file_contents .= $_; }
    close(FILE) or die("could not close file: $!\n");

    return $file_contents;
}

# Takes a string, returns <template> part of the first "use <template> template" line.
sub find_template_statement {
    my ($string) = @_;

    if($string =~ /^use\s+([a-zA-Z0-9_]+)\s+template/) { return $1; }
    
    return $DEFAULT_LAYOUT;
}

# Takes a string, removes all "use <template> template" statements and returns what's left.
sub filter_template_statements {
    my ($string) = @_;

    $string =~ s/^(use\s+[a-zA-Z0-9_]+\s+template)//g;
    
    return $string;
}

sub filter_extension {
    my ($filename) = @_;
    $filename = canonpath $filename;

    my ($ext) = $filename =~ /(\.[^.]+)$/;
   
    return $ext;
}

sub filter_stem {
    my ($filename) = @_;
    $filename = canonpath $filename;
    
    (my $stem = $filename) =~ s/\.[^.]+$//;

    return $stem;
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

1;
