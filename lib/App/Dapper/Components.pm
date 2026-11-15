package App::Dapper::Components;

=head1 NAME

App::Dapper::Components - Callouts, videos, galleries and more in Markdown.

=head1 DESCRIPTION

Components add things Markdown can't express, without template code. A
component starts with three colons and its name. Most wrap Markdown and end
with three colons on a line of their own:

    ::: warning "Before you start"
    Back up your site first. **Really.**
    :::

    ::: details "Show the full list"
    - one
    - two
    :::

    ::: gallery
    ![The shop](shop.jpg)
    ![The team](team.jpg)
    :::

Others are a single line:

    ::: youtube https://www.youtube.com/watch?v=dQw4w9WgXcQ "Our story"
    ::: vimeo 76979871 "A short film"
    ::: button /contact/ "Get in touch"
    ::: figure shop.jpg "The shop at night" "Open until 9pm on Fridays"
    ::: map "1 Main Street, Springfield"

The built-in components are:

=over 4

=item B<note>, B<tip>, B<warning>, B<important>, B<callout>

A box that stands out from the text, with an optional title. C<::: callout
tip> is the same as C<::: tip>. HTML: C<< <aside class="callout
callout-tip"> >>.

=item B<details>

A section that opens when clicked, with the summary given.

=item B<gallery>

The images inside, in a C<< <div class="gallery"> >>, for a grid.

=item B<youtube>, B<vimeo>

An embedded video, from its address or ID, with a title for screen readers.
YouTube videos use youtube-nocookie.com.

=item B<button>

A link styled as a button: C<< <a class="button"> >>.

=item B<figure>

An image with alt text and an optional caption.

=item B<map>

A map of an address, from Google Maps.

=back

Words after the name are its arguments; put quotes around ones with spaces.
To nest a component inside another, give the outer one more colons:

    :::: note
    ::: details "More"
    Hidden text
    :::
    ::::

=head2 Components of your own

A theme or site can add components, or change how the built-in ones look, with
templates in C<_layout/components>. C<_layout/components/pricing.html> is
used for C<::: pricing>, with these variables:

    args      The arguments: args.0 is the first, args.size how many,
              and args.list all of them, for FOR loops
    content   The HTML of the Markdown inside it (empty for a single line)
    page      The page
    site      The site

Arguments written as C<name=value> are also available by name, as
C<args.name>. A component is a single line unless a matching line of colons
closes it.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use Text::ParseWords ();

my %CALLOUTS = map { $_ => 1 } qw/ note tip warning important caution info /;
my %SINGLE_LINE = map { $_ => 1 } qw/ youtube vimeo button figure map /;
my %WRAPPING = map { $_ => 1 } (keys %CALLOUTS, qw/ callout details gallery /);

=head2 names

Returns the names of the built-in components.

=cut

sub names {
    return sort(keys %SINGLE_LINE, keys %WRAPPING);
}

=head2 expand

