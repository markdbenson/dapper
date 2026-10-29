package App::Dapper::Utils;

=head1 NAME

App::Dapper::Utils - Common utility functions used throughout Dapper.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use POSIX;
use Unicode::Normalize;
use File::Spec;
use File::Spec::Functions qw/ canonpath catfile /;
use File::Path qw/ make_path /;
use File::Basename qw/ dirname /;
use File::Copy ();
use File::Find ();
use Cwd qw/ abs_path /;
use YAML::PP qw/ Load /;
use DateTime::Format::XSD;

=head2 read_file

Read a file and return a scalar with the file's contents, decoded as UTF-8.

=cut

sub read_file {
    my ($file_name) = @_;

    open(my $fh, "<:encoding(UTF-8)", $file_name)
        or die "error: could not open \"$file_name\": $!\n";
    my $file_contents = do { local $/; <$fh> };
    close($fh) or die "error: could not close \"$file_name\": $!\n";

    return defined $file_contents ? $file_contents : '';
}

=head2 write_file

Takes a file name and a string, creates any missing parent directories, and
writes the string to the file encoded as UTF-8.

=cut

sub write_file {
    my ($file_name, $content) = @_;

    my $dir = dirname($file_name);
    make_path($dir) unless -d $dir;

    open(my $fh, ">:encoding(UTF-8)", $file_name)
        or die "error: could not open \"$file_name\" for writing: $!\n";
    print $fh $content or die "error: could not write to \"$file_name\": $!\n";
    close($fh) or die "error: could not close \"$file_name\": $!\n";
}

=head2 has_frontmatter

Takes a file name and returns true if the file begins with a YAML front matter
delimiter (C<--->). Only the first few bytes are read, so this is safe to call
on binary files.

=cut

sub has_frontmatter {
    my ($file_name) = @_;

    open(my $fh, "<:raw", $file_name)
        or die "error: could not open \"$file_name\": $!\n";
    my $read = read($fh, my $head, 64);
    close($fh);

    return 0 unless $read;
    return $head =~ /\A(?:\xEF\xBB\xBF)?---[ \t]*(?:\r?\n|\z)/ ? 1 : 0;
}

=head2 split_frontmatter

Takes a string (and a name used in error messages) and splits it into its YAML
front matter and its body. The front matter must start on the first line and
be closed by a line containing only C<--->. Returns a list of the parsed front
matter (a hash reference) and the body, or an empty list if the string does
not start with front matter.

=cut

sub split_frontmatter {
    my ($text, $name) = @_;

    return unless defined $text;
    return unless $text =~ /\A\x{FEFF}?---[ \t]*\r?\n(.*?)^---[ \t]*(?=\r?\n|\z)(.*)\z/ms;

    my ($yaml, $body) = ($1, $2);

    my $data = eval { Load($yaml) };
    die "error: could not parse front matter in \"$name\": $@" if $@;

    $data = {} unless defined $data;
    die "error: front matter in \"$name\" must be a set of key: value pairs\n"
        unless ref $data eq 'HASH';

    return ($data, $body);
}

=head2 parse_date

Takes a date string and returns a L<DateTime> object. Accepts ISO 8601 / XML
Schema date-times (C<2014-05-02T10:30:00>, optionally with a time zone), the
pre-0.19 format with a space instead of a C<T> (C<2014-05-02 10:30:00>), and
plain dates (C<2014-05-02>). Dies with a helpful message otherwise.

=cut

sub parse_date {
    my ($input, $name) = @_;

    if (ref $input and eval { $input->isa('DateTime') }) {
        return $input->isa('App::Dapper::Date') ? $input : bless($input->clone, 'App::Dapper::Date');
    }

    my $date = defined $input ? "$input" : '';
    $date =~ s/^\s+|\s+$//g;
    $date =~ s/^(\d{4}-\d{2}-\d{2})[ ]+(\d)/$1T$2/;
    $date .= "T00:00:00" if $date =~ /^\d{4}-\d{2}-\d{2}$/;
    $date .= ":00" if $date =~ /T\d{2}:\d{2}$/;

    my $dt = eval { DateTime::Format::XSD->parse_datetime($date) };
    die "error: could not understand the date \"$input\""
        . (defined $name ? " in \"$name\"" : "")
        . ". Use the ISO 8601 format, e.g. 2014-05-02T10:30:00\n"
        unless $dt;

    return bless($dt, 'App::Dapper::Date');
}

