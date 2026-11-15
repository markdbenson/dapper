use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Utils;

use File::Temp qw(tempdir);
use Scalar::Util qw(refaddr);
use POSIX ();
use DateTime;

binmode(Test::More->builder->$_, ':encoding(UTF-8)') for qw(output failure_output todo_output);

# Each subtest works in a fresh temporary directory
sub in_tmp { my $dir = tempdir(CLEANUP => 1); chdir $dir or die; return $dir }

sub dies_like {
    my ($code, $re, $name) = @_;
    eval { $code->(); 1 } and do { fail("$name (did not die)"); return };
    like($@, $re, $name);
}

subtest 'read_file' => sub {
    in_tmp();
    spew('plain.txt', "line one\nline two\n");
    is(App::Dapper::Utils::read_file('plain.txt'), "line one\nline two\n", 'whole file read');

    spew('empty.txt', '');
    is(App::Dapper::Utils::read_file('empty.txt'), '', 'empty file is an empty string, not undef');
    ok(defined App::Dapper::Utils::read_file('empty.txt'), 'defined');

    spew('utf8.txt', "caf\xC3\xA9 \xE6\x97\xA5\n", ':raw');
    my $text = App::Dapper::Utils::read_file('utf8.txt');
    is($text, "café 日\n", 'decoded from UTF-8');
    is(length $text, 7, 'characters, not bytes');

    spew('nolf.txt', 'no newline');
    is(App::Dapper::Utils::read_file('nolf.txt'), 'no newline', 'no trailing newline added');

    dies_like(sub { App::Dapper::Utils::read_file('missing.txt') },
        qr/^error: could not open "missing\.txt": /, 'missing file is a clear error');
};

subtest 'write_file' => sub {
    in_tmp();
    App::Dapper::Utils::write_file('a/b/c/deep.txt', "Zoë\n");
    ok(-f 'a/b/c/deep.txt', 'missing parent directories created');
    is(slurp('a/b/c/deep.txt', ':raw'), "Zo\xC3\xAB\n", 'written as UTF-8 bytes');

    App::Dapper::Utils::write_file('a/b/c/deep.txt', "new");
    is(slurp('a/b/c/deep.txt'), 'new', 'an existing file is replaced');

    App::Dapper::Utils::write_file('top.txt', '');
    ok(-f 'top.txt' && -z 'top.txt', 'an empty file can be written in the current directory');

    mkdir 'adir';
    dies_like(sub { App::Dapper::Utils::write_file('adir', 'x') },
        qr/^error: could not open "adir" for writing: /, 'writing over a directory is a clear error');
};

subtest 'has_frontmatter' => sub {
    in_tmp();
    my %cases = (
        'plain.md'      => ["---\ntitle: x\n---\n", 1, 'front matter'],
        'trailing.md'   => ["---  \t\ntitle: x\n---\n", 1, 'spaces and tabs after the dashes'],
        'crlf.md'       => ["---\r\ntitle: x\r\n---\r\n", 1, 'CRLF line endings'],
        'bom.md'        => ["\xEF\xBB\xBF---\ntitle: x\n---\n", 1, 'UTF-8 byte order mark'],
        'only.md'       => ["---", 1, 'just three dashes at the end of the file'],
        'four.md'       => ["----\ntitle: x\n", 0, 'four dashes is not front matter'],
        'text.md'       => ["---text\n", 0, 'text after the dashes'],
        'late.md'       => ["\n---\ntitle: x\n---\n", 0, 'dashes not on the first line'],
        'space.md'      => [" ---\ntitle: x\n---\n", 0, 'indented dashes'],
        'empty.md'      => ["", 0, 'empty file'],
        'heading.md'    => ["# Title\n---\n", 0, 'ordinary markdown'],
        'bin.dat'       => [join('', map { chr } 0 .. 255), 0, 'binary data'],
        'twobom.md'     => ["\xEF\xBB\xBF\xEF\xBB\xBF---\n", 0, 'two byte order marks'],
    );
    for my $file (sort keys %cases) {
        spew($file, $cases{$file}[0], ':raw');
        is(App::Dapper::Utils::has_frontmatter($file), $cases{$file}[1], $cases{$file}[2]);
    }

    # only the first 64 bytes are looked at; the result is still right for a
    # long file
    spew('long.md', "---\ntitle: x\n---\n" . ('y' x 100_000), ':raw');
    is(App::Dapper::Utils::has_frontmatter('long.md'), 1, 'long file');

    dies_like(sub { App::Dapper::Utils::has_frontmatter('nope.md') },
        qr/^error: could not open "nope\.md": /, 'missing file');
};

