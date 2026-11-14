package App::Dapper::Collections;

=head1 NAME

App::Dapper::Collections - Category pages, tag pages and pagination.

=head1 DESCRIPTION

After the source files are read, Dapper can generate a page for each
category and each tag, and split long lists of pages across several pages.

Category and tag pages are turned on in C<_config.yml>, and are rendered with
the layout you name:

    category_pages:
      layout: category        # _layout/category.html
      urlpattern: /:category/ # the default
      per_page: 10            # optional: split into pages of 10
    tag_pages:
      layout: tag
      urlpattern: /tags/:tag/ # the default

Each generated page has C<page.title> (the category or tag), C<page.category>
or C<page.tag>, and C<page.posts> (its pages, newest first). With C<per_page>,
C<page.posts> holds just the pages for that page, and C<paginator> describes
the whole set. The URL of each one is in C<site.category_pages> and
C<site.tag_pages>, so layouts can link to them:

    <a href="[% site.tag_pages.$tag %]">[% tag %]</a>

Any page can list pages across several pages with C<paginate> in its front
matter:

    paginate:
      category: blog     # or tag: perl; leave both out for every post
      per_page: 10

In its layout (or its content, with C<template: true>), C<paginator.items>
holds that page's share of the posts, newest first.

=head2 The paginator

    paginator.items          the pages to show on this page
    paginator.page           this page's number, starting at 1
    paginator.per_page       pages per page
    paginator.total_pages    how many pages there are
    paginator.total_items    how many items there are
    paginator.previous_url   the URL of the previous page (if there is one)
    paginator.next_url       the URL of the next page (if there is one)
    paginator.first_url, paginator.last_url
    paginator.pages          a list of { number, url } for every page

Page 1 keeps the page's own URL; page 2 is at C<page/2/> below it.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use File::Spec::Functions qw/ canonpath catfile /;

use App::Dapper::Utils;

=head2 generate

Takes the Dapper object, adds category and tag pages to the site if they are
turned on, and expands every paginated page into its set of pages.

=cut

sub generate {
    my ($dapper) = @_;

    my $site = $dapper->{site};

    # The settings from _config.yml; the same names then hold the URL of each
    # generated page
    my %settings = (category => $site->{category_pages}, tag => $site->{tag_pages});
    $site->{category_pages} = {};
    $site->{tag_pages} = {};

    my @generated;
    for my $kind (qw/ category tag /) {
        my $value = $settings{$kind};
        next unless defined $value;
        die "error: ${kind}_pages in $dapper->{config} must be settings such as layout: $kind\n"
            unless ref $value eq 'HASH';
        my $lists = $kind eq 'tag' ? $site->{tags} : $site->{categories};
        push @generated, list_pages($dapper, $kind, $lists, $site->{"${kind}_pages"}, $value);
    }

    my @pages;
    for my $page (@{$site->{pages}}, @generated) {
        push @pages, paginate($dapper, $page);
    }
    $site->{pages} = \@pages;
}

=head2 list_pages

Takes the Dapper object, the kind of list (C<category> or C<tag>), the hash of
names to pages, the hash to record each list page's URL in, and the settings
from C<_config.yml>. Returns the generated pages.

=cut

sub list_pages {
    my ($dapper, $kind, $lists, $urls, $settings) = @_;

    my $site = $dapper->{site};
    my $label = "${kind}_pages";

    die "error: $label in $dapper->{config} needs a layout, e.g. layout: $kind\n"
        unless defined $settings->{layout} and length $settings->{layout};

    my $pattern = defined $settings->{urlpattern} ? $settings->{urlpattern}
                : $kind eq 'tag'                  ? '/tags/:tag/'
                :                                   '/:category/';

    my @pages;
    for my $name (sort keys %$lists) {
        my @posts = reverse @{$lists->{$name}};
        my $value = $kind eq 'tag' ? App::Dapper::Utils::slugify($name) : $name;

        my %page = (
            title     => $name,
            $kind     => $name,
            posts     => \@posts,
            layout    => $settings->{layout},
            extension => $site->{extension},
            date      => $posts[0]->{date},
            content   => '',
            source    => "$label ($name)",
            generated => 1,
            sitemap   => $settings->{sitemap},
        );
        $page{url} = App::Dapper::expand_urlpattern($pattern, { $kind => $value });
        set_filename($dapper, \%page);

        if ($settings->{per_page}) {
            $page{paginate} = { items => \@posts, per_page => $settings->{per_page} };
        }

        $urls->{$name} = $page{url};
        push @pages, \%page;
    }

    return @pages;
}

