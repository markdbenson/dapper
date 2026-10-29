package App::Dapper::Publish;

=head1 NAME

App::Dapper::Publish - Sitemaps, feeds, Markdown copies, llms.txt and SEO tags.

=head1 DESCRIPTION

After the pages of a site are rendered, Dapper writes files that help search
engines, feed readers and AI tools find and read them. Each is controlled by a
setting in C<_config.yml>:

    url: https://example.com   # needed for absolute links in all of these
    markdown_twins: true       # page.md next to each Markdown page's HTML
    llms_txt: true             # /llms.txt and /llms-full.txt
    sitemap: true              # /sitemap.xml
    feed:                      # /feed.xml (off unless set)
      category: blog
      limit: 20

It also builds C<page.seo>, the tags a layout can put in its C<< <head> >>:
a description, a canonical link, Open Graph and Twitter tags, a feed link,
and JSON-LD structured data.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use JSON ();
use File::Spec;

use App::Dapper::Filters;
use App::Dapper::Utils;

=head2 absolute_url

Takes the site and a URL relative to the site root (e.g. C</about/>) and
returns it with C<site.url> in front, or unchanged if C<site.url> is not set
or the URL is already absolute.

=cut

sub absolute_url {
    my ($site, $url) = @_;

    return $url unless defined $url and length $url;
    return $url if $url =~ m{^[a-z][a-z0-9+.-]*:}i;

    my $base = $site->{url};
    return $url unless defined $base and length $base;

    $base =~ s{/+$}{};
    $url = "/$url" unless $url =~ m{^/};
    return "$base$url";
}

=head2 plain_text

Takes HTML and returns its text: tags removed, common entities decoded and
white space collapsed.

=cut

sub plain_text {
    my ($html) = @_;

    return '' unless defined $html;

    my $text = $html;
    $text =~ s/<[^>]*>//g;
    $text =~ s/&nbsp;/ /g;
    $text =~ s/&lt;/</g;
    $text =~ s/&gt;/>/g;
    $text =~ s/&quot;/"/g;
    $text =~ s/&#39;/'/g;
    $text =~ s/&amp;/&/g;
    $text =~ s/\s+/ /g;
    $text =~ s/^ | $//g;

    return $text;
}

=head2 description

Takes a page and returns its description: its C<description> setting, or the
text of its excerpt, shortened to about 200 characters.

=cut

sub description {
    my ($page) = @_;

    my $text = defined $page->{description} && !ref $page->{description}
        ? $page->{description}
        : plain_text($page->{excerpt});

    if (length $text > 200) {
        $text = substr($text, 0, 200);
        $text =~ s/\s+\S*$//;
        $text .= '...';
    }

    return $text;
}

=head2 is_html

Returns true if a page's output is an HTML file.

=cut

sub is_html {
    my ($page) = @_;
    return defined $page->{filename} && $page->{filename} =~ /\.html?$/i;
}

=head2 enabled

Takes the site and the name of a setting, and returns true unless the setting
is off (false, 0, "false" or "no").

=cut

sub enabled {
    my ($site, $name) = @_;

    my $value = $site->{$name};
    return 1 unless defined $value;
    return 0 if !ref $value and $value =~ /^(?:0|false|no|off|)$/i;
    return 1;
}

=head2 twin_path

Takes a page and returns the output path of its Markdown copy:
C<blog/post/index.html> becomes C<blog/post/index.md>.

=cut

sub twin_path {
    my ($page) = @_;

    (my $path = $page->{filename}) =~ s/\.[^.\/]+$/.md/;
    return $path;
}

=head2 twin_url

Takes a page and returns the URL of its Markdown copy: C</blog/post/>
becomes C</blog/post/index.md>.

=cut

sub twin_url {
    my ($page) = @_;

    my $url = $page->{url};
    return $url . 'index.md' if $url =~ m{/$};
    $url =~ s/\.[^.\/]+$/.md/;
    return $url;
}

=head2 has_twin

Returns true if a page gets a Markdown copy: it is an HTML page made from a
Markdown file, it has not turned it off (C<markdown_twin: false>), and its
Markdown is not a template (which would show template code, not text).