subtest 'split_frontmatter' => sub {
    my ($fm, $body);

    ($fm, $body) = App::Dapper::Utils::split_frontmatter("---\ntitle: Hi\nn: 3\n---\nBody\n", 'x');
    is_deeply($fm, { title => 'Hi', n => 3 }, 'front matter parsed');
    is($body, "\nBody\n", 'body keeps the newline after the closing dashes');

    ($fm, $body) = App::Dapper::Utils::split_frontmatter("\x{FEFF}---\ntitle: Bom\n---\nB", 'x');
    is_deeply($fm, { title => 'Bom' }, 'byte order mark before the front matter');
    is($body, "\nB", 'body after a byte order mark');

    ($fm, $body) = App::Dapper::Utils::split_frontmatter("---\r\ntitle: Win\r\n---\r\nBody\r\n", 'x');
    is_deeply($fm, { title => 'Win' }, 'CRLF front matter');
    is($body, "\r\nBody\r\n", 'CRLF body left alone');

    ($fm, $body) = App::Dapper::Utils::split_frontmatter("--- \t\ntitle: T\n---  \nBody", 'x');
    is_deeply($fm, { title => 'T' }, 'trailing whitespace on both fences');
    is($body, "\nBody", 'body');

    ($fm, $body) = App::Dapper::Utils::split_frontmatter("---\ntitle: End\n---", 'x');
    is_deeply($fm, { title => 'End' }, 'closing dashes at the very end');
    is($body, '', 'empty body');

    ($fm, $body) = App::Dapper::Utils::split_frontmatter("---\n---\n", 'x');
    is_deeply($fm, {}, 'empty front matter is an empty hash');
    is($body, "\n", 'body');

    ($fm, $body) = App::Dapper::Utils::split_frontmatter("---\n# just a comment\n---\nx", 'x');
    is_deeply($fm, {}, 'front matter with only a comment');

    ($fm, $body) = App::Dapper::Utils::split_frontmatter("---\na: 1\n---\nmiddle\n---\nend\n", 'x');
    is_deeply($fm, { a => 1 }, 'the first closing line ends the front matter');
    is($body, "\nmiddle\n---\nend\n", 'later dashes stay in the body');

    ($fm, $body) = App::Dapper::Utils::split_frontmatter("---\ntitle: a---b\nlist:\n  - x\n  - y\n---\n", 'x');
    is_deeply($fm, { title => 'a---b', list => ['x', 'y'] }, 'dashes inside values and nested data');

    ($fm, $body) = App::Dapper::Utils::split_frontmatter("---\ntitle: Café 日本\n---\nZoë", 'x');
    is($fm->{title}, 'Café 日本', 'Unicode in front matter');
    is($body, "\nZoë", 'Unicode in the body');

    is_deeply([App::Dapper::Utils::split_frontmatter("no front matter\n", 'x')], [], 'no front matter: empty list');
    is_deeply([App::Dapper::Utils::split_frontmatter("---\ntitle: open\n", 'x')], [], 'never closed: empty list');
    is_deeply([App::Dapper::Utils::split_frontmatter("x---\na: 1\n---\n", 'x')], [], 'text before the dashes');
    is_deeply([App::Dapper::Utils::split_frontmatter("---\na: 1\n----\nb\n", 'x')], [], 'four dashes do not close');
    is_deeply([App::Dapper::Utils::split_frontmatter(undef, 'x')], [], 'undef: empty list');
    is_deeply([App::Dapper::Utils::split_frontmatter('', 'x')], [], 'empty string: empty list');

    dies_like(sub { App::Dapper::Utils::split_frontmatter("---\ntitle: [oops\n---\n", 'my/page.md') },
        qr/^error: could not parse front matter in "my\/page\.md": /, 'invalid YAML names the file');
    dies_like(sub { App::Dapper::Utils::split_frontmatter("---\n- a\n- b\n---\n", 'list.md') },
        qr/^error: front matter in "list\.md" must be a set of key: value pairs$/, 'a list is not allowed');
    dies_like(sub { App::Dapper::Utils::split_frontmatter("---\njust a string\n---\n", 's.md') },
        qr/^error: front matter in "s\.md" must be a set of key: value pairs$/, 'a scalar is not allowed');
};