=head2 paginate

Takes the Dapper object and a page. If the page has C<paginate> settings,
returns the page followed by its further pages, each with a C<paginator>;
otherwise returns the page unchanged.

=cut

sub paginate {
    my ($dapper, $page) = @_;

    my $settings = $page->{paginate};
    return $page unless $settings;

    $settings = { per_page => $settings } unless ref $settings;
    die "error: paginate in $page->{source} must be a number or settings such as per_page: 10\n"
        unless ref $settings eq 'HASH';

    my $per_page = $settings->{per_page} || 10;
    die "error: per_page in $page->{source} must be a whole number above 0\n"
        unless $per_page =~ /^\d+$/ and $per_page > 0;

    my @items = $settings->{items} ? @{$settings->{items}} : items_for($dapper->{site}, $settings);

    my $total_pages = int((@items + $per_page - 1) / $per_page) || 1;
    my $base = base_url($page->{url});

    my @urls = map { $_ == 1 ? $page->{url} : "${base}page/$_/" } 1 .. $total_pages;

    my @pages;
    for my $number (1 .. $total_pages) {
        my $copy = $number == 1 ? $page : { %$page };

        if ($number > 1) {
            $copy->{url} = $urls[$number - 1];
            delete $copy->{markdown};
            delete $copy->{markdown_url};
            set_filename($dapper, $copy, 1);
        }

        my $first = ($number - 1) * $per_page;
        my $last = $first + $per_page - 1;
        $last = $#items if $last > $#items;

        $copy->{paginator} = {
            items        => [ @items > 0 ? @items[$first .. $last] : () ],
            page         => $number,
            per_page     => $per_page,
            total_pages  => $total_pages,
            total_items  => scalar @items,
            previous_url => $number > 1 ? $urls[$number - 2] : undef,
            next_url     => $number < $total_pages ? $urls[$number] : undef,
            first_url    => $urls[0],
            last_url     => $urls[-1],
            pages        => [ map { { number => $_, url => $urls[$_ - 1] } } 1 .. $total_pages ],
        };
        $copy->{posts} = $copy->{paginator}->{items} if $page->{generated};

        push @pages, $copy;
    }

    return @pages;
}

=head2 items_for

Takes the site and pagination settings, and returns the pages to paginate,
newest first: those in the C<category> or with the C<tag>, or every page with
a category if neither is given.

=cut

sub items_for {
    my ($site, $settings) = @_;

    my @items;
    if (defined $settings->{category}) {
        @items = @{ $site->{categories}->{$settings->{category}} || [] };
    }
    elsif (defined $settings->{tag}) {
        @items = @{ $site->{tags}->{$settings->{tag}} || [] };
    }
    else {
        my %seen;
        @items = grep { !$seen{$_}++ } map { @{ $site->{categories}->{$_} } } sort keys %{$site->{categories}};
    }

    return sort { $b->{date} <=> $a->{date} } @items;
}

=head2 base_url

Takes a URL and returns the directory the further pages go in:
C</blog/> stays C</blog/>, and C</archive.html> becomes C</archive/>.

=cut

sub base_url {
    my ($url) = @_;

    return $url if $url =~ m{/$};
    $url =~ s{/index\.[^./]+$}{/};
    return $url if $url =~ m{/$};
    $url =~ s{\.[^./]+$}{};
    return "$url/";
}

=head2 set_filename

Takes the Dapper object and a page with a C<url>, and sets the page's
C<filename> and C<dirname> from it. A URL ending in C</> is written as an
index file.

=cut

sub set_filename {
    my ($dapper, $page, $is_index) = @_;

    my $path = $page->{url};
    $path .= "index$page->{extension}" if $path =~ m{/$};
    $page->{filename} = canonpath(catfile($dapper->{output}, $path));
    (my $dir = $page->{filename}) =~ s{[^/]*$}{};
    $page->{dirname} = $dir;
}

1;
