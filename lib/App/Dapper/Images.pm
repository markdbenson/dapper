package App::Dapper::Images;

=head1 NAME

App::Dapper::Images - Image sizes, responsive images and lazy loading.

=head1 DESCRIPTION

With C<images> set in C<_config.yml>, Dapper improves the images in every
page it writes, after the site is built:

    images: true

=over 4

=item * B<Dimensions.> Each C<< <img> >> of a PNG, JPEG, GIF or WebP file in the
site gets C<width> and C<height>, so the page doesn't jump about as images
load.

=item * B<Lazy loading.> Images after the first on a page get
C<loading="lazy">, so the browser fetches them only as they scroll into view.

=item * B<Responsive sizes.> JPEG and PNG images wider than a size in C<sizes>
are resized to each smaller size (C<photo-480w.jpg>, C<photo-960w.jpg>, ...),
and the C<< <img> >> gets a C<srcset> listing them, so phones download small
files.

=item * B<WebP.> With C<webp> on, a WebP copy of each size is made too, and
the image is wrapped in a C<< <picture> >> that offers it to browsers.

=back

Every part can be set:

    images:
      dimensions: true          # width and height (default: true)
      lazy: true                # loading="lazy" after the first image (default: true)
      sizes: [480, 960, 1600]   # widths to resize to (default; [] turns it off)
      webp: true                # WebP copies (default: true)
      quality: 82               # JPEG and WebP quality (default: 82)
      command: magick           # magick, convert or vips (default: whichever is installed)

Resizing needs ImageMagick (C<magick> or C<convert>) or libvips (C<vips>).
Without one, Dapper says so once and does everything else. Resized images are
kept in C<.dapper/images>, so each is only made once. An image with a
C<srcset> of its own, or inside a C<< <picture> >>, is left alone.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use File::Spec;
use File::Spec::Functions qw/ catfile /;
use File::Copy ();
use File::Path ();
use Digest::MD5 ();

use App::Dapper::Utils;

my @DEFAULT_SIZES = (480, 960, 1600);

=head2 settings

Takes the site and returns the image settings as a hash reference, or nothing
if C<images> is not set.

=cut

sub settings {
    my ($site) = @_;

    my $value = $site->{images};
    return unless defined $value;
    return if !ref $value and $value =~ /^(?:0|false|no|off|)$/i;

    my %given = ref $value eq 'HASH' ? %$value : ();
    my $on = sub {
        my ($name) = @_;
        return 1 unless defined $given{$name};
        return $given{$name} =~ /^(?:0|false|no|off|)$/i ? 0 : 1;
    };

    my @sizes = exists $given{sizes}
        ? (ref $given{sizes} eq 'ARRAY' ? @{$given{sizes}} : grep { length } split /[\s,]+/, $given{sizes})
        : @DEFAULT_SIZES;
    @sizes = sort { $a <=> $b } grep { /^\d+$/ and $_ > 0 } @sizes;

    return {
        dimensions => $on->('dimensions'),
        lazy       => $on->('lazy'),
        webp       => $on->('webp'),
        sizes      => \@sizes,
        quality    => defined $given{quality} && $given{quality} =~ /^\d+$/ ? $given{quality} : 82,
        command    => $given{command},
    };
}

=head2 process

Takes a Dapper object whose site has just been written, and improves the
images in each HTML file it wrote.

=cut