subtest 'parse_date: formats' => sub {
    my %cases = (
        '2014-05-02T10:30:00'        => ['2014-05-02T10:30:00+00:00', 'floating', 'ISO 8601'],
        '2014-05-02 10:30:00'        => ['2014-05-02T10:30:00+00:00', 'floating', 'space instead of T'],
        '2014-05-02    10:30:00'     => ['2014-05-02T10:30:00+00:00', 'floating', 'several spaces instead of T'],
        '2014-05-02T10:30'           => ['2014-05-02T10:30:00+00:00', 'floating', 'no seconds'],
        '2014-05-02 10:30'           => ['2014-05-02T10:30:00+00:00', 'floating', 'space and no seconds'],
        '2014-05-02'                 => ['2014-05-02T00:00:00+00:00', 'floating', 'date only is midnight'],
        "  2014-05-02\t\n"           => ['2014-05-02T00:00:00+00:00', 'floating', 'surrounding whitespace trimmed'],
        '2014-05-02T10:30:00Z'       => ['2014-05-02T10:30:00+00:00', 'UTC', 'Z is UTC'],
        '2014-05-02T10:30:00-05:00'  => ['2014-05-02T10:30:00-05:00', '-0500', 'negative offset'],
        '2014-05-02T10:30:00+09:30'  => ['2014-05-02T10:30:00+09:30', '+0930', 'half hour offset'],
        '2014-05-02 10:30:00+01:00'  => ['2014-05-02T10:30:00+01:00', '+0100', 'space and offset'],
        '2014-05-02T23:59:59'        => ['2014-05-02T23:59:59+00:00', 'floating', 'end of the day'],
        '2016-02-29'                 => ['2016-02-29T00:00:00+00:00', 'floating', 'leap day'],
        '1970-01-01T00:00:00Z'       => ['1970-01-01T00:00:00+00:00', 'UTC', 'the epoch'],
        '20140502'                   => ['2014-05-02T00:00:00+00:00', 'floating', 'ISO 8601 basic format'],
    );
    for my $input (sort keys %cases) {
        my ($want, $zone, $name) = @{ $cases{$input} };
        my $dt = App::Dapper::Utils::parse_date($input);
        isa_ok($dt, 'App::Dapper::Date', $name);
        isa_ok($dt, 'DateTime', $name);
        is($dt->xmlschema, $want, "$name: value");
        is($dt->time_zone->name, $zone, "$name: time zone");
    }

    my $dt = App::Dapper::Utils::parse_date('2014-05-02T10:30:45');
    is(join(' ', $dt->year, $dt->month, $dt->day, $dt->hour, $dt->minute, $dt->second),
        '2014 5 2 10 30 45', 'parts');
};

