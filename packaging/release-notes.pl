#!/usr/bin/env perl
# Print the GitHub release notes for a version: its entry from Changes, as
# Markdown, followed by the ways to install it.
# Usage: perl packaging/release-notes.pl 1.00
use strict;
use warnings;

my $version = shift or die "usage: $0 <version>\n";

open(my $fh, '<', 'Changes') or die "error: could not read Changes: $!\n";
my ($found, @lines);
while (<$fh>) {
    if (/^(\S+)\s/) {
        last if $found;
        $found = 1 if $1 eq $version;
        next;
    }
    push @lines, $_ if $found;
}
close $fh;
die "error: Changes has no entry for $version\n" unless $found;

# Paragraphs are separated by blank lines; join each one's lines
my @paragraphs = grep { length } map { s/^\s+|\s+$//gr =~ s/\s*\n\s*/ /gr } split /\n\s*\n/, join('', @lines);

for my $paragraph (@paragraphs) {
    # "Added: ..." and "Changed: ..." become a list; anything else stays text
    if ($paragraph =~ s/^(Added|Changed|Fixed|Removed):\s*/- **$1:** /) {
        print "$paragraph\n";
    }
    else {
        print "$paragraph\n\n";
    }
}

print <<"END";

## Install

    brew install markdbenson/tap/dapper     # Homebrew, on macOS or Linux
    cpanm App::Dapper                       # CPAN

With Docker, with nothing else installed:

    docker run --rm -v "\$PWD":/site ghcr.io/markdbenson/dapper:$version build

Or as a single file that runs with any Perl 5.10 or newer:

    curl -fsSLo dapper https://github.com/markdbenson/dapper/releases/download/v$version/dapper
    chmod +x dapper

See the [README](https://github.com/markdbenson/dapper#readme) to get started, and [Changes](https://github.com/markdbenson/dapper/blob/master/Changes) for every release.
END
