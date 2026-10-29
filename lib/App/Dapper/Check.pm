package App::Dapper::Check;

=head1 NAME

App::Dapper::Check - Find the problems in a site without publishing it.

=head1 DESCRIPTION

C<dapper check> builds the site into a temporary directory, collecting every
problem instead of stopping at the first, then looks for links between pages
that lead nowhere. The real output directory is not touched.

    $ dapper check
    $ dapper check --json

It reports:

=over 4

=item * front matter that can't be read, or that doesn't match a C<_schema.yml>

=item * layouts that don't exist, and errors in templates

=item * two pages that would be written to the same file

=item * links and images (C<href> and C<src>) inside the site that lead to no file

=item * settings that need C<url> when it isn't set, and pages without a title

=back

With C<--json>, the report is printed as JSON, for scripts and AI assistants:

    {
      "ok": false,
      "pages": 12,
      "errors":   [ { "file": "...", "type": "...", "message": "..." } ],
      "warnings": [ ... ]
    }

The command exits with status 1 if there are errors, and 0 otherwise.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use File::Temp qw/ tempdir /;
use File::Spec::Functions qw/ catfile /;
use JSON ();

use App::Dapper::Utils;

=head2 run

Takes a Dapper object and returns the report as a hash reference.

=cut

sub run {
    my ($dapper) = @_;

    my $tmp = tempdir(CLEANUP => 1);

    # Build into the temporary directory, collecting problems
    my %saved = map { $_ => $dapper->{$_} } qw/ collect quiet output /;
    my $explicit_output = $dapper->{explicit}->{output};

    $dapper->{collect} = 1;
    $dapper->{quiet} = 1;

    my ($pages, @problems) = (0);
    my $ok = eval {
        # Resolve the real directories first, then build into the temporary one
        $dapper->read_project();
        my $real_output = $dapper->{output};
        $dapper->{output} = catfile($tmp, 'site');
        $dapper->{explicit}->{output} = 1;
        $dapper->build();
        $dapper->{site}->{output} = $real_output;
        1;
    };

    @problems = @{ $dapper->{problems} || [] };
    if (not $ok) {
        (my $message = $@) =~ s/^(?:error): //;
        $message =~ s/\s+\z//;
        push @problems, { severity => 'error', file => $dapper->{config}, message => $message };
    }

    if ($ok) {
        $pages = scalar @{ $dapper->{site}->{pages} };
        push @problems, links($dapper);
        push @problems, warnings($dapper);
    }

    $dapper->{$_} = $saved{$_} for keys %saved;
    $dapper->{explicit}->{output} = $explicit_output;

    for my $problem (@problems) {
        $problem->{type} = classify($problem) unless defined $problem->{type};
    }

    my @errors   = grep { $_->{severity} eq 'error' } @problems;
    my @warnings = grep { $_->{severity} ne 'error' } @problems;

    return {
        ok       => @errors ? JSON::false : JSON::true,
        pages    => $pages,
        errors   => [ map { _clean($_) } @errors ],
        warnings => [ map { _clean($_) } @warnings ],
    };
}

sub _clean {
    my ($problem) = @_;

    # Messages often start with the file they are about; it is in "file" already
    my $message = $problem->{message};
    my $file = defined $problem->{file} ? $problem->{file} : '';
    $message =~ s/^\Q$file\E:?\s+// if length $file;

    return { file => $problem->{file}, type => $problem->{type}, message => $message };
}

=head2 classify

Takes a problem and returns a short name for its kind: C<schema>,
C<front_matter>, C<layout>, C<template>, C<duplicate>, C<link>, C<setting> or
C<other>.

=cut

sub classify {
    my ($problem) = @_;

    my $message = $problem->{message};
    return 'schema'       if $message =~ /schema/;
    return 'front_matter' if $message =~ /front matter|could not understand the date|unknown time zone/;
    return 'layout'       if $message =~ /uses the layout|loop of layouts|names the layout/;
    return 'template'     if $message =~ /could not process/;
    return 'duplicate'    if $message =~ /both write|already writes/;
    return 'setting'      if $message =~ /needs the site|needs a layout|needs Pagefind|must be settings/;
    return 'other';
}

=head2 links

Takes a Dapper object that has just been built, and returns a problem for each
link or image in an HTML page that points to a file the site does not have.

=cut