sub process {
    my ($dapper) = @_;

    my $settings = settings($dapper->{site}) or return;
    my $output = $dapper->{output};
    my $base = defined $dapper->{site}->{url} ? $dapper->{site}->{url} : '';
    $base =~ s{/+$}{};

    my $state = { settings => $settings, dapper => $dapper, made => {} };

    for my $relative (sort keys %{$dapper->{written}}) {
        next unless $relative =~ /\.html?$/i;
        my $file = catfile($output, $relative);
        next unless -f $file;

        my $html = App::Dapper::Utils::read_file($file);
        my $page_dir = '/' . $relative;
        $page_dir =~ s{[^/]*$}{};

        my $count = 0;
        my $changed = 0;

        # Pictures and code are left as they are
        my @kept;
        $html =~ s{(<picture\b.*?</picture>|<pre\b.*?</pre>|<code\b.*?</code>|<!--.*?-->)}{push @kept, $1; "\x{0}DAPPERKEPT$#kept\x{0}"}gise;

        $html =~ s{(<img\b([^>]*?)\s*/?>)}{
            my ($whole, $attributes) = ($1, $2);
            my $tag = image_tag($state, $attributes, $page_dir, $base, $count++ == 0);
            $changed = 1 if defined $tag;
            defined $tag ? $tag : $whole;
        }gise;

        $html =~ s{\x{0}DAPPERKEPT(\d+)\x{0}}{$kept[$1]}g;
        App::Dapper::Utils::write_file($file, $html) if $changed;
    }
}

=head2 image_tag

Takes the processing state, the attributes of an C<< <img> >>, the directory
of the page it is on, the site's address and whether it is the first image
on the page. Returns the new HTML for it, or nothing to leave it alone.

=cut

