use 5.010;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use Digest::MD5;
use Cwd qw(getcwd);

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Images;

# Responsive images: settings, image tags, resized copies, the commands that
# make them, and the whole thing in a site build.

sub png  { "\x89PNG\r\n\x1a\n" . pack('N', 13) . 'IHDR' . pack('NN', @_) . "\x08\x02\0\0\0" . "\0" x 4 }
sub gif  { 'GIF89a' . pack('vv', @_) . "\0" x 8 }
sub webp { 'RIFF' . pack('V', 30) . 'WEBPVP8X' . pack('V', 10) . "\0" x 4 . pack('VXv', $_[0] - 1, ($_[1] - 1) & 0xffff) . "\0" x 4 }
sub jpeg { my ($w, $h) = @_; "\xff\xd8\xff\xdb" . pack('n', 4) . "\0\0" . "\xff\xc0" . pack('nCnnC', 11, 8, $h, $w, 3) . "\0" x 6 }

# Stand-ins for ImageMagick and libvips that record how they were called.
# magick copies its input to its output; vips writes to the name before [...].
my $bin = tempdir(CLEANUP => 1);
my $log = "$bin/calls.log";
sub stand_in {
    my ($dir, $name, $code) = @_;
    make_path($dir);
    spew("$dir/$name", "#!$^X\nopen my \$l, '>>', '$log'; print \$l join(' ', '$name', \@ARGV), \"\\n\"; close \$l;\n$code");
    chmod 0755, "$dir/$name";
}
my $copy_magick = "open my \$i, '<:raw', \$ARGV[0] or die; open my \$o, '>:raw', \$ARGV[-1] or die; local \$/; print {\$o} <\$i>;\n";
my $copy_vips = "(my \$to = \$ARGV[2]) =~ s/\\[.*//; open my \$i, '<:raw', \$ARGV[1] or die; open my \$o, '>:raw', \$to or die; local \$/; print {\$o} <\$i>;\n";

stand_in("$bin/magick", 'magick', $copy_magick);
stand_in("$bin/convert", 'convert', $copy_magick);
stand_in("$bin/vips", 'vips', $copy_vips);
stand_in("$bin/all", $_, $_ eq 'vips' ? $copy_vips : $copy_magick) for qw/ magick convert vips /;
stand_in("$bin/fail", 'magick', "exit 1;\n");
stand_in("$bin/empty", 'magick', "exit 0;\n");
stand_in("$bin/some", 'magick', "exit 1 if grep { \$_ eq '960x' } \@ARGV;\n$copy_magick");
stand_in("$bin/paths", 'my-resizer', $copy_magick);
stand_in("$bin/paths", 'vipsthumb', $copy_vips);
spew("$bin/paths/not-executable", "x");

sub calls { my $text = slurp($log); return defined $text ? [ split /\n/, $text ] : [] }

# A stand-in for the Dapper object, collecting problems and written files
{
    package MockDapper;
    sub new { my ($class, %a) = @_; return bless { output => '_output', config => '_config.yml', written => {}, problems => [], %a }, $class }
    sub problem { my ($self, @p) = @_; push @{$self->{problems}}, \@p }
    sub record_written { App::Dapper::record_written(@_) }
}

sub defaults { App::Dapper::Images::settings({ images => 1 }) }

# --- settings ---------------------------------------------------------------

subtest 'settings: off' => sub {
    my $s = \&App::Dapper::Images::settings;
    is_deeply([ $s->({}) ], [], 'not set');
    is_deeply([ $s->({ images => undef }) ], [], 'undefined');
    for my $off ('0', 'false', 'no', 'off', '', 'FALSE', 'No', 'OFF') {
        is_deeply([ $s->({ images => $off }) ], [], "images: '$off'");
    }
};