sub links {
    my ($dapper) = @_;

    my $site = $dapper->{site};
    my $output = $dapper->{output};
    my %source_of = %{ $dapper->{page_owner} || {} };
    my $base = defined $site->{url} ? $site->{url} : '';
    $base =~ s{/+$}{};

    my @problems;

    for my $relative (sort keys %{$dapper->{written}}) {
        next unless $relative =~ /\.html?$/i;
        my $file = catfile($output, $relative);
        my $html = App::Dapper::Utils::read_file($file);
        my $page_dir = '/' . $relative;
        $page_dir =~ s{[^/]*$}{};

        my %seen;
        while ($html =~ /\b(?:href|src)\s*=\s*(["'])(.*?)\1/gis) {
            my $link = $2;
            next if $seen{$link}++;

            my $path = target_path($link, $page_dir, $base);
            next unless defined $path;
            next if $site->{search} and $path =~ m{^/pagefind/};
            next if exists_in($output, $path);

            push @problems, {
                severity => 'error',
                type     => 'link',
                file     => $source_of{$file} || $file,
                message  => "links to $link, which is not in the site",
            };
        }
    }

    return @problems;
}

=head2 target_path

Takes a link, the directory of the page it is on (e.g. C</blog/post/>) and the
site's URL, and returns the path in the site it points to, or nothing for links
that lead outside the site (or to the same page).

=cut

sub target_path {
    my ($link, $page_dir, $base) = @_;

    $link =~ s/^\s+|\s+$//g;
    return if $link eq '' or $link =~ /^#/;

    if (length $base and index($link, $base) == 0) {
        $link = substr($link, length $base);
        $link = '/' unless length $link;
    }

    return if $link =~ m{^[a-z][a-z0-9+.-]*:}i or $link =~ m{^//};

    $link =~ s/[?#].*$//;
    return if $link eq '';

    $link =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
    $link =~ s/&amp;/&/g;

    my $path = $link =~ m{^/} ? $link : "$page_dir$link";

    my @parts;
    for my $part (split m{/}, $path, -1) {
        next if $part eq '.' or ($part eq '' and @parts);
        if ($part eq '..') { pop @parts if @parts > 1; next }
        push @parts, $part;
    }
    my $resolved = join('/', @parts);
    $resolved .= '/' if $path =~ m{/$} and $resolved !~ m{/$};
    $resolved = "/$resolved" unless $resolved =~ m{^/};

    return $resolved;
}

=head2 exists_in

Takes the output directory and a path in the site, and returns true if a file
is there (or, for a directory, an C<index.html> in it).

=cut

sub exists_in {
    my ($output, $path) = @_;

    my $file = catfile($output, $path);
    return 1 if -f $file;
    return 1 if -d $file and (-f catfile($file, 'index.html') or -f catfile($file, 'index.htm'));
    return 0;
}

=head2 warnings

Takes a Dapper object that has just been built, and returns warnings about the
site's settings and pages.

=cut

sub warnings {
    my ($dapper) = @_;

    my $site = $dapper->{site};
    my @problems;

    my $has_url = defined $site->{url} && length $site->{url};
    if (not $has_url) {
        push @problems, {
            severity => 'warning',
            type     => 'setting',
            file     => $dapper->{config},
            message  => 'url is not set, so there is no sitemap, and links in llms.txt and page.seo are not absolute',
        };
    }

    for my $page (@{$site->{pages}}) {
        next if $page->{generated} or $page->{paginator} && $page->{paginator}->{page} > 1;
        next unless defined $page->{filename} and $page->{filename} =~ /\.html?$/i;
        next if defined $page->{title} and length $page->{title};
        push @problems, {
            severity => 'warning',
            type     => 'front_matter',
            file     => $page->{source},
            message  => 'has no title',
        };
    }

    return @problems;
}

=head2 text

Takes a report from L</run> and returns it as text for people.

=cut

sub text {
    my ($report) = @_;

    my $out = '';
    for my $problem (@{$report->{errors}}) {
        $out .= "error: $problem->{file}: $problem->{message}\n";
    }
    for my $problem (@{$report->{warnings}}) {
        $out .= "warning: $problem->{file}: $problem->{message}\n";
    }

    my $errors = @{$report->{errors}};
    my $warnings = @{$report->{warnings}};
    $out .= sprintf("Checked %d page%s: %d error%s, %d warning%s.\n",
        $report->{pages}, $report->{pages} == 1 ? '' : 's',
        $errors, $errors == 1 ? '' : 's',
        $warnings, $warnings == 1 ? '' : 's');

    return $out;
}

1;