subtest 'parse_date: errors' => sub {
    for my $bad ('yesterday', '2014/05/02', '05-02-2014', '2014-13-01', '2014-02-30', '2015-02-29',
                 '2014-05-02T25:00:00', '2014-05-02T9:30:00', '2014-5-2', '2014-05-02T10:30:00+5') {
        dies_like(sub { App::Dapper::Utils::parse_date($bad) },
            qr/^error: could not understand the date "\Q$bad\E"\. Use the ISO 8601 format, e\.g\. 2014-05-02T10:30:00\n\z/,
            "rejects '$bad'");
    }
    dies_like(sub { App::Dapper::Utils::parse_date('nope', '_source/a.md') },
        qr/^error: could not understand the date "nope" in "_source\/a\.md"\. Use the ISO 8601 format/,
        'the file is named');
    dies_like(sub { App::Dapper::Utils::parse_date('', 'x') },
        qr/^error: could not understand the date "" in "x"/, 'empty string');
    {
        my @warnings;
        local $SIG{__WARN__} = sub { push @warnings, @_ };
        dies_like(sub { App::Dapper::Utils::parse_date(undef) },
            qr/^error: could not understand the date ""/, 'undef');
        is(scalar @warnings, 0, 'no warning for undef');
    }
};

subtest 'parse_date: DateTime objects' => sub {
    my $dt = DateTime->new(year => 2020, month => 1, day => 2, hour => 3, time_zone => 'Asia/Tokyo');
    my $parsed = App::Dapper::Utils::parse_date($dt);
    isa_ok($parsed, 'App::Dapper::Date');
    isnt(refaddr($parsed), refaddr($dt), 'a plain DateTime is cloned');
    is(ref $dt, 'DateTime', 'the original is not reblessed');
    is($parsed->xmlschema, '2020-01-02T03:00:00+09:00', 'value and time zone kept');

    my $again = App::Dapper::Utils::parse_date($parsed);
    is(refaddr($again), refaddr($parsed), 'an App::Dapper::Date is returned as it is');

    my $floating = DateTime->new(year => 2000, month => 6, day => 15);
    is(App::Dapper::Utils::parse_date($floating)->time_zone->name, 'floating', 'floating stays floating');

    # Something that stringifies to a date
    {
        package My::DateLike;
        use overload '""' => sub { '2011-11-11T11:11:11' }, fallback => 1;
    }
    my $like = bless {}, 'My::DateLike';
    is(App::Dapper::Utils::parse_date($like)->xmlschema, '2011-11-11T11:11:11+00:00',
        'other objects are parsed from their string form');
};

subtest 'xmlschema' => sub {
    my $utc = bless(DateTime->new(year => 2014, month => 5, day => 2, hour => 10, minute => 30, time_zone => 'UTC'),
        'App::Dapper::Date');
    is($utc->xmlschema, '2014-05-02T10:30:00+00:00', 'UTC');
    my $ny = App::Dapper::Utils::parse_date('2014-01-15T08:00:00');
    $ny->set_time_zone('America/New_York');
    is($ny->xmlschema, '2014-01-15T08:00:00-05:00', 'named zone in winter');
    my $summer = App::Dapper::Utils::parse_date('2014-07-15T08:00:00');
    $summer->set_time_zone('America/New_York');
    is($summer->xmlschema, '2014-07-15T08:00:00-04:00', 'daylight saving time');
    my $conv = App::Dapper::Utils::parse_date('2014-07-15T12:00:00Z');
    $conv->set_time_zone('Asia/Kolkata');
    is($conv->xmlschema, '2014-07-15T17:30:00+05:30', 'converted between zones');
    ok(App::Dapper::Date->can('xmlschema'), 'method exists');
    ok(App::Dapper::Date->isa('DateTime'), 'subclass of DateTime');
};

