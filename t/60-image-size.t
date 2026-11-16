use 5.010;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);

use lib 't/lib';
use DapperTest;
use App::Dapper::Images;

# Reading the width and height of PNG, GIF, JPEG and WebP files, byte by byte

my $dir = tempdir(CLEANUP => 1);
my $n = 0;

# size_of($bytes) - Write the bytes to a file and return what image_size says
sub size_of {
    my ($data) = @_;
    my $file = "$dir/image" . $n++;
    spew($file, $data, ':raw');
    return [ App::Dapper::Images::image_size($file) ];
}

sub png  { "\x89PNG\r\n\x1a\n" . pack('N', 13) . 'IHDR' . pack('NN', @_) . "\x08\x02\0\0\0" . "\0" x 4 }
sub gif  { my $v = shift; "GIF8${v}a" . pack('vv', @_) . "\0" x 8 }

# WebP: the three kinds of first chunk
sub webp_vp8 {
    my ($w, $h, $scale) = @_;
    $scale ||= 0;
    return 'RIFF' . pack('V', 30) . 'WEBP' . 'VP8 ' . pack('V', 18) . "\0\0\0" . "\x9d\x01\x2a"
        . pack('vv', $w | ($scale << 14), $h | ($scale << 14)) . "\0" x 4;
}
sub webp_vp8l {
    my ($w, $h) = @_;
    my $bits = ($w - 1) | (($h - 1) << 14);
    return 'RIFF' . pack('V', 30) . 'WEBP' . 'VP8L' . pack('V', 10) . "\x2f" . pack('V', $bits) . "\0" x 5;
}
sub webp_vp8x {
    my ($w, $h) = @_;
    my $three = sub { my $v = shift; pack('CCC', $v & 0xff, ($v >> 8) & 0xff, ($v >> 16) & 0xff) };
    return 'RIFF' . pack('V', 30) . 'WEBP' . 'VP8X' . pack('V', 10) . "\0" x 4 . $three->($w - 1) . $three->($h - 1) . "\0" x 4;
}