=head2 get_modified_time

Takes a file and returns the last modified time of the file.

=cut

sub get_modified_time {
    my ($file) = @_;
    my $date = POSIX::strftime( "%Y-%m-%dT%H:%M:%S", localtime((stat $file)[9]));
    return $date;
}

=head2 slugify

Takes an input string (e.g. the title of a blog post) and "slugifies" it, meaning that
it removes non-ASCII characters, removes all non-word characters (e.g. '_', '-', etc.),
removes leading and trailing whitespace, replaces spaces with hyphens, and converts to
lowercase.

=cut

sub slugify {
    my ($input) = @_;

    if (not defined $input) { return; }

    $input = NFKD($input);         # Normalize the Unicode string
    $input =~ tr/\000-\177//cd;    # Strip non-ASCII characters (>127)
    $input =~ s/[^\w\s-]//g;       # Remove all characters that are not word characters (includes _), spaces, or hyphens
    $input =~ s/^\s+|\s+$//g;      # Trim whitespace from both ends
    $input = lc($input);
    $input =~ s/[-\s]+/-/g;        # Replace all occurrences of spaces and hyphens with a single hyphen

    return $input;
}

=head2 filter_extension

Takes a string (filename) and returns the extension.

=cut

sub filter_extension {
    my ($filename) = @_;
    $filename = canonpath $filename;

    my ($ext) = $filename =~ /(\.[^.\/]+)$/;

    return $ext;
}

=head2 filter_stem

Takes a filename and returns the stem of the file name (without the extension).

=cut

sub filter_stem {
    my ($filename) = @_;
    $filename = canonpath $filename;

    (my $stem = $filename) =~ s/\.[^.\/]+$//;

    return $stem;
}

=head2 create_file

Takes a file name and a string of the content and writes it to disk. Dies if
the file already exists.

=cut

sub create_file {
    my ($filename, $content) = @_;
    die "Invalid number of arguments to create_file" if @_ != 2;
    $filename = canonpath $filename;
    die "error: \"$filename\" already exists\n" if -e $filename;

    print "Creating $filename\n";
    write_file($filename, $content);
}

=head2 create_dir

Takes a directory name and creates it (and any missing parents) on disk.

=cut

sub create_dir {
    my ($dirname) = @_;
    die "Invalid number of arguments to create_dir" if @_ != 1;
    $dirname = canonpath $dirname;

    return if -d $dirname;
    make_path($dirname)
        or die "error: could not create directory \"$dirname\": $!\n";
}

=head2 copy_recursive

Takes a source path (a file or directory), a destination path, and an
optional list of absolute paths to skip. Copies the source to the
destination, recursing into directories and creating them as needed. No shell
is involved, so file names with spaces or special characters are safe.

=cut

sub copy_recursive {
    my ($source, $destination, @skip) = @_;

    my %skip = map { $_ => 1 } grep { defined } map { abs_path($_) } @skip;

    if (-f $source) {
        _copy_file($source, $destination);
        return;
    }

    die "error: \"$source\" is not a file or directory\n" unless -d $source;

    File::Find::find({
        no_chdir => 1,
        wanted   => sub {
            my $path = $File::Find::name;
            if (-d $path) {
                my $abs = abs_path($path);
                if (defined $abs and $skip{$abs}) { $File::Find::prune = 1; return; }
            }
            my $relative = File::Spec->abs2rel($path, $source);
            my $target = $relative eq '.' ? $destination : catfile($destination, $relative);
            if (-d $path) { make_path($target) unless -d $target; }
            elsif (-f $path) { _copy_file($path, $target); }
        },
    }, $source);
}

sub _copy_file {
    my ($source, $destination) = @_;

    my $dir = dirname($destination);
    make_path($dir) unless -d $dir;

    File::Copy::copy($source, $destination)
        or die "error: could not copy \"$source\" to \"$destination\": $!\n";
}

package App::Dapper::Date;

=head1 App::Dapper::Date

Dates in Dapper (C<page.date>, C<site.time>) are L<DateTime> objects with one
extra method, C<xmlschema>, which returns the date in XML Schema format with
its time zone. Template filters only apply to plain strings, so use the
method form for dates:

    <updated>[% page.date.xmlschema %]</updated>

=cut

our @ISA = ('DateTime');

sub xmlschema {
    my ($self) = @_;
    return DateTime::Format::XSD->format_datetime($self);
}

1;