sub image_tag {
    my ($state, $attributes, $page_dir, $base, $first) = @_;

    my $settings = $state->{settings};
    my $output = $state->{dapper}->{output};

    my ($quote, $src) = $attributes =~ /\bsrc\s*=\s*(["'])(.*?)\1/is;
    return unless defined $src;

    require App::Dapper::Check;
    my $path = App::Dapper::Check::target_path($src, $page_dir, $base);
    return unless defined $path and $path =~ /\.(?:png|jpe?g|gif|webp)$/i;
    my $file = File::Spec->canonpath(catfile($output, $path));
    return unless -f $file;

    my ($width, $height) = image_size($file);
    return unless $width and $height;

    my $new = $attributes;
    my $changed = 0;

    if ($settings->{dimensions} and $new !~ /\b(?:width|height)\s*=/i) {
        $new .= qq{ width="$width" height="$height"};
        $changed = 1;
    }
    if ($settings->{lazy} and not $first and $new !~ /\bloading\s*=/i) {
        $new .= q{ loading="lazy" decoding="async"};
        $changed = 1;
    }

    my $picture;
    if (@{$settings->{sizes}} and $path =~ /\.(?:png|jpe?g)$/i and $new !~ /\bsrcset\s*=/i) {
        my @widths = grep { $_ < $width } @{$settings->{sizes}};
        if (@widths and my @made = variants($state, $file, $width, $height, \@widths)) {
            my $srcset = sub {
                my ($ext) = @_;
                my @list = map { variant_url($src, $_->{full} ? undef : $_->{width}, $ext) . " $_->{width}w" }
                            grep { $_->{ext} eq ($ext || 'same') } @made;
                return join(', ', @list);
            };
            my $sizes = qq{(max-width: ${width}px) 100vw, ${width}px};
            $new .= qq{ srcset="} . $srcset->() . ", $src ${width}w" . qq{" sizes="$sizes"};
            if (grep { $_->{ext} eq 'webp' } @made) {
                $picture = qq{<source type="image/webp" srcset="} . $srcset->('webp') . qq{" sizes="$sizes">};
            }
            $changed = 1;
        }
    }

    return unless $changed;
    my $img = "<img$new>";
    return defined $picture ? "<picture>$picture$img</picture>" : $img;
}

=head2 variant_url

Takes an image URL, a width and (optionally) a new extension, and returns the
URL of the resized copy: C<photo.jpg> at 480 is C<photo-480w.jpg>, and as WebP
C<photo-480w.webp>. Without a width, the full-size copy: C<photo.webp>.

=cut

sub variant_url {
    my ($url, $width, $ext) = @_;

    my ($stem, $old, $rest) = $url =~ /^(.*)\.([A-Za-z0-9]+)((?:[?#].*)?)$/s
        or return $url;
    $ext = $old unless defined $ext;
    my $size = defined $width ? "-${width}w" : '';
    return "$stem$size.$ext" . (defined $rest ? $rest : '');
}

=head2 variants

Takes the processing state, an image in the output directory, its width and
height, and the widths wanted. Makes each resized copy (and its WebP copy, if
WebP is on) next to the image, and returns a list of hash references with the
C<width> and C<ext> (C<same> or C<webp>) of each copy made. Returns nothing if
no resizing command is installed.

=cut

sub variants {
    my ($state, $file, $width, $height, $widths) = @_;

    my $settings = $state->{settings};
    my $dapper = $state->{dapper};
    my $command = command($state) or return;

    my $digest = do {
        open(my $fh, '<:raw', $file) or return;
        Digest::MD5->new->addfile($fh)->hexdigest;
    };

    my $cache = catfile('.dapper', 'images');
    File::Path::make_path($cache) unless -d $cache;

    my @made;
    my @formats = ('same');
    push @formats, 'webp' if $settings->{webp};

    (my $ext = $file) =~ s/.*\.//;
    for my $format (@formats) {
        my $out_ext = $format eq 'webp' ? 'webp' : lc $ext;
        my @sizes = @$widths;
        push @sizes, $width if $format eq 'webp';
        for my $size (@sizes) {
            my $cached = catfile($cache, "$digest-$size-$settings->{quality}.$out_ext");
            if (not -s $cached) {
                my $ok = resize($command, $file, $cached, $size, $settings->{quality});
                if (not $ok) {
                    unlink $cached;
                    $dapper->problem('warning', $file, "could not resize $file with $command->[0]");
                    next;
                }
            }
            my $target = $size == $width ? variant_url($file, undef, $out_ext) : variant_url($file, $size, $out_ext);
            File::Copy::copy($cached, $target) or next;
            $dapper->record_written($target);
            push @made, { width => $size, ext => $format } unless $size == $width;
        }
    }

    # The full-size WebP copy is listed with the other sizes
    if ($settings->{webp} and grep { $_->{ext} eq 'webp' } @made) {
        push @made, { width => $width, ext => 'webp', full => 1 };
    }

    return @made;
}

=head2 command

Returns the command used to resize images (as an array reference), finding it
the first time: the C<command> setting, or C<magick>, C<convert> or C<vips>,
whichever is installed. Returns nothing, after one warning, if there is none.

=cut

sub command {
    my ($state) = @_;

    return $state->{command} if exists $state->{command};

    my @wanted = defined $state->{settings}->{command} ? ($state->{settings}->{command}) : qw/ magick convert vips /;
    for my $name (@wanted) {
        my $found = $name =~ m{/} ? (-x $name ? $name : undef)
                  : (grep { -x catfile($_, $name) } File::Spec->path()) ? $name : undef;
        next unless defined $found;
        my ($kind) = $name =~ m{(magick|convert|vips)[^/]*$};
        $kind = 'magick' unless defined $kind;
        return $state->{command} = [ $found, $kind ];
    }

    $state->{dapper}->problem('warning', $state->{dapper}->{config},
        'resizing images needs ImageMagick or libvips; install one (for example "brew install imagemagick"), or set sizes: [] under images');
    return $state->{command} = undef;
}

=head2 resize

Takes the command (from L</command>), an image, the file to write, the width
and the quality, and resizes the image. Returns true if it worked.

=cut

sub resize {
    my ($command, $from, $to, $width, $quality) = @_;

    my ($program, $kind) = @$command;
    my @run = $kind eq 'vips'
        ? ($program, 'thumbnail', $from, "${to}[Q=$quality,strip]", $width)
        : ($program, $from, '-auto-orient', '-strip', '-resize', "${width}x", '-quality', $quality, $to);

    # Keep the programs quiet; their errors are reported as a warning instead
    open(my $null, '>', File::Spec->devnull);
    open(my $saved_out, '>&', \*STDOUT);
    open(my $saved_err, '>&', \*STDERR);
    open(STDOUT, '>&', $null);
    open(STDERR, '>&', $null);
    my $status = system(@run);
    open(STDOUT, '>&', $saved_out);
    open(STDERR, '>&', $saved_err);

    return $status == 0 && -s $to;
}

=head2 image_size

Takes an image file (PNG, GIF, JPEG or WebP) and returns its width and height
as it is displayed (so a JPEG turned by its EXIF orientation reports its
turned size), or nothing if it can't tell.

=cut

sub image_size {
    my ($file) = @_;

    open(my $fh, '<:raw', $file) or return;
    my $data = '';
    read($fh, $data, 256 * 1024);
    close $fh;

    if ($data =~ /^\x89PNG\r\n\x1a\n/ and length $data >= 24) {
        return unpack('NN', substr($data, 16, 8));
    }
    if ($data =~ /^GIF8[79]a/ and length $data >= 10) {
        return unpack('vv', substr($data, 6, 4));
    }
    if ($data =~ /^RIFF....WEBP/s and length $data >= 30) {
        my $chunk = substr($data, 12, 4);
        if ($chunk eq 'VP8 ') {
            my ($w, $h) = unpack('vv', substr($data, 26, 4));
            return ($w & 0x3fff, $h & 0x3fff);
        }
        if ($chunk eq 'VP8L') {
            my $bits = unpack('V', substr($data, 21, 4));
            return (1 + ($bits & 0x3fff), 1 + (($bits >> 14) & 0x3fff));
        }
        if ($chunk eq 'VP8X') {
            my @b = unpack('C6', substr($data, 24, 6));
            return (1 + ($b[0] | $b[1] << 8 | $b[2] << 16), 1 + ($b[3] | $b[4] << 8 | $b[5] << 16));
        }
        return;
    }
    return jpeg_size($data) if $data =~ /^\xff\xd8/;
    return;
}

sub jpeg_size {
    my ($data) = @_;

    my ($pos, $orientation) = (2, 1);
    while ($pos + 4 <= length $data) {
        my ($marker, $type) = unpack('CC', substr($data, $pos, 2));
        return unless $marker == 0xff;
        if ($type == 0xff) { $pos++; next }
        my $length = unpack('n', substr($data, $pos + 2, 2));

        if ($type == 0xe1 and substr($data, $pos + 4, 6) eq "Exif\0\0") {
            my $found = exif_orientation(substr($data, $pos + 10, $length - 8));
            $orientation = $found if $found;
        }
        if ($type >= 0xc0 and $type <= 0xcf and $type != 0xc4 and $type != 0xc8 and $type != 0xcc) {
            return if $pos + 9 > length $data;
            my ($height, $width) = unpack('nn', substr($data, $pos + 5, 4));
            return $orientation >= 5 && $orientation <= 8 ? ($height, $width) : ($width, $height);
        }
        $pos += 2 + $length;
    }
    return;
}

sub exif_orientation {
    my ($tiff) = @_;

    return unless length $tiff >= 8;
    my $order = substr($tiff, 0, 2);
    my ($short, $long) = $order eq 'II' ? ('v', 'V') : $order eq 'MM' ? ('n', 'N') : return;
    my $ifd = unpack($long, substr($tiff, 4, 4));
    return unless $ifd + 2 <= length $tiff;
    my $entries = unpack($short, substr($tiff, $ifd, 2));
    for my $i (0 .. $entries - 1) {
        my $entry = $ifd + 2 + $i * 12;
        last if $entry + 12 > length $tiff;
        next unless unpack($short, substr($tiff, $entry, 2)) == 0x0112;
        return unpack($short, substr($tiff, $entry + 8, 2));
    }
    return;
}

1;