Takes Markdown, a function that turns Markdown into HTML, and options:
C<layout> (the layout directory, for components of your own), C<vars> (the
C<page> and C<site> for their templates) and C<unknown> (an array reference to
collect the names of components that don't exist). Returns the Markdown with
each component replaced by a placeholder line, and the HTML for each
placeholder.

=cut

sub expand {
    my ($text, $to_html, $options) = @_;

    my @lines = split /\n/, $text, -1;
    my (@out, @html);

    my $i = 0;
    while ($i < @lines) {
        my $line = $lines[$i];
        my ($colons, $name, $rest) = $line =~ /^[ ]{0,3}(:{3,})[ \t]*([A-Za-z][\w-]*)[ \t]*(.*?)[ \t]*$/;
        if (not defined $name) {
            push @out, $line;
            $i++;
            next;
        }
        $name = lc $name;

        my $template = template($options, $name);
        my $known = defined $template || $SINGLE_LINE{$name} || $WRAPPING{$name};
        if (not $known) {
            push @{$options->{unknown}}, $name if $options->{unknown};
            push @out, $line;
            $i++;
            next;
        }

        # Find the line that closes it: the same number of colons, alone
        my $end;
        if (!$SINGLE_LINE{$name} or defined $template) {
            for my $j ($i + 1 .. $#lines) {
                if ($lines[$j] =~ /^[ ]{0,3}\Q$colons\E[ \t]*$/) { $end = $j; last }
                # Another component opening first means this one is a single line
                last if $lines[$j] =~ /^[ ]{0,3}\Q$colons\E[ \t]*[A-Za-z]/;
            }
        }

        my $body = '';
        if (defined $end and not $SINGLE_LINE{$name}) {
            $body = join("\n", @lines[$i + 1 .. $end - 1]);
        }
        elsif ($WRAPPING{$name} and not defined $template) {
            # A component that wraps text but is never closed is left as text
            push @out, $line;
            $i++;
            next;
        }
        else {
            undef $end;
        }

        my @args = parse_args($rest);
        my $inner = length $body ? $to_html->($body, $options) : '';
        my $result = defined $template
            ? render_template($template, $name, \@args, $inner, $options)
            : built_in($name, \@args, $inner);

        push @html, $result;
        push @out, '', "DAPPERCOMPONENT$#html", '';
        $i = defined $end ? $end + 1 : $i + 1;
    }

    return (join("\n", @out), \@html);
}

=head2 parse_args

Takes the text after a component's name and returns its arguments: words, or
quoted text.

=cut

sub parse_args {
    my ($text) = @_;
    return () unless defined $text and length $text;
    my @words = Text::ParseWords::shellwords($text);
    return @words ? @words : split ' ', $text;
}

=head2 template

Takes the options given to L</expand> and a component name, and returns the
path of its template in C<_layout/components>, if there is one.

=cut

sub template {
    my ($options, $name) = @_;

    return unless defined $options->{layout};
    for my $ext (qw/ .html .htm .tt /) {
        my $path = "$options->{layout}/components/$name$ext";
        return $path if -f $path;
    }
    return;
}

=head2 render_template

Renders a component of your own with its template.

=cut

sub render_template {
    my ($path, $name, $args, $content, $options) = @_;

    require Template::Alloy;
    require App::Dapper::Utils;
    require App::Dapper::Filters;

    my %named = map { /^([A-Za-z_]\w*)=(.*)$/s ? ($1 => $2) : () } @$args;
    my $tt = Template::Alloy->new({ ANYCASE => 1, ENCODING => 'utf8', FILTERS => App::Dapper::Filters::filters() });
    my $source = App::Dapper::Utils::read_file($path);
    my %vars = (
        %{ $options->{vars} || {} },
        args    => args_value($args, \%named),
        content => $content,
        name    => $name,
    );

    my $out = '';
    $tt->process(\$source, \%vars, \$out)
        or die "error: could not process the component template $path: " . $tt->error() . "\n";
    return $out;
}

# A list of arguments that can also be read by name in a template: args.0 is
# the first argument, and args.title the one written title=...
sub args_value {
    my ($list, $named) = @_;
    my %hash = (%$named, map { ($_ => $list->[$_]) } 0 .. $#$list);
    $hash{size} = scalar @$list;
    $hash{list} = $list;
    return \%hash;
}

=head2 built_in

Takes a built-in component's name, arguments and inner HTML, and returns its
HTML.

=cut

sub built_in {
    my ($name, $args, $inner) = @_;

    my @args = @$args;

    if ($name eq 'callout' or $CALLOUTS{$name}) {
        my $kind = $name eq 'callout' ? (@args && $CALLOUTS{lc $args[0]} ? lc shift @args : 'note') : $name;
        my $title = @args ? escape(join(' ', @args)) : '';
        my $heading = length $title ? qq{<p class="callout-title">$title</p>\n} : '';
        return qq{<aside class="callout callout-$kind" role="note">\n$heading$inner</aside>};
    }
    if ($name eq 'details') {
        my $summary = @args ? escape(join(' ', @args)) : 'Details';
        return qq{<details>\n<summary>$summary</summary>\n$inner</details>};
    }
    if ($name eq 'gallery') {
        (my $images = $inner) =~ s{</?p>}{}g;
        return qq{<div class="gallery">\n$images</div>};
    }
    if ($name eq 'youtube' or $name eq 'vimeo') {
        my ($video, @title) = @args;
        my $id = video_id($name, $video);
        return error($name, 'needs a video address or ID') unless defined $id;
        my $title = escape(@title ? join(' ', @title) : ($name eq 'youtube' ? 'YouTube video' : 'Vimeo video'));
        my $src = $name eq 'youtube' ? "https://www.youtube-nocookie.com/embed/$id" : "https://player.vimeo.com/video/$id";
        return qq{<div class="video video-$name"><iframe src="$src" title="$title" loading="lazy" }
             . qq{allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; fullscreen" }
             . qq{referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe></div>};
    }
    if ($name eq 'button') {
        my ($href, @label) = @args;
        return error($name, 'needs an address and a label') unless defined $href and @label;
        return error($name, 'needs a web address') unless safe_url($href);
        return '<p><a class="button" href="' . escape($href) . '">' . escape(join(' ', @label)) . '</a></p>';
    }
    if ($name eq 'figure') {
        my ($src, $alt, @caption) = @args;
        return error($name, 'needs an image and its alt text') unless defined $src and defined $alt;
        return error($name, 'needs an image address') unless safe_url($src);
        my $caption = @caption ? "\n<figcaption>" . escape(join(' ', @caption)) . '</figcaption>' : '';
        return '<figure><img src="' . escape($src) . '" alt="' . escape($alt) . qq{">$caption</figure>};
    }
    if ($name eq 'map') {
        my $place = join(' ', @args);
        return error($name, 'needs an address or place') unless length $place;
        (my $query = $place) =~ s/([^A-Za-z0-9\-._~ ])/sprintf('%%%02X', ord $1)/ge;
        $query =~ s/ /+/g;
        return qq{<div class="map"><iframe src="https://maps.google.com/maps?q=$query&amp;output=embed" title="Map of }
             . escape($place) . qq{" loading="lazy" referrerpolicy="no-referrer-when-downgrade"></iframe></div>};
    }

    return error($name, 'is not a component');
}

=head2 video_id

Takes C<youtube> or C<vimeo> and a video's address or ID, and returns its ID.

=cut

sub video_id {
    my ($site, $video) = @_;

    return unless defined $video;
    if ($site eq 'youtube') {
        return $1 if $video =~ m{(?:youtu\.be/|[?&]v=|/embed/|/shorts/|/live/)([\w-]{6,})};
        return $video if $video =~ /^[\w-]{6,}$/;
        return;
    }
    return $1 if $video =~ m{vimeo\.com/(?:video/)?(\d+)};
    return $video if $video =~ /^\d+$/;
    return;
}

sub safe_url {
    my ($url) = @_;
    return $url !~ /^\s*(?:javascript|vbscript|data):/i;
}

sub error {
    my ($name, $message) = @_;
    return '<p class="component-error"><strong>' . escape("::: $name $message") . '</strong></p>';
}

sub escape {
    my ($text) = @_;
    $text = '' unless defined $text;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text =~ s/"/&quot;/g;
    return $text;
}

1;