=cut

sub has_twin {
    my ($site, $page) = @_;

    return 0 unless enabled($site, 'markdown_twins');
    return 0 unless ($page->{source_file_extension} || '') eq '.md';
    return 0 unless is_html($page);
    return 0 if defined $page->{markdown_twin} and !enabled($page, 'markdown_twin');
    return 0 unless defined $page->{markdown};

    my $templated = $page->{template} || $site->{templates_in_content};
    return 0 if $templated and $page->{markdown} =~ /\[%/;

    return 1;
}

=head2 twin

Takes the site and a page, and returns the text of its Markdown copy: the
title as a heading, the description as a quote, and the page's Markdown.

=cut

sub twin {
    my ($site, $page) = @_;

    my $text = '';
    $text .= "# $page->{title}\n\n" if defined $page->{title} and length $page->{title};

    my $description = defined $page->{description} && !ref $page->{description} ? $page->{description} : '';
    $text .= "> $description\n\n" if length $description;

    my $body = $page->{markdown};
    $body =~ s/^\s+//;
    $body =~ s/\s+\z//;

    return "$text$body\n";
}

=head2 llms_txt

Takes the site and the pages that have Markdown copies, and returns the text
of C</llms.txt>: the site's name and description, then a list of links to the
Markdown copies, grouped by category (newest first), with other pages last.

=cut

sub llms_txt {
    my ($site, $pages) = @_;

    $pages = [ grep { _in_llms($_) } @$pages ];

    my $text = "# " . (defined $site->{name} ? $site->{name} : 'Site') . "\n\n";
    $text .= "> $site->{description}\n\n" if defined $site->{description} and length $site->{description};

    my (%by_category, @other, %seen);
    for my $page (@$pages) {
        my $category = _first_category($page);
        if (defined $category) { push @{$by_category{$category}}, $page }
        else                   { push @other, $page }
    }

    for my $category (sort keys %by_category) {
        $text .= "## " . ucfirst($category) . "\n\n";
        for my $page (sort { $b->{date} <=> $a->{date} } @{$by_category{$category}}) {
            $text .= _llms_line($site, $page);
        }
        $text .= "\n";
    }

    if (@other) {
        $text .= "## Pages\n\n";
        $text .= _llms_line($site, $_) for @other;
        $text .= "\n";
    }

    return $text;
}

sub _in_llms {
    my ($page) = @_;
    return !(defined $page->{llms} and !enabled($page, 'llms'));
}

sub _llms_line {
    my ($site, $page) = @_;

    my $title = defined $page->{title} && length $page->{title} ? $page->{title} : $page->{url};
    my $line = "- [$title](" . absolute_url($site, twin_url($page)) . ")";
    my $description = description($page);
    $line .= ": $description" if length $description;
    return "$line\n";
}

sub _first_category {
    my ($page) = @_;

    my $categories = $page->{categories};
    return $categories->[0] if ref $categories eq 'ARRAY' and @$categories;
    return $categories if defined $categories and !ref $categories and length $categories;
    return;
}

=head2 llms_full_txt

Takes the site and the pages that have Markdown copies, and returns the text
of C</llms-full.txt>: every Markdown copy, one after another, each with its
URL.

=cut

sub llms_full_txt {
    my ($site, $pages) = @_;

    $pages = [ grep { _in_llms($_) } @$pages ];

    my $text = "# " . (defined $site->{name} ? $site->{name} : 'Site') . "\n\n";
    $text .= "> $site->{description}\n\n" if defined $site->{description} and length $site->{description};

    for my $page (@$pages) {
        $text .= "---\n\nURL: " . absolute_url($site, $page->{url}) . "\n\n" . twin($site, $page) . "\n";
    }

    return $text;
}

=head2 sitemap

Takes the site and its pages, and returns the text of C</sitemap.xml>,
listing every HTML page that has not turned it off with C<sitemap: false>.
Needs C<site.url>.

=cut

sub sitemap {
    my ($site, $pages) = @_;

    my $xml = qq{<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n};

    for my $page (@$pages) {
        next unless is_html($page);
        next if defined $page->{sitemap} and !enabled($page, 'sitemap');
        next if $page->{url} =~ m{(?:^|/)404\.html$};

        $xml .= "  <url>\n";
        $xml .= "    <loc>" . App::Dapper::Filters::xml_escape(absolute_url($site, $page->{url})) . "</loc>\n";
        my $modified = _modified($page);
        $xml .= "    <lastmod>" . $modified->xmlschema . "</lastmod>\n" if $modified;
        $xml .= "  </url>\n";
    }

    $xml .= "</urlset>\n";
    return $xml;
}

sub _modified {
    my ($page) = @_;

    my $date = defined $page->{updated} ? eval { App::Dapper::Utils::parse_date($page->{updated}) } : undef;
    $date = $page->{date} unless $date;
    return ref $date && eval { $date->can('xmlschema') } ? $date : undef;
}

=head2 feed_settings

Takes the site and returns the feed settings (C<path>, C<category>, C<limit>,
C<title>) if a feed is turned on, or nothing if it is not. C<feed: true>
turns on a feed of every page with a category.

=cut

sub feed_settings {
    my ($site) = @_;

    my $feed = $site->{feed};
    return unless defined $feed;
    return unless ref $feed or enabled($site, 'feed');

    my %settings = ref $feed eq 'HASH' ? %$feed : ();
    $settings{path}  = '/feed.xml' unless defined $settings{path};
    $settings{limit} = 20 unless defined $settings{limit};
    $settings{title} = $site->{name} unless defined $settings{title};
    $settings{path}  = "/$settings{path}" unless $settings{path} =~ m{^/};

    return \%settings;
}

=head2 feed_pages

Takes the site and the feed settings, and returns the pages in the feed:
those in the feed's category (or with any category), newest first, up to the
limit.

=cut

sub feed_pages {
    my ($site, $settings) = @_;

    my @pages;
    if (defined $settings->{category}) {
        @pages = @{ $site->{categories}->{$settings->{category}} || [] };
    }
    else {
        my %seen;
        @pages = grep { !$seen{$_}++ } map { @{ $site->{categories}->{$_} } } keys %{$site->{categories}};
    }

    @pages = sort { $b->{date} <=> $a->{date} } grep { is_html($_) } @pages;
    splice(@pages, $settings->{limit}) if $settings->{limit} and @pages > $settings->{limit};

    return \@pages;
}

=head2 feed

Takes the site, the feed settings and the pages in the feed, and returns an
Atom feed.

=cut

sub feed {
    my ($site, $settings, $pages) = @_;

    my $esc = \&App::Dapper::Filters::xml_escape;
    my $home = absolute_url($site, '/');
    my $self_url = absolute_url($site, $settings->{path});
    my $updated = @$pages ? _modified($pages->[0]) : $site->{time};
    $updated = $site->{time} unless $updated;

    my $xml = qq{<?xml version="1.0" encoding="utf-8"?>\n<feed xmlns="http://www.w3.org/2005/Atom">\n};
    $xml .= "  <title>" . $esc->($settings->{title}) . "</title>\n";
    $xml .= "  <subtitle>" . $esc->($site->{description}) . "</subtitle>\n" if defined $site->{description};
    $xml .= qq{  <link href="} . $esc->($home) . qq{"/>\n};
    $xml .= qq{  <link rel="self" href="} . $esc->($self_url) . qq{"/>\n};
    $xml .= "  <id>" . $esc->($home) . "</id>\n";
    $xml .= "  <updated>" . $updated->xmlschema . "</updated>\n";
    $xml .= "  <author><name>" . $esc->($site->{author}) . "</name></author>\n" if defined $site->{author};

    for my $page (@$pages) {
        my $url = absolute_url($site, $page->{url});
        my $modified = _modified($page);
        $xml .= "  <entry>\n";
        $xml .= "    <title>" . $esc->(defined $page->{title} ? $page->{title} : $page->{url}) . "</title>\n";
        $xml .= qq{    <link href="} . $esc->($url) . qq{"/>\n};
        $xml .= "    <id>" . $esc->($url) . "</id>\n";
        $xml .= "    <published>" . $page->{date}->xmlschema . "</published>\n";
        $xml .= "    <updated>" . $modified->xmlschema . "</updated>\n" if $modified;
        $xml .= "    <author><name>" . $esc->($page->{author}) . "</name></author>\n"
            if defined $page->{author} and !ref $page->{author};
        my $summary = description($page);
        $xml .= "    <summary>" . $esc->($summary) . "</summary>\n" if length $summary;
        $xml .= qq{    <content type="html">} . $esc->($page->{content}) . "</content>\n";
        $xml .= "  </entry>\n";
    }

    $xml .= "</feed>\n";
    return $xml;
}

=head2 seo

Takes the site and a page, and returns the HTML for C<page.seo>: tags for the
page's C<< <head> >>.

=cut

sub seo {
    my ($site, $page) = @_;

    my $esc = \&App::Dapper::Filters::xml_escape;
    my @tags;

    my $title = defined $page->{title} && !ref $page->{title} ? $page->{title} : $site->{name};
    my $description = description($page);
    my $has_url = defined $site->{url} && length $site->{url};
    my $url = absolute_url($site, $page->{url});
    my $is_article = defined _first_category($page);
    my $image = defined $page->{image} && !ref $page->{image} ? $page->{image}
              : defined $site->{image} && !ref $site->{image} ? $site->{image}
              : undef;
    $image = absolute_url($site, $image) if defined $image;

    push @tags, qq{<meta name="description" content="} . $esc->($description) . qq{">} if length $description;
    push @tags, qq{<link rel="canonical" href="} . $esc->($url) . qq{">} if $has_url;
    push @tags, qq{<link rel="alternate" type="text/markdown" href="} . $esc->(absolute_url($site, $page->{markdown_url})) . qq{">}
        if defined $page->{markdown_url};

    if (my $feed = feed_settings($site)) {
        push @tags, qq{<link rel="alternate" type="application/atom+xml" title="} . $esc->($feed->{title})
            . qq{" href="} . $esc->(absolute_url($site, $feed->{path})) . qq{">};
    }

    push @tags, qq{<meta property="og:type" content="} . ($is_article ? 'article' : 'website') . qq{">};
    push @tags, qq{<meta property="og:title" content="} . $esc->($title) . qq{">} if defined $title;
    push @tags, qq{<meta property="og:description" content="} . $esc->($description) . qq{">} if length $description;
    push @tags, qq{<meta property="og:url" content="} . $esc->($url) . qq{">} if $has_url;
    push @tags, qq{<meta property="og:site_name" content="} . $esc->($site->{name}) . qq{">} if defined $site->{name};
    push @tags, qq{<meta property="og:image" content="} . $esc->($image) . qq{">} if defined $image;
    push @tags, qq{<meta property="article:published_time" content="} . $page->{date}->xmlschema . qq{">}
        if $is_article and ref $page->{date};
    push @tags, qq{<meta name="twitter:card" content="} . (defined $image ? 'summary_large_image' : 'summary') . qq{">};

    my %data = (
        '@context' => 'https://schema.org',
        '@type'    => $is_article ? 'BlogPosting' : 'WebPage',
    );
    $data{headline}    = $title if defined $title;
    $data{name}        = $title if defined $title and !$is_article;
    $data{description} = $description if length $description;
    $data{url}         = $url if $has_url;
    $data{image}       = $image if defined $image;
    if ($is_article and ref $page->{date}) {
        $data{datePublished} = $page->{date}->xmlschema;
        my $modified = _modified($page);
        $data{dateModified} = $modified->xmlschema if $modified;
    }
    my $author = defined $page->{author} && !ref $page->{author} ? $page->{author} : $site->{author};
    $data{author} = { '@type' => 'Person', name => $author } if defined $author and !ref $author;
    $data{publisher} = { '@type' => 'Organization', name => $site->{name} } if $is_article and defined $site->{name};
    $data{mainEntityOfPage} = $url if $is_article and $has_url;

    my $json = JSON->new->canonical->encode(\%data);
    $json =~ s{</}{<\\/}g;
    push @tags, qq{<script type="application/ld+json">$json</script>};

    return join("\n", @tags);
}

1;
