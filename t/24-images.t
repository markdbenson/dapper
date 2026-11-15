use 5.010;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Images;

# The start of image files: enough for their sizes to be read
sub png  { "\x89PNG\r\n\x1a\n" . pack('N', 13) . 'IHDR' . pack('NN', @_) . "\x08\x02\0\0\0" . "\0" x 4 }
sub gif  { 'GIF89a' . pack('vv', @_) . "\0" x 8 }
sub webp { 'RIFF' . pack('V', 30) . 'WEBPVP8X' . pack('V', 10) . "\0" x 4 . pack('VXv', $_[0] - 1, ($_[1] - 1) & 0xffff) . "\0" x 4 }
sub jpeg {
    my ($w, $h, $orientation) = @_;
    my $exif = '';
    if ($orientation) {
        my $tiff = 'MM' . pack('nN', 42, 8) . pack('n', 1) . pack('nnNnn', 0x0112, 3, 1, $orientation, 0) . pack('N', 0);
        $exif = "\xff\xe1" . pack('n', 2 + 6 + length $tiff) . "Exif\0\0" . $tiff;
    }
    return "\xff\xd8" . $exif . "\xff\xdb" . pack('n', 4) . "\0\0" . "\xff\xc0" . pack('nCnnC', 11, 8, $h, $w, 3) . "\0" x 6;
}

# A stand-in for ImageMagick that copies the image and records how it was called
my $bin = tempdir(CLEANUP => 1);
my $log = "$bin/magick.log";
spew("$bin/magick", "#!$^X\nopen my \$l, '>>', '$log'; print \$l join(' ', \@ARGV), \"\\n\";\n"
    . "open my \$i, '<:raw', \$ARGV[0] or die; open my \$o, '>:raw', \$ARGV[-1] or die; local \$/; print {\$o} <\$i>;\n");
chmod 0755, "$bin/magick";

subtest 'image_size' => sub {
    my $dir = tempdir(CLEANUP => 1);
    my %files = (
        'a.png'  => [png(2000, 1000), 2000, 1000],
        'a.gif'  => [gif(300, 200), 300, 200],
        'a.webp' => [webp(640, 480), 640, 480],
        'a.jpg'  => [jpeg(1200, 800), 1200, 800],
        'r.jpg'  => [jpeg(1200, 800, 6), 800, 1200],
        'x.png'  => ["not an image", undef, undef],
    );
    for my $name (sort keys %files) {
        my ($data, $w, $h) = @{$files{$name}};
        spew("$dir/$name", $data, ':raw');
        my @size = App::Dapper::Images::image_size("$dir/$name");
        is_deeply(\@size, defined $w ? [$w, $h] : [], $name);
    }
};

subtest 'variant_url' => sub {
    my $v = \&App::Dapper::Images::variant_url;
    is($v->('/img/photo.jpg', 480), '/img/photo-480w.jpg', 'resized');
    is($v->('photo.jpg', 480, 'webp'), 'photo-480w.webp', 'resized WebP');
    is($v->('photo.jpg', undef, 'webp'), 'photo.webp', 'full-size WebP');
    is($v->('photo.jpg?v=2', 480), 'photo-480w.jpg?v=2', 'query kept');
};

my %images = (
    '_source/img/big.jpg'   => jpeg(2000, 1000),
    '_source/img/small.png' => png(400, 300),
    '_source/img/logo.gif'  => gif(120, 60),
);

# make_site writes text; images are written as bytes
sub make_image_site {
    my ($files) = @_;
    make_site($files);
    spew($_, $images{$_}, ':raw') for keys %images;
}

my %site = (
    '_source/index.md' => "---\ntitle: Home\n---\n![Big](img/big.jpg)\n\n![Small](img/small.png)\n\n![Logo](img/logo.gif)\n\n"
        . "<img src=\"img/big.jpg\" alt=\"Set\" srcset=\"x.jpg 1x\">\n\n<img src=\"https://example.com/x.jpg\" alt=\"Remote\">\n\n"
        . "<pre><img src=\"img/big.jpg\"></pre>\n",
);