subtest 'settings: on' => sub {
    my $s = \&App::Dapper::Images::settings;
    my $default = { dimensions => 1, lazy => 1, webp => 1, sizes => [480, 960, 1600], quality => 82, command => undef };
    is_deeply($s->({ images => $_ }), $default, "images: $_") for qw/ 1 true yes on anything /;
    is_deeply($s->({ images => {} }), $default, 'an empty hash');
    is_deeply($s->({ images => [1] }), $default, 'a list is treated as on');

    for my $name (qw/ dimensions lazy webp /) {
        for my $off ('0', 'false', 'no', 'off', '', 'False') {
            is($s->({ images => { $name => $off } })->{$name}, 0, "$name: '$off'");
        }
        for my $on ('1', 'true', 'yes', 'on', 'whatever') {
            is($s->({ images => { $name => $on } })->{$name}, 1, "$name: '$on'");
        }
        is($s->({ images => { $name => undef } })->{$name}, 1, "$name: undefined is on");
    }

    is_deeply($s->({ images => { sizes => [1600, 480, 960] } })->{sizes}, [480, 960, 1600], 'sizes sorted');
    is_deeply($s->({ images => { sizes => [10, 100, 2] } })->{sizes}, [2, 10, 100], 'sorted as numbers');
    is_deeply($s->({ images => { sizes => [] } })->{sizes}, [], 'sizes: [] turns resizing off');
    is_deeply($s->({ images => { sizes => '' } })->{sizes}, [], 'empty text too');
    is_deeply($s->({ images => { sizes => '800, 400 1200' } })->{sizes}, [400, 800, 1200], 'text, split on commas and spaces');
    is_deeply($s->({ images => { sizes => 640 } })->{sizes}, [640], 'one number');
    is_deeply($s->({ images => { sizes => [0, -5, 'big', '1.5', 300, '20px'] } })->{sizes}, [300], 'only whole numbers above zero');
    { local $SIG{__WARN__} = sub {};
        is_deeply($s->({ images => { sizes => undef } })->{sizes}, [], 'sizes given but empty'); }

    is($s->({ images => { quality => 70 } })->{quality}, 70, 'quality');
    is($s->({ images => { quality => 'high' } })->{quality}, 82, 'quality that is not a number');
    is($s->({ images => { quality => '90.5' } })->{quality}, 82, 'quality with a fraction');
    is($s->({ images => { quality => '' } })->{quality}, 82, 'quality empty');
    is($s->({ images => { command => 'vips' } })->{command}, 'vips', 'command');

    make_site({ '_config.yml' => "---\nname: x\nimages:\n  lazy: false\n  sizes: [300, 100]\n  quality: 60\n" });
    my $d = App::Dapper->new();
    $d->read_project();
    is_deeply(App::Dapper::Images::settings($d->{site}),
        { dimensions => 1, lazy => 0, webp => 1, sizes => [100, 300], quality => 60, command => undef }, 'from _config.yml');
    make_site({ '_config.yml' => "---\nname: x\nimages: false\n" });
    $d = App::Dapper->new();
    $d->read_project();
    is_deeply([ App::Dapper::Images::settings($d->{site}) ], [], 'images: false in _config.yml');
};

# --- variant_url --------------------------------------------------------------

subtest 'variant_url' => sub {
    my $v = \&App::Dapper::Images::variant_url;
    is($v->('/img/photo.jpg', 480), '/img/photo-480w.jpg', 'resized');
    is($v->('photo.jpg', 480, 'webp'), 'photo-480w.webp', 'resized WebP');
    is($v->('photo.jpg', undef, 'webp'), 'photo.webp', 'full-size WebP');
    is($v->('photo.jpg', undef), 'photo.jpg', 'neither');
    is($v->('photo.jpg?v=2', 480), 'photo-480w.jpg?v=2', 'query kept');
    is($v->('photo.jpg#top', 480, 'webp'), 'photo-480w.webp#top', 'fragment kept');
    is($v->('photo.jpg?a=1#b', 960), 'photo-960w.jpg?a=1#b', 'query and fragment');
    is($v->('my.photo.v2.png', 480), 'my.photo.v2-480w.png', 'only the last extension');
    is($v->('PHOTO.JPG', 480), 'PHOTO-480w.JPG', 'extension case kept');
    is($v->('PHOTO.JPG', 480, 'jpg'), 'PHOTO-480w.jpg', 'or replaced');
    is($v->('/a.b/photo', 480), '/a.b/photo', 'no extension: left alone');
    is($v->('photo', 480), 'photo', 'no extension at all');
    is($v->('https://example.com/i/p.jpeg', 1600), 'https://example.com/i/p-1600w.jpeg', 'a full address');
    is($v->('photo.jpg', 0), 'photo-0w.jpg', 'a width of 0 is still a width');
};

# --- image_tag, without resizing --------------------------------------------------

my $root = tempdir(CLEANUP => 1);
sub output_dir {
    my $out = "$root/out" . int(rand(1e9));
    my %files = (
        'img/small.png'    => png(400, 300),
        'img/big.jpg'      => jpeg(2000, 1000),
        'img/mid.png'      => png(1000, 500),
        'img/edge.png'     => png(960, 540),
        'img/tiny.jpg'     => jpeg(480, 270),
        'img/anim.gif'     => gif(3000, 2000),
        'img/photo.webp'   => webp(2400, 1600),
        'img/broken.png'   => 'not really a PNG',
        'img/my pic.png'   => png(10, 20),
        'img/vector.svg'   => '<svg/>',
        'img/zero.png'     => png(0, 10),
        'blog/rel.png'     => png(64, 32),
        'img/PHOTO.JPG'    => jpeg(2000, 1500),
    );
    spew("$out/$_", $files{$_}, ':raw') for keys %files;
    return $out;
}

sub tag_state {
    my (%settings) = @_;
    my $out = output_dir();
    my $settings = { %{ defaults() }, %settings };
    return { settings => $settings, dapper => MockDapper->new(output => $out), made => {}, command => undef };
}