subtest 'get_modified_time' => sub {
    in_tmp();
    spew('f.txt', 'x');
    utime 1_000_000_000, 1_000_000_000, 'f.txt' or die;
    {
        local $ENV{TZ} = 'UTC';
        POSIX::tzset();
        is(App::Dapper::Utils::get_modified_time('f.txt'), '2001-09-09T01:46:40', 'mtime in UTC');
    }
    {
        local $ENV{TZ} = 'Asia/Tokyo';
        POSIX::tzset();
        is(App::Dapper::Utils::get_modified_time('f.txt'), '2001-09-09T10:46:40', 'mtime in local time');
    }
    POSIX::tzset();
    like(App::Dapper::Utils::get_modified_time('f.txt'), qr/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$/,
        'always a format parse_date understands');
    isa_ok(App::Dapper::Utils::parse_date(App::Dapper::Utils::get_modified_time('f.txt')), 'DateTime');
};

subtest 'slugify' => sub {
    my %cases = (
        'Hello World'            => 'hello-world',
        'Café: A Story'          => 'cafe-a-story',
        '  padded   title  '     => 'padded-title',
        'Tabs	and
newlines'                        => 'tabs-and-newlines',
        'a--b---c'               => 'a-b-c',
        'a - b'                  => 'a-b',
        'under_score_kept'       => 'under_score_kept',
        'UPPER lower MiXeD'      => 'upper-lower-mixed',
        'Version 1.2.3'          => 'version-123',
        q{It's "quoted" (really)} => 'its-quoted-really',
        'Ünïcödé Naïve Résumé'   => 'unicode-naive-resume',
        'Straße'                 => 'strae',
        'ﬁne ligature'           => 'fine-ligature',
        '日本語のタイトル'        => '',
        'Mixed 日本 words'       => 'mixed-words',
        'emoji 😀 here'          => 'emoji-here',
        '100% & more!'           => '100-more',
        '---'                    => '-',
        '-leading and trailing-' => '-leading-and-trailing-',
        'C++ & C#'               => 'c-c',
        '2014'                   => '2014',
        'ÀÉÎÕÜ'                  => 'aeiou',
        'Ñandú'                  => 'nandu',
        'Øresund'                => 'resund',
        ''                       => '',
        '!!!'                    => '',
        'a/b\\c'                 => 'abc',
    );
    for my $in (sort keys %cases) {
        is(App::Dapper::Utils::slugify($in), $cases{$in}, "slugify('$in')");
    }
    is(App::Dapper::Utils::slugify(undef), undef, 'undef in, undef out');
    is_deeply([App::Dapper::Utils::slugify(undef)], [], 'undef returns an empty list in list context');
    is(App::Dapper::Utils::slugify(42), '42', 'numbers');
};

subtest 'filter_extension and filter_stem' => sub {
    my @cases = (
        # name                 extension   stem
        ['index.md',           '.md',      'index'],
        ['a.b.md',             '.md',      'a.b'],
        ['dir/page.html',      '.html',    'dir/page'],
        ['dir.d/file',         undef,      'dir.d/file'],
        ['noext',              undef,      'noext'],
        ['./a.md',             '.md',      'a'],
        ['a//b/./c.txt',       '.txt',     'a/b/c'],
        ['dir/',               undef,      'dir'],
        ['x.',                 undef,      'x.'],
        ['archive.tar.gz',     '.gz',      'archive.tar'],
        ['_source/Café.md',    '.md',      '_source/Café'],
        ['a b/c d.e f',        '.e f',     'a b/c d'],
        ['/abs/path/file.yml', '.yml',     '/abs/path/file'],
        ['UPPER.MD',           '.MD',      'UPPER'],
    );
    for my $case (@cases) {
        my ($name, $ext, $stem) = @$case;
        is(App::Dapper::Utils::filter_extension($name), $ext, "extension of '$name'");
        is(App::Dapper::Utils::filter_stem($name), $stem, "stem of '$name'");
    }
    # A dot file is all extension (walk skips dot files, so pages never see this)
    is(App::Dapper::Utils::filter_extension('dir/.hidden'), '.hidden', 'dot file extension');
    is(App::Dapper::Utils::filter_stem('dir/.hidden'), 'dir/', 'dot file stem');
};

subtest 'create_file' => sub {
    in_tmp();
    my $out = '';
    {
        open(my $fh, '>', \$out) or die;
        my $old = select $fh;
        App::Dapper::Utils::create_file('./sub//new.txt', "content\n");
        select $old;
    }
    is($out, "Creating sub/new.txt\n", 'prints the canonical name');
    is(slurp('sub/new.txt'), "content\n", 'file written with its parent directory');

    $out = '';
    {
        open(my $fh, '>', \$out) or die;
        my $old = select $fh;
        local $App::Dapper::Utils::QUIET = 1;
        App::Dapper::Utils::create_file('quiet.txt', "q");
        select $old;
    }
    is($out, '', 'nothing printed with $QUIET');
    is(slurp('quiet.txt'), 'q', 'file still written');

    local $App::Dapper::Utils::QUIET = 1;
    dies_like(sub { App::Dapper::Utils::create_file('./sub/new.txt', 'again') },
        qr/^error: "sub\/new\.txt" already exists$/, 'an existing file is never overwritten');
    is(slurp('sub/new.txt'), "content\n", 'and stays as it was');
    mkdir 'somedir';
    dies_like(sub { App::Dapper::Utils::create_file('somedir', 'x') },
        qr/^error: "somedir" already exists$/, 'nor a directory');
    dies_like(sub { App::Dapper::Utils::create_file('only-one-arg') },
        qr/^Invalid number of arguments to create_file/, 'one argument');
    dies_like(sub { App::Dapper::Utils::create_file('a', 'b', 'c') },
        qr/^Invalid number of arguments to create_file/, 'three arguments');
    ok(!-e 'only-one-arg' && !-e 'a', 'nothing written on bad arguments');
};

subtest 'create_dir' => sub {
    in_tmp();
    App::Dapper::Utils::create_dir('x/y/z/');
    ok(-d 'x/y/z', 'nested directories created');
    is(App::Dapper::Utils::create_dir('x/y'), undef, 'an existing directory is fine');
    ok(-d 'x/y/z', 'and is left alone');
    App::Dapper::Utils::create_dir('Ünï cödé');
    ok(-d 'Ünï cödé' || -d App::Dapper::Utils::name_bytes('Ünï cödé'), 'Unicode name with a space');

    dies_like(sub { App::Dapper::Utils::create_dir() }, qr/^Invalid number of arguments to create_dir/, 'no arguments');
    dies_like(sub { App::Dapper::Utils::create_dir('a', 'b') }, qr/^Invalid number of arguments to create_dir/, 'two arguments');

    spew('afile', 'x');
    eval { App::Dapper::Utils::create_dir('afile/sub') };
    ok($@, 'a file in the way is an error');
    like($@, qr/^error: could not create directory "afile\/sub"/, 'with a clear message');
};

subtest 'name_chars and name_bytes' => sub {
    is(App::Dapper::Utils::name_chars(undef), undef, 'name_chars(undef)');
    is(App::Dapper::Utils::name_bytes(undef), undef, 'name_bytes(undef)');

    my $chars = App::Dapper::Utils::name_chars("caf\xC3\xA9");
    is($chars, 'café', 'UTF-8 bytes decoded');
    is(length $chars, 4, 'four characters');

    my $invalid = App::Dapper::Utils::name_chars("\xFF\xFEab");
    is($invalid, "\xFF\xFEab", 'invalid UTF-8 returned as it is');
    is(length $invalid, 4, 'same length');

    is(App::Dapper::Utils::name_chars('plain'), 'plain', 'ASCII unchanged');

    my $bytes = App::Dapper::Utils::name_bytes('café');
    is($bytes, "caf\xC3\xA9", 'characters encoded');
    is(length $bytes, 5, 'five bytes');
    ok(!utf8::is_utf8($bytes), 'no UTF-8 flag');
    is(App::Dapper::Utils::name_bytes("caf\xC3\xA9"), "caf\xC3\xA9", 'bytes stay bytes');
    is(App::Dapper::Utils::name_bytes('plain'), 'plain', 'ASCII unchanged');
    is(App::Dapper::Utils::name_chars(App::Dapper::Utils::name_bytes('日本')), '日本', 'round trip');
};

subtest 'read_dir' => sub {
    in_tmp();
    spew($_, 'x') for ('b.txt', 'a.txt', 'C.txt', '.hidden', 'café.md');
    mkdir 'zdir';
    my @names = App::Dapper::Utils::read_dir('.');
    is_deeply(\@names, ['.hidden', 'C.txt', 'a.txt', 'b.txt', 'café.md', 'zdir'],
        'sorted, includes dot files and directories, no . or ..');
    ok(utf8::is_utf8($names[4]) || $names[4] eq 'café.md', 'names are characters');
    is($names[4], 'café.md', 'accented name decoded');

    mkdir 'empty';
    is_deeply([App::Dapper::Utils::read_dir('empty')], [], 'empty directory');
    dies_like(sub { App::Dapper::Utils::read_dir('missing') },
        qr/^error: could not open "missing": /, 'missing directory');
};

subtest 'copy_recursive' => sub {
    in_tmp();
    my $binary = join('', map { chr } 0 .. 255);
    spew('src/one.txt', "one\n");
    spew('src/sub/two.txt', "two\n");
    spew('src/sub/deeper/three.bin', $binary, ':raw');
    spew('src/space name/quote\'s.txt', "q\n");
    spew('src/Zoë/café.txt', "accent\n");
    mkdir 'src/emptydir';
    spew('src/skipme/inside.txt', "skip\n");

    my @copied = App::Dapper::Utils::copy_recursive('src', 'dst', 'src/skipme');
    is_deeply([sort @copied],
        [sort map { File::Spec->catfile('dst', $_) }
            ('one.txt', 'sub/two.txt', 'sub/deeper/three.bin', "space name/quote's.txt", 'Zoë/café.txt')],
        'returns every file written');
    is(slurp('dst/one.txt'), "one\n", 'top-level file');
    is(slurp('dst/sub/two.txt'), "two\n", 'nested file');
    is(slurp('dst/sub/deeper/three.bin', ':raw'), $binary, 'binary file byte for byte');
    is(slurp("dst/space name/quote's.txt"), "q\n", 'odd names');
    is(slurp(App::Dapper::Utils::name_bytes('dst/Zoë/café.txt')), "accent\n", 'Unicode names');
    ok(-d 'dst/emptydir', 'empty directories are created');
    ok(!-e 'dst/skipme', 'skipped directories are not copied');

    my @single = App::Dapper::Utils::copy_recursive('src/one.txt', 'elsewhere/deep/one-copy.txt');
    is_deeply(\@single, ['elsewhere/deep/one-copy.txt'], 'a single file returns its destination');
    is(slurp('elsewhere/deep/one-copy.txt'), "one\n", 'with parent directories created');

    my @none = App::Dapper::Utils::copy_recursive('src/emptydir', 'emptycopy');
    is_deeply(\@none, [], 'an empty directory copies no files');
    ok(-d 'emptycopy', 'but is created');

    my @skip_undef = App::Dapper::Utils::copy_recursive('src/sub', 'sub2', 'does-not-exist');
    is(scalar @skip_undef, 2, 'skip paths that do not exist are ignored');

    dies_like(sub { App::Dapper::Utils::copy_recursive('nope', 'x') },
        qr/^error: "nope" is not a file or directory$/, 'missing source');

    SKIP: {
        skip 'file permissions are not enforced for root', 1 if $> == 0;
        spew('locked.txt', 'secret');
        chmod 0000, 'locked.txt';
        dies_like(sub { App::Dapper::Utils::copy_recursive('locked.txt', 'unlocked.txt') },
            qr/^error: could not copy "locked\.txt" to "unlocked\.txt": /, 'unreadable file');
        chmod 0644, 'locked.txt';
    }
};

done_testing();