subtest 'turned off by default' => sub {
    make_image_site({ %site });
    quiet_build();
    unlike(slurp('_output/index.html'), qr/width=|loading=|srcset="[^x]/, 'images left alone');
};

subtest 'dimensions, lazy loading, sizes and WebP' => sub {
    local $ENV{PATH} = "$bin:$ENV{PATH}";
    unlink $log;
    make_image_site({ %site, '_config.yml' => "---\nname: x\nimages: true\n" });
    quiet_build();
    my $html = slurp('_output/index.html');

    like($html, qr{<picture><source type="image/webp" srcset="img/big-480w\.webp 480w, img/big-960w\.webp 960w, img/big-1600w\.webp 1600w, img/big\.webp 2000w" sizes="\(max-width: 2000px\) 100vw, 2000px"><img src="img/big\.jpg" alt="Big"[^>]* width="2000" height="1000" srcset="img/big-480w\.jpg 480w, img/big-960w\.jpg 960w, img/big-1600w\.jpg 1600w, img/big\.jpg 2000w" sizes="\(max-width: 2000px\) 100vw, 2000px"></picture>},
        'the first image: sizes, WebP, no lazy loading') or diag $html;
    like($html, qr{<img src="img/small\.png" alt="Small"[^>]* width="400" height="300" loading="lazy" decoding="async" srcset="img/small\.png 400w, img/small\.png 400w"|<img src="img/small\.png" alt="Small"[^>]* width="400" height="300" loading="lazy" decoding="async">},
        'a small image: dimensions and lazy loading');
    unlike($html, qr{small-480w}, 'not made bigger');
    like($html, qr{<img src="img/logo\.gif" alt="Logo"[^>]* width="120" height="60" loading="lazy" decoding="async">}, 'a GIF is not resized');
    like($html, qr{<img src="img/big\.jpg" alt="Set" srcset="x\.jpg 1x" width="2000" height="1000" loading="lazy" decoding="async">}, 'its own srcset kept');
    like($html, qr{<img src="https://example\.com/x\.jpg" alt="Remote">}, 'other sites left alone');
    like($html, qr{<pre><img src="img/big\.jpg"></pre>}, 'code left alone');

    ok(-f "_output/img/big-$_.jpg", "big-$_.jpg") for qw/ 480w 960w 1600w /;
    ok(-f "_output/img/big-$_.webp", "big-$_.webp") for qw/ 480w 960w 1600w /;
    ok(-f '_output/img/big.webp', 'full-size WebP');

    my $calls = () = slurp($log) =~ /\n/g;
    is($calls, 7, 'seven copies made');
    like(slurp($log), qr{-auto-orient -strip -resize 480x -quality 82 \.dapper/images/\w+-480-82\.jpg}, 'resized into the cache');

    quiet_build();
    $calls = () = slurp($log) =~ /\n/g;
    is($calls, 7, 'the second build uses the cache');
    ok(-f '_output/img/big-480w.jpg', 'and still writes the copies');

    my $report = App::Dapper->new()->check();
    is_deeply([ grep { $_->{type} eq 'link' } @{$report->{errors}} ], [], 'every copy is linked correctly');
};

subtest 'settings' => sub {
    local $ENV{PATH} = "$bin:$ENV{PATH}";
    make_image_site({ %site, '_config.yml' => "---\nname: x\nimages:\n  sizes: [1000]\n  webp: false\n  lazy: false\n  quality: 70\n" });
    unlink $log;
    quiet_build();
    my $html = slurp('_output/index.html');
    like($html, qr{<img src="img/big\.jpg" alt="Big"[^>]* width="2000" height="1000" srcset="img/big-1000w\.jpg 1000w, img/big\.jpg 2000w"}, 'one size, no WebP');
    unlike($html, qr{<picture>|loading=}, 'no picture, no lazy loading');
    like(slurp($log), qr{-quality 70}, 'quality');

    make_image_site({ %site, '_config.yml' => "---\nname: x\nimages:\n  sizes: []\n  dimensions: false\n" });
    unlink $log;
    quiet_build();
    $html = slurp('_output/index.html');
    unlike($html, qr{width=|srcset="img}, 'no dimensions, no sizes');
    like($html, qr{alt="Small"[^>]* loading="lazy"}, 'lazy loading still on');
    ok(!-e $log, 'nothing resized');
};

subtest 'without ImageMagick or libvips' => sub {
    local $ENV{PATH} = '/nonexistent';
    make_image_site({ %site, '_config.yml' => "---\nname: x\nimages: true\n" });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    is(scalar(grep { /resizing images needs ImageMagick or libvips/ } @warnings), 1, 'one warning');
    my $html = slurp('_output/index.html');
    like($html, qr{alt="Big"[^>]* width="2000" height="1000">}, 'dimensions still added');
    unlike($html, qr{srcset="img}, 'no sizes');
};

subtest 'check finds images without alt text' => sub {
    make_site({ '_source/a.md' => "---\ntitle: A\n---\nIntro.\n\n![](img/x.png)\n" });
    spew('_source/img/x.png', png(10, 10), ':raw');
    my $report = App::Dapper->new()->check();
    ok((grep { $_->{message} =~ m{img/x\.png has no alt text} } @{$report->{warnings}}), 'reported');
};

done_testing();