sub tag { my ($state, $attrs, %o) = @_; App::Dapper::Images::image_tag($state, $attrs, $o{dir} // '/', $o{base} // '', $o{first}) }

subtest 'image_tag: dimensions and lazy loading' => sub {
    my $st = tag_state();
    is(tag($st, ' src="img/small.png" alt="S"'), '<img src="img/small.png" alt="S" width="400" height="300" loading="lazy" decoding="async">', 'later image');
    is(tag($st, ' src="img/small.png" alt="S"', first => 1), '<img src="img/small.png" alt="S" width="400" height="300">', 'first image: not lazy');
    is(tag($st, " src='img/small.png'"), q{<img src='img/small.png' width="400" height="300" loading="lazy" decoding="async">}, 'single quotes');
    is(tag($st, ' SRC="img/small.png"'), '<img SRC="img/small.png" width="400" height="300" loading="lazy" decoding="async">', 'SRC in capitals');
    is(tag($st, ' alt="x" src = "img/small.png"'), '<img alt="x" src = "img/small.png" width="400" height="300" loading="lazy" decoding="async">', 'spaces around =');
    is(tag($st, ' src="img/small.png" width="100"'), '<img src="img/small.png" width="100" loading="lazy" decoding="async">', 'its own width: no dimensions added');
    is(tag($st, ' src="img/small.png" height="100"'), '<img src="img/small.png" height="100" loading="lazy" decoding="async">', 'its own height');
    is(tag($st, ' src="img/small.png" WIDTH="100"'), '<img src="img/small.png" WIDTH="100" loading="lazy" decoding="async">', 'WIDTH in capitals');
    is(tag($st, ' src="img/small.png" width="100"', first => 1), undef, 'nothing to add: left alone');
    is(tag($st, ' src="img/small.png" loading="eager"'), '<img src="img/small.png" loading="eager" width="400" height="300">', 'its own loading kept');
    is(tag($st, ' src="img/small.png" width="1" height="1" loading="eager"'), undef, 'everything already there');
    is(tag($st, ' src="img/anim.gif"'), '<img src="img/anim.gif" width="3000" height="2000" loading="lazy" decoding="async">', 'GIF');
    is(tag($st, ' src="img/photo.webp"'), '<img src="img/photo.webp" width="2400" height="1600" loading="lazy" decoding="async">', 'WebP');
    is(tag($st, ' src="img/big.jpg"'), '<img src="img/big.jpg" width="2000" height="1000" loading="lazy" decoding="async">', 'a large JPEG, nothing to resize with');
};

subtest 'image_tag: which images' => sub {
    my $st = tag_state();
    is(tag($st, ' alt="no source"'), undef, 'no src');
    is(tag($st, ' src=img/small.png'), undef, 'src without quotes');
    is(tag($st, ' src=""'), undef, 'empty src');
    is(tag($st, ' src="https://example.com/img/small.png"'), undef, 'another site');
    is(tag($st, ' src="//cdn.example.com/img/small.png"'), undef, 'protocol-relative');
    is(tag($st, ' src="data:image/png;base64,AAAA"'), undef, 'data: URL');
    is(tag($st, ' src="#x"'), undef, 'a fragment');
    is(tag($st, ' src="img/vector.svg"'), undef, 'SVG');
    is(tag($st, ' src="img/missing.png"'), undef, 'a missing file');
    is(tag($st, ' src="img/broken.png"'), undef, 'a file whose size cannot be read');
    is(tag($st, ' src="img/zero.png"'), undef, 'a width of zero');
    is(tag($st, ' src="img"'), undef, 'a directory');
    is(tag($st, ' src="img/small.png?v=3"'), '<img src="img/small.png?v=3" width="400" height="300" loading="lazy" decoding="async">', 'a query string');
    is(tag($st, ' src="img/small.png#frag"'), '<img src="img/small.png#frag" width="400" height="300" loading="lazy" decoding="async">', 'a fragment after it');
    is(tag($st, ' src="img/my%20pic.png"'), '<img src="img/my%20pic.png" width="10" height="20" loading="lazy" decoding="async">', 'escaped characters');
    is(tag($st, ' src="/img/small.png"', dir => '/blog/2020/'), '<img src="/img/small.png" width="400" height="300" loading="lazy" decoding="async">', 'an absolute path from a page in a subdirectory');
    is(tag($st, ' src="../img/small.png"', dir => '/blog/'), '<img src="../img/small.png" width="400" height="300" loading="lazy" decoding="async">', 'a relative path up a directory');
    is(tag($st, ' src="rel.png"', dir => '/blog/'), '<img src="rel.png" width="64" height="32" loading="lazy" decoding="async">', 'next to the page');
    is(tag($st, ' src="./rel.png"', dir => '/blog/'), '<img src="./rel.png" width="64" height="32" loading="lazy" decoding="async">', 'with ./');
    is(tag($st, ' src="img/small.png"', dir => '/blog/'), undef, 'relative to the page, so not found');
    is(tag($st, ' src="https://example.com/img/small.png"', base => 'https://example.com'),
        '<img src="https://example.com/img/small.png" width="400" height="300" loading="lazy" decoding="async">', "the site's own address");
    is(tag($st, ' src="https://example.com/img/small.png"', base => 'https://example.org'), undef, 'a different address');
};

subtest 'image_tag: settings' => sub {
    is(tag(tag_state(dimensions => 0), ' src="img/small.png"'), '<img src="img/small.png" loading="lazy" decoding="async">', 'no dimensions');
    is(tag(tag_state(lazy => 0), ' src="img/small.png"'), '<img src="img/small.png" width="400" height="300">', 'no lazy loading');
    is(tag(tag_state(dimensions => 0, lazy => 0), ' src="img/small.png"'), undef, 'neither: left alone');
    is(tag(tag_state(dimensions => 0), ' src="img/small.png"', first => 1), undef, 'the first image, without dimensions');
};

# --- resizing -------------------------------------------------------------------

sub resize_state {
    my ($command, %settings) = @_;
    my $out = output_dir();
    return { settings => { %{ defaults() }, %settings }, dapper => MockDapper->new(output => $out), made => {},
             defined $command ? (command => $command) : () };
}
sub digest { my ($file) = @_; open my $fh, '<:raw', $file or die; Digest::MD5->new->addfile($fh)->hexdigest }
sub names_in { my ($dir) = @_; opendir my $dh, $dir or return []; [ sort grep { !/^\./ } readdir $dh ] }

subtest 'image_tag: srcset, sizes and WebP with ImageMagick' => sub {
    make_site({}, bare => 1);
    unlink $log;
    my $st = resize_state(["$bin/magick/magick", 'magick']);
    my $out = $st->{dapper}->{output};
    my $sizes = 'sizes="(max-width: 2000px) 100vw, 2000px"';
    is(tag($st, ' src="img/big.jpg" alt="Big"'),
        qq{<picture><source type="image/webp" srcset="img/big-480w.webp 480w, img/big-960w.webp 960w, img/big-1600w.webp 1600w, img/big.webp 2000w" $sizes>}
        . qq{<img src="img/big.jpg" alt="Big" width="2000" height="1000" loading="lazy" decoding="async" srcset="img/big-480w.jpg 480w, img/big-960w.jpg 960w, img/big-1600w.jpg 1600w, img/big.jpg 2000w" $sizes></picture>},
        'every size, WebP in a picture');
    is_deeply(names_in("$out/img"), [ sort 'PHOTO.JPG', 'anim.gif', 'big.jpg', 'broken.png', 'edge.png', 'mid.png', 'my pic.png', 'photo.webp', 'zero.png',
        'small.png', 'tiny.jpg', 'vector.svg', map({; "big-${_}w.jpg", "big-${_}w.webp" } 480, 960, 1600), 'big.webp' ], 'the copies, next to the image');
    is_deeply([ sort keys %{$st->{dapper}->{written}} ],
        [ sort map({; "img/big-${_}w.jpg", "img/big-${_}w.webp" } 480, 960, 1600), 'img/big.webp' ], 'recorded as written');

    my $d = digest("$out/img/big.jpg");
    is_deeply(names_in('.dapper/images'), [ sort map({; "$d-$_-82.jpg" } 480, 960, 1600), map({; "$d-$_-82.webp" } 480, 960, 1600, 2000) ], 'cached by content, size and quality');
    my $file = "$out/img/big.jpg";
    is_deeply(calls(), [
        map({; "magick $file -auto-orient -strip -resize ${_}x -quality 82 .dapper/images/$d-$_-82.jpg" } 480, 960, 1600),
        map({; "magick $file -auto-orient -strip -resize ${_}x -quality 82 .dapper/images/$d-$_-82.webp" } 480, 960, 1600, 2000),
    ], 'how ImageMagick was run');

    unlink $log;
    my $again = resize_state(["$bin/magick/magick", 'magick']);
    ok(defined tag($again, ' src="img/big.jpg"'), 'a second time');
    is_deeply(calls(), [], 'the cache is used');
    ok(-f "$again->{dapper}->{output}/img/big-480w.jpg", 'and the copies are still written');

    unlink $log;
    my $q = resize_state(["$bin/magick/magick", 'magick'], quality => 60);
    tag($q, ' src="img/big.jpg"');
    is(scalar @{ calls() }, 7, 'a new quality makes new copies');
    like(calls()->[0], qr{-quality 60 \.dapper/images/$d-480-60\.jpg$}, 'at that quality');
};

subtest 'image_tag: which sizes' => sub {
    make_site({}, bare => 1);
    my $st = resize_state(["$bin/magick/magick", 'magick'], webp => 0);
    is(tag($st, ' src="img/mid.png"'),
        '<img src="img/mid.png" width="1000" height="500" loading="lazy" decoding="async" srcset="img/mid-480w.png 480w, img/mid-960w.png 960w, img/mid.png 1000w" sizes="(max-width: 1000px) 100vw, 1000px">',
        'only sizes smaller than the image; no WebP');
    is(tag($st, ' src="img/edge.png"', first => 1),
        '<img src="img/edge.png" width="960" height="540" srcset="img/edge-480w.png 480w, img/edge.png 960w" sizes="(max-width: 960px) 100vw, 960px">',
        'a size equal to the width is not made');
    is(tag($st, ' src="img/tiny.jpg"'), '<img src="img/tiny.jpg" width="480" height="270" loading="lazy" decoding="async">', 'no smaller size: no srcset');
    is(tag($st, ' src="img/small.png"'), '<img src="img/small.png" width="400" height="300" loading="lazy" decoding="async">', 'smaller than every size');
    is(tag($st, ' src="img/anim.gif"'), '<img src="img/anim.gif" width="3000" height="2000" loading="lazy" decoding="async">', 'GIFs are not resized');
    is(tag($st, ' src="img/photo.webp"'), '<img src="img/photo.webp" width="2400" height="1600" loading="lazy" decoding="async">', 'WebP files are not resized');
    is(tag($st, ' src="img/big.jpg" srcset="a.jpg 1x, b.jpg 2x"'), '<img src="img/big.jpg" srcset="a.jpg 1x, b.jpg 2x" width="2000" height="1000" loading="lazy" decoding="async">', 'its own srcset kept');
    is(tag($st, ' src="img/big.jpg" SRCSET="a.jpg 1x"', first => 1), '<img src="img/big.jpg" SRCSET="a.jpg 1x" width="2000" height="1000">', 'SRCSET in capitals');
    is(tag($st, ' src="img/big.jpg?v=2"', first => 1),
        '<img src="img/big.jpg?v=2" width="2000" height="1000" srcset="img/big-480w.jpg?v=2 480w, img/big-960w.jpg?v=2 960w, img/big-1600w.jpg?v=2 1600w, img/big.jpg?v=2 2000w" sizes="(max-width: 2000px) 100vw, 2000px">',
        'the query string is kept on every size');
    is(tag($st, ' src="/img/big.jpg"', dir => '/blog/', first => 1),
        '<img src="/img/big.jpg" width="2000" height="1000" srcset="/img/big-480w.jpg 480w, /img/big-960w.jpg 960w, /img/big-1600w.jpg 1600w, /img/big.jpg 2000w" sizes="(max-width: 2000px) 100vw, 2000px">',
        'an absolute path');
    is(tag($st, ' src="../img/big.jpg"', dir => '/blog/', first => 1),
        '<img src="../img/big.jpg" width="2000" height="1000" srcset="../img/big-480w.jpg 480w, ../img/big-960w.jpg 960w, ../img/big-1600w.jpg 1600w, ../img/big.jpg 2000w" sizes="(max-width: 2000px) 100vw, 2000px">',
        'a relative path');

    my $one = resize_state(["$bin/magick/magick", 'magick'], sizes => [1200]);
    is(tag($one, ' src="img/big.jpg"', first => 1),
        '<picture><source type="image/webp" srcset="img/big-1200w.webp 1200w, img/big.webp 2000w" sizes="(max-width: 2000px) 100vw, 2000px">'
        . '<img src="img/big.jpg" width="2000" height="1000" srcset="img/big-1200w.jpg 1200w, img/big.jpg 2000w" sizes="(max-width: 2000px) 100vw, 2000px"></picture>',
        'sizes of your own');

    my $none = resize_state(["$bin/magick/magick", 'magick'], sizes => []);
    is(tag($none, ' src="img/big.jpg"', first => 1), '<img src="img/big.jpg" width="2000" height="1000">', 'sizes: []');
    my $nothing = resize_state(["$bin/magick/magick", 'magick'], sizes => [], dimensions => 0);
    is(tag($nothing, ' src="img/big.jpg"', first => 1), undef, 'nothing to do');
    my $only = resize_state(["$bin/magick/magick", 'magick'], dimensions => 0, lazy => 0, webp => 0);
    is(tag($only, ' src="img/mid.png"'),
        '<img src="img/mid.png" srcset="img/mid-480w.png 480w, img/mid-960w.png 960w, img/mid.png 1000w" sizes="(max-width: 1000px) 100vw, 1000px">',
        'only srcset');
};

subtest 'image_tag: a file name in capitals' => sub {
    make_site({}, bare => 1);
    my $st = resize_state(["$bin/magick/magick", 'magick'], webp => 0, sizes => [480]);
    my $tag = tag($st, ' src="img/PHOTO.JPG"', first => 1);
    my ($listed) = $tag =~ /srcset="(\S+) 480w/;
    is($listed, 'img/PHOTO-480w.JPG', 'srcset keeps the extension as written');
    my %present = map { $_ => 1 } @{ names_in("$st->{dapper}->{output}/img") };
    ok($present{'PHOTO-480w.JPG'}, 'the file named in srcset exists, with exactly that name');
};

subtest 'image_tag: resizing that fails' => sub {
    make_site({}, bare => 1);
    my $st = resize_state(["$bin/fail/magick", 'magick']);
    my $out = $st->{dapper}->{output};
    is(tag($st, ' src="img/big.jpg"', first => 1), '<img src="img/big.jpg" width="2000" height="1000">', 'a command that fails: no srcset');
    is(scalar @{$st->{dapper}->{problems}}, 7, 'a warning for each copy');
    is_deeply($st->{dapper}->{problems}->[0], ['warning', "$out/img/big.jpg", "could not resize $out/img/big.jpg with $bin/fail/magick"], 'what it says');
    is_deeply(names_in('.dapper/images'), [], 'nothing cached');

    my $empty = resize_state(["$bin/empty/magick", 'magick'], webp => 0);
    is(tag($empty, ' src="img/big.jpg"', first => 1), '<img src="img/big.jpg" width="2000" height="1000">', 'a command that writes nothing');
    is(scalar @{$empty->{dapper}->{problems}}, 3, 'a warning for each size');

    my $some = resize_state(["$bin/some/magick", 'magick']);
    is(tag($some, ' src="img/big.jpg"', first => 1),
        '<picture><source type="image/webp" srcset="img/big-480w.webp 480w, img/big-1600w.webp 1600w, img/big.webp 2000w" sizes="(max-width: 2000px) 100vw, 2000px">'
        . '<img src="img/big.jpg" width="2000" height="1000" srcset="img/big-480w.jpg 480w, img/big-1600w.jpg 1600w, img/big.jpg 2000w" sizes="(max-width: 2000px) 100vw, 2000px"></picture>',
        'only the sizes that worked are listed');
    is_deeply([ map { $_->[2] =~ /could not resize/ ? 1 : 0 } @{$some->{dapper}->{problems}} ], [1, 1], 'two warnings, for 960 and its WebP');
    ok(!-e "$some->{dapper}->{output}/img/big-960w.jpg", 'no copy for the size that failed');
};

subtest 'resize with libvips' => sub {
    make_site({}, bare => 1);
    unlink $log;
    my $st = resize_state(["$bin/vips/vips", 'vips'], webp => 0, sizes => [480]);
    my $out = $st->{dapper}->{output};
    is(tag($st, ' src="img/big.jpg"', first => 1),
        '<img src="img/big.jpg" width="2000" height="1000" srcset="img/big-480w.jpg 480w, img/big.jpg 2000w" sizes="(max-width: 2000px) 100vw, 2000px">', 'srcset');
    my $d = digest("$out/img/big.jpg");
    is_deeply(calls(), ["vips thumbnail $out/img/big.jpg .dapper/images/$d-480-82.jpg[Q=82,strip] 480"], 'how vips was run');
    ok(-f "$out/img/big-480w.jpg", 'the copy');

    unlink $log;
    ok(App::Dapper::Images::resize(["$bin/vips/vips", 'vips'], "$out/img/mid.png", 'x.webp', 300, 75), 'resize returns true');
    is_deeply(calls(), ["vips thumbnail $out/img/mid.png x.webp[Q=75,strip] 300"], 'WebP at another quality');
    unlink $log;
    ok(App::Dapper::Images::resize(["$bin/convert/convert", 'convert'], "$out/img/mid.png", 'y.png', 200, 90), 'convert');
    is_deeply(calls(), ["convert $out/img/mid.png -auto-orient -strip -resize 200x -quality 90 y.png"], 'run like magick');
    ok(!App::Dapper::Images::resize(["$bin/fail/magick", 'magick'], "$out/img/mid.png", 'z.png', 200, 90), 'false when it fails');
    ok(!App::Dapper::Images::resize(["$bin/empty/magick", 'magick'], "$out/img/mid.png", 'e.png', 200, 90), 'false when nothing is written');
    ok(!App::Dapper::Images::resize(["$bin/nope/magick", 'magick'], "$out/img/mid.png", 'n.png', 200, 90), 'false when the program is missing');
};

subtest 'variants' => sub {
    make_site({}, bare => 1);
    my $st = resize_state(["$bin/magick/magick", 'magick']);
    my $out = $st->{dapper}->{output};
    is_deeply([ App::Dapper::Images::variants($st, "$out/img/big.jpg", 2000, 1000, [480, 960]) ], [
        { width => 480, ext => 'same' }, { width => 960, ext => 'same' },
        { width => 480, ext => 'webp' }, { width => 960, ext => 'webp' },
        { width => 2000, ext => 'webp', full => 1 },
    ], 'each copy made');
    my $no = resize_state(["$bin/magick/magick", 'magick'], webp => 0);
    is_deeply([ App::Dapper::Images::variants($no, "$out/img/mid.png", 1000, 500, [480]) ], [ { width => 480, ext => 'same' } ], 'without WebP');
    my $none = resize_state(undef);
    $none->{command} = undef;
    is_deeply([ App::Dapper::Images::variants($none, "$out/img/mid.png", 1000, 500, [480]) ], [], 'no command: nothing');
    make_site({}, bare => 1);
    my $failing = resize_state(["$bin/fail/magick", 'magick']);
    is_deeply([ App::Dapper::Images::variants($failing, "$out/img/mid.png", 1000, 500, [480]) ], [], 'all failed: nothing, not even the full-size WebP');
    is_deeply([ App::Dapper::Images::variants($st, "$out/img/missing.png", 1000, 500, [480]) ], [], 'a file that cannot be read');
};

subtest 'command' => sub {
    my $find = sub {
        my ($path, $setting) = @_;
        local $ENV{PATH} = $path;
        my $st = { settings => { %{ defaults() }, command => $setting }, dapper => MockDapper->new() };
        my $command = App::Dapper::Images::command($st);
        return ($command, $st);
    };
    my ($c, $st);
    ($c) = $find->("$bin/all");
    is_deeply($c, ['magick', 'magick'], 'magick first');
    ($c) = $find->("$bin/convert:$bin/vips");
    is_deeply($c, ['convert', 'convert'], 'then convert');
    ($c) = $find->("$bin/vips");
    is_deeply($c, ['vips', 'vips'], 'then vips');
    ($c) = $find->("/nonexistent:$bin/vips:$bin/convert");
    is_deeply($c, ['convert', 'convert'], 'in that order, wherever they are on the path');
    ($c) = $find->("$bin/all", 'vips');
    is_deeply($c, ['vips', 'vips'], 'the setting wins');
    ($c) = $find->("$bin/all", 'convert');
    is_deeply($c, ['convert', 'convert'], 'convert by setting');
    ($c) = $find->('/nonexistent', "$bin/paths/my-resizer");
    is_deeply($c, ["$bin/paths/my-resizer", 'magick'], 'a path: run like ImageMagick unless named for vips');
    ($c) = $find->('/nonexistent', "$bin/paths/vipsthumb");
    is_deeply($c, ["$bin/paths/vipsthumb", 'vips'], 'a path named for vips');
    ($c) = $find->('/nonexistent', "$bin/vips/vips");
    is_deeply($c, ["$bin/vips/vips", 'vips'], 'the full path of vips');

    ($c, $st) = $find->('/nonexistent', "$bin/paths/not-executable");
    is($c, undef, 'a path that cannot be run');
    is_deeply($st->{dapper}->{problems}, [['warning', '_config.yml',
        'resizing images needs ImageMagick or libvips; install one (for example "brew install imagemagick"), or set sizes: [] under images']], 'a warning');

    ($c, $st) = $find->("$bin/all", 'gm');
    is($c, undef, 'a setting that is not installed');
    is(scalar @{$st->{dapper}->{problems}}, 1, 'warns');

    ($c, $st) = $find->('/nonexistent');
    is($c, undef, 'none installed');
    {
        local $ENV{PATH} = "$bin/all";
        is(App::Dapper::Images::command($st), undef, 'the answer is kept, even after one is installed');
    }
    is(scalar @{$st->{dapper}->{problems}}, 1, 'and the warning is given once');
    ok(exists $st->{command}, 'remembered in the state');

    ($c, $st) = $find->("$bin/magick");
    {
        local $ENV{PATH} = '/nonexistent';
        is_deeply(App::Dapper::Images::command($st), ['magick', 'magick'], 'a found command is kept too');
    }
};

# --- in a site ------------------------------------------------------------------

my %images = (
    '_source/img/big.jpg'    => jpeg(2000, 1000),
    '_source/img/small.png'  => png(400, 300),
    '_source/img/mid.png'    => png(1000, 500),
    '_source/img/logo.gif'   => gif(120, 60),
    '_source/blog/local.png' => png(50, 40),
);
sub image_site {
    my ($files) = @_;
    make_site($files);
    spew($_, $images{$_}, ':raw') for keys %images;
}

subtest 'in a site: pages and what is left alone' => sub {
    local $ENV{PATH} = '/nonexistent';
    image_site({
        '_config.yml' => "---\nname: x\nurl: https://example.com/\nimages:\n  sizes: []\n",
        '_source/index.md' => "---\ntitle: Home\n---\n![Remote](https://other.example/x.png)\n\n![Small](img/small.png)\n\n"
            . "<!-- <img src=\"img/small.png\" alt=\"commented\"> -->\n\n<code><img src=\"img/small.png\" alt=\"code\"></code>\n\n"
            . "<picture><img src=\"img/small.png\" alt=\"pic\"></picture>\n\n<img src=\"img/logo.gif\" alt=\"Closed\" />\n\n"
            . "<img src=\"https://example.com/img/small.png\" alt=\"Own\">\n\n<IMG SRC=\"img/small.png\" ALT=\"Caps\">\n",
        '_source/blog/post.md' => "---\ntitle: Post\n---\n![Up](../img/small.png)\n\n![Root](/img/small.png)\n\n![Here](local.png)\n\n![Wrong](img/small.png)\n",
        '_source/plain.html' => "<p><img src=\"img/logo.gif\" alt=\"A\"><img src=\"img/logo.gif\" alt=\"B\"></p>\n",
        '_source/legacy.htm' => "<img src=\"img/logo.gif\">\n",
        '_source/notes.txt' => "<img src=\"img/logo.gif\">\n",
        '_source/no-images.md' => "---\ntitle: None\n---\nJust words.\n",
    });
    quiet_build();
    my $html = slurp('_output/index.html');
    like($html, qr{<img src="https://other\.example/x\.png" alt="Remote" id="remote" />}, 'another site: left alone');
    like($html, qr{<img src="img/small\.png" alt="Small" id="small" width="400" height="300" loading="lazy" decoding="async">}, 'counted after a remote first image, so lazy');
    like($html, qr{<!-- <img src="img/small\.png" alt="commented"> -->}, 'a comment left alone');
    like($html, qr{<code><img src="img/small\.png" alt="code"></code>}, 'code left alone');
    like($html, qr{<picture><img src="img/small\.png" alt="pic"></picture>}, 'a picture left alone');
    like($html, qr{<img src="img/logo\.gif" alt="Closed" width="120" height="60" loading="lazy" decoding="async"></p>}, 'a self-closing tag loses its slash');
    like($html, qr{<img src="https://example\.com/img/small\.png" alt="Own" width="400" height="300" loading="lazy" decoding="async">}, "the site's own address");
    like($html, qr{<img SRC="img/small\.png" ALT="Caps" width="400" height="300" loading="lazy" decoding="async">}, 'capitals (Markdown lowercases the tag name)');

    my $post = slurp('_output/blog/post.html');
    like($post, qr{<img src="\.\./img/small\.png" alt="Up" id="up" width="400" height="300">}, 'first image on a page in a folder: not lazy');
    like($post, qr{<img src="/img/small\.png" alt="Root" id="root" width="400" height="300" loading="lazy" decoding="async">}, 'from the root');
    like($post, qr{<img src="local\.png" alt="Here" id="here" width="50" height="40" loading="lazy" decoding="async">}, 'next to the page');
    like($post, qr{<img src="img/small\.png" alt="Wrong" id="wrong" />}, 'a path that does not exist from there');

    is(slurp('_output/plain.html'), qq{<p><img src="img/logo.gif" alt="A" width="120" height="60"><img src="img/logo.gif" alt="B" width="120" height="60" loading="lazy" decoding="async"></p>\n},
        'an HTML file without front matter');
    is(slurp('_output/legacy.htm'), qq{<img src="img/logo.gif" width="120" height="60">\n}, '.htm');
    is(slurp('_output/notes.txt'), qq{<img src="img/logo.gif">\n}, 'not HTML: left alone');
};

subtest 'in a site: responsive copies, then fewer, then none' => sub {
    local $ENV{PATH} = "$bin/magick";
    image_site({
        '_config.yml' => "---\nname: x\nimages:\n  sizes: [480, 960]\n  webp: false\n",
        '_source/index.md' => "---\ntitle: Home\n---\n![Big](img/big.jpg)\n\n![Mid](img/mid.png)\n",
    });
    quiet_build();
    my $html = slurp('_output/index.html');
    like($html, qr{<img src="img/big\.jpg" alt="Big" id="big" width="2000" height="1000" srcset="img/big-480w\.jpg 480w, img/big-960w\.jpg 960w, img/big\.jpg 2000w" sizes="\(max-width: 2000px\) 100vw, 2000px">}, 'the first image');
    like($html, qr{<img src="img/mid\.png" alt="Mid" id="mid" width="1000" height="500" loading="lazy" decoding="async" srcset="img/mid-480w\.png 480w, img/mid-960w\.png 960w, img/mid\.png 1000w"}, 'the second');
    ok(-f "_output/img/$_", $_) for qw/ big-480w.jpg big-960w.jpg mid-480w.png mid-960w.png /;
    ok(!-e '_output/img/big.webp', 'no WebP');
    my $manifest = slurp('.dapper/manifest.json');
    like($manifest, qr{"img/big-960w\.jpg"}, 'the copies are in the manifest');

    spew('_config.yml', "---\nname: x\nimages:\n  sizes: [480]\n  webp: false\n");
    quiet_build();
    ok(-f '_output/img/big-480w.jpg', 'a size still wanted is kept');
    ok(!-e '_output/img/big-960w.jpg', 'a size no longer wanted is removed');
    ok(!-e '_output/img/mid-960w.png', 'for every image');
    like(slurp('_output/index.html'), qr{srcset="img/big-480w\.jpg 480w, img/big\.jpg 2000w"}, 'and not listed');

    spew('_config.yml', "---\nname: x\n");
    quiet_build();
    ok(!-e '_output/img/big-480w.jpg', 'images turned off: the copies are removed');
    ok(-f '_output/img/big.jpg', 'the image itself stays');
    ok(-d '.dapper/images', 'the cache stays');
    unlike(slurp('_output/index.html'), qr{width=|srcset}, 'and the page is left as it was');
};

subtest 'in a site: one warning without a resizing command' => sub {
    local $ENV{PATH} = '/nonexistent';
    image_site({
        '_config.yml' => "---\nname: x\nimages: true\n",
        '_source/index.md' => "---\ntitle: Home\n---\n![Big](img/big.jpg)\n\n![Mid](img/mid.png)\n",
        '_source/two.md' => "---\ntitle: Two\n---\n![Big](img/big.jpg)\n",
    });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    is_deeply(\@warnings, [qq{warning: resizing images needs ImageMagick or libvips; install one (for example "brew install imagemagick"), or set sizes: [] under images\n}],
        'one warning for the whole site');
    like(slurp('_output/two.html'), qr{<img src="img/big\.jpg" alt="Big" id="big" width="2000" height="1000"></p>}, 'dimensions on every page');

    @warnings = ();
    spew('_config.yml', "---\nname: x\nimages:\n  sizes: []\n");
    quiet_build();
    is_deeply(\@warnings, [], 'none with sizes: []');
};

subtest 'in a site: the command setting' => sub {
    local $ENV{PATH} = "$bin/all";
    unlink $log;
    image_site({
        '_config.yml' => "---\nname: x\nimages:\n  command: vips\n  sizes: [480]\n  webp: false\n",
        '_source/index.md' => "---\ntitle: Home\n---\n![Big](img/big.jpg)\n",
    });
    quiet_build();
    like(calls()->[0], qr{^vips thumbnail _output/img/big\.jpg \.dapper/images/\w+-480-82\.jpg\[Q=82,strip\] 480$}, 'vips is used');
    ok(-f '_output/img/big-480w.jpg', 'the copy');
};

done_testing();