# JPEG: a start, optional segments, a frame header of the type given, and more
sub segment { my ($type, $payload) = @_; "\xff" . chr($type) . pack('n', 2 + length $payload) . $payload }
sub sof     { my ($type, $w, $h) = @_; segment($type, pack('CnnC', 8, $h, $w, 3) . "\0" x 9) }
sub exif {
    my ($order, $orientation, %opt) = @_;
    my ($s, $l) = $order eq 'II' ? ('v', 'V') : ('n', 'N');
    my @entries = @{ $opt{before} || [] };
    my $entry = sub { my ($tag, $value) = @_; pack($s, $tag) . pack($s, 3) . pack($l, 1) . pack($s, $value) . "\0\0" };
    my $ifd = join('', map { $entry->(@$_) } @entries) . (defined $orientation ? $entry->(0x0112, $orientation) : '');
    my $count = @entries + (defined $orientation ? 1 : 0);
    my $offset = defined $opt{offset} ? $opt{offset} : 8;
    my $tiff = $order . pack($s, 42) . pack($l, $offset) . pack($s, $opt{count} // $count) . $ifd . pack($l, 0);
    return segment(0xe1, "Exif\0\0" . $tiff);
}
sub jpeg { "\xff\xd8" . join('', @_) . "\xff\xd9" }
my $dqt = segment(0xdb, "\0" x 65);

subtest 'PNG' => sub {
    is_deeply(size_of(png(2000, 1000)), [2000, 1000], 'width and height from IHDR');
    is_deeply(size_of(png(1, 1)), [1, 1], 'one pixel');
    is_deeply(size_of(png(65536, 70000)), [65536, 70000], 'more than 16 bits');
    is_deeply(size_of(substr(png(10, 20), 0, 24)), [10, 20], 'exactly 24 bytes is enough');
    is_deeply(size_of(substr(png(10, 20), 0, 23)), [], '23 bytes is not');
    is_deeply(size_of("\x89PNG\r\n\x1a\x0a"), [], 'only the signature');
    is_deeply(size_of("\x89PNX\r\n\x1a\n" . "\0" x 30), [], 'a wrong signature');
};

subtest 'GIF' => sub {
    is_deeply(size_of(gif(9, 300, 200)), [300, 200], 'GIF89a');
    is_deeply(size_of(gif(7, 640, 480)), [640, 480], 'GIF87a');
    is_deeply(size_of(gif(9, 65535, 1)), [65535, 1], 'little-endian, 16 bits');
    is_deeply(size_of(substr(gif(9, 5, 6), 0, 10)), [5, 6], 'exactly 10 bytes');
    is_deeply(size_of(substr(gif(9, 5, 6), 0, 9)), [], '9 bytes is not enough');
    is_deeply(size_of('GIF88a' . "\0" x 10), [], 'an unknown GIF version');
};

subtest 'WebP' => sub {
    is_deeply(size_of(webp_vp8(640, 480)), [640, 480], 'lossy (VP8)');
    is_deeply(size_of(webp_vp8(1000, 700, 3)), [1000, 700], 'lossy, scaling bits ignored');
    is_deeply(size_of(webp_vp8(16383, 16383)), [16383, 16383], 'lossy, largest');
    is_deeply(size_of(webp_vp8l(800, 600)), [800, 600], 'lossless (VP8L)');
    is_deeply(size_of(webp_vp8l(1, 1)), [1, 1], 'lossless, one pixel');
    is_deeply(size_of(webp_vp8l(16384, 16384)), [16384, 16384], 'lossless, largest');
    is_deeply(size_of(webp_vp8x(640, 480)), [640, 480], 'extended (VP8X)');
    is_deeply(size_of(webp_vp8x(70000, 3)), [70000, 3], 'extended, 24 bits');
    is_deeply(size_of(webp_vp8x(16777216, 16777216)), [16777216, 16777216], 'extended, largest');
    is_deeply(size_of('RIFF' . pack('V', 30) . 'WEBP' . 'VP8Q' . "\0" x 20), [], 'an unknown chunk');
    is_deeply(size_of(substr(webp_vp8x(10, 10), 0, 29)), [], 'too short');
    is_deeply(size_of('RIFF' . pack('V', 30) . 'WAVE' . 'fmt ' . "\0" x 20), [], 'a RIFF file that is not WebP');
};

subtest 'JPEG' => sub {
    is_deeply(size_of(jpeg($dqt, sof(0xc0, 1200, 800))), [1200, 800], 'baseline (SOF0)');
    is_deeply(size_of(jpeg($dqt, sof(0xc1, 30, 40))), [30, 40], 'extended (SOF1)');
    is_deeply(size_of(jpeg($dqt, sof(0xc2, 1024, 768))), [1024, 768], 'progressive (SOF2)');
    is_deeply(size_of(jpeg(sof(0xc3, 5, 6))), [5, 6], 'lossless (SOF3)');
    is_deeply(size_of(jpeg(sof(0xcf, 7, 8))), [7, 8], 'SOF15');
    is_deeply(size_of(jpeg(segment(0xc4, "\0" x 20), sof(0xc0, 9, 10))), [9, 10], 'a Huffman table (C4) is not a frame');
    is_deeply(size_of(jpeg(segment(0xc8, "\0" x 20), sof(0xc0, 11, 12))), [11, 12], 'JPG (C8) is not a frame');
    is_deeply(size_of(jpeg(segment(0xcc, "\0" x 20), sof(0xc0, 13, 14))), [13, 14], 'arithmetic coding (CC) is not a frame');
    is_deeply(size_of(jpeg(segment(0xe0, "JFIF\0" . "\0" x 9), segment(0xfe, 'a comment'), $dqt, sof(0xc0, 15, 16))),
        [15, 16], 'after JFIF, a comment and tables');
    is_deeply(size_of("\xff\xd8\xff\xff\xff" . substr(sof(0xc0, 17, 18), 1)), [17, 18], 'fill bytes before a marker');
    is_deeply(size_of(jpeg($dqt, sof(0xc0, 65535, 65535))), [65535, 65535], 'largest');
    is_deeply(size_of(jpeg(segment(0x01, 'xx'), segment(0xbf, 'yy'), sof(0xc0, 19, 20))), [19, 20], 'markers below C0 are skipped');
    is_deeply(size_of(jpeg(segment(0xd0, 'zz'), sof(0xc0, 21, 22))), [21, 22], 'markers above CF are skipped');
    is_deeply(size_of(jpeg($dqt)), [], 'no frame header');
    is_deeply(size_of("\xff\xd8" . $dqt . "\x00\x00\x00\x00"), [], 'something other than a marker');
    is_deeply(size_of("\xff\xd8" . "\xff\xc0\x00\x11\x08"), [], 'a frame header cut short');
    is_deeply(size_of("\xff\xd8"), [], 'only the start');
    is_deeply(size_of("\xff\xd9\xff\xc0" . "\0" x 20), [], 'not a JPEG start');

    my $big = join('', map { segment(0xe2, 'x' x 60000) } 1 .. 5);
    is_deeply(size_of(jpeg($big, sof(0xc0, 50, 60))), [], 'a frame header after the first 256 KB is not found');
    my $fits = join('', map { segment(0xe2, 'x' x 60000) } 1 .. 4);
    is_deeply(size_of(jpeg($fits, sof(0xc0, 50, 60))), [50, 60], 'one inside the first 256 KB is');
};

subtest 'EXIF orientation' => sub {
    for my $order (qw/ MM II /) {
        for my $o (1 .. 8) {
            my $want = $o >= 5 ? [800, 1200] : [1200, 800];
            is_deeply(size_of(jpeg(exif($order, $o), $dqt, sof(0xc0, 1200, 800))), $want, "$order orientation $o");
        }
        is_deeply(size_of(jpeg(exif($order, 6, before => [[0x010f, 1], [0x0110, 2]]), sof(0xc0, 100, 50))), [50, 100],
            "$order: found after other tags");
        is_deeply(size_of(jpeg(exif($order, undef, before => [[0x010f, 6]]), sof(0xc0, 100, 50))), [100, 50],
            "$order: no orientation tag");
        is_deeply(size_of(jpeg(exif($order, 0), sof(0xc0, 100, 50))), [100, 50], "$order: orientation 0 is ignored");
        is_deeply(size_of(jpeg(exif($order, 9), sof(0xc0, 100, 50))), [100, 50], "$order: orientation 9 is not turned");
        is_deeply(size_of(jpeg(exif($order, 6, offset => 500), sof(0xc0, 100, 50))), [100, 50], "$order: a directory past the end");
        is_deeply(size_of(jpeg(exif($order, 6, count => 40), sof(0xc0, 100, 50))), [50, 100], "$order: an entry count past the end");
        is_deeply(size_of(jpeg(exif($order, undef, before => [[0x010f, 6]], count => 40), sof(0xc0, 100, 50))), [100, 50], "$order: a count past the end and no orientation");
    }
    my $bad = exif('MM', 6);
    $bad =~ s/MM/XX/;
    is_deeply(size_of(jpeg($bad, sof(0xc0, 100, 50))), [100, 50], 'an unknown byte order');
    is_deeply(size_of(jpeg(segment(0xe1, "Exif\0\0MM"), sof(0xc0, 100, 50))), [100, 50], 'EXIF too short to read');
    is_deeply(size_of(jpeg(segment(0xe1, "http://ns.adobe.com/xap/1.0/\0<x/>"), sof(0xc0, 100, 50))), [100, 50], 'XMP is not EXIF');
    is_deeply(size_of(jpeg(exif('MM', 6), exif('II', 1), sof(0xc0, 100, 50))), [100, 50], 'a second EXIF segment (orientation 1) wins over the first');
    is_deeply(size_of(jpeg(exif('MM', 1), exif('II', 8), sof(0xc0, 100, 50))), [50, 100], 'the last turn found wins');
    is_deeply(size_of(jpeg(exif('MM', 6), $dqt, sof(0xc2, 640, 480))), [480, 640], 'progressive and turned');
};

subtest 'not images' => sub {
    is_deeply(size_of(''), [], 'an empty file');
    is_deeply(size_of("not an image at all, just text\n" x 3), [], 'text');
    is_deeply(size_of('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>'), [], 'SVG');
    is_deeply([ App::Dapper::Images::image_size("$dir/missing.png") ], [], 'a missing file');
    is_deeply([ App::Dapper::Images::image_size($dir) ], [], 'a directory');
};

done_testing();
