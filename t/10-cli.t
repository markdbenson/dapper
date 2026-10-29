use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use Cwd qw(abs_path);
use File::Spec;

my $dapper = abs_path(File::Spec->catfile('bin', 'dapper'));
my $lib = abs_path('lib');

sub run {
    my @args = @_;
    my $command = join(' ', map { "\"$_\"" } $^X, "-I$lib", $dapper, @args) . ' 2>&1';
    my $output = `$command`;
    return ($? >> 8, $output);
}

my ($status, $output) = run('-v');
is($status, 0, '-v exits 0');
like($output, qr/Dapper version \Q$App::Dapper::VERSION\E/, '-v prints the version');

($status, $output) = run('--help');
is($status, 0, '--help exits 0');
like($output, qr/Usage:/, '--help prints usage');

($status, $output) = run('frobnicate');
is($status, 2, 'unknown command exits 2');
like($output, qr/unknown command "frobnicate"/, 'unknown command is named');

($status, $output) = run('--bogus');
is($status, 2, 'unknown option exits 2');

make_site({}, bare => 1);
($status, $output) = run('-q', 'init');
is($status, 0, 'init exits 0');

($status, $output) = run('-q', 'build');
is($status, 0, 'build exits 0');
is($output, '', '-q suppresses progress messages');
ok(-f '_output/index.html', 'build wrote the site');

($status, $output) = run('-q', '-o', 'other', 'build');
ok(-f 'other/index.html', '-o chooses the output directory');

($status, $output) = run('--output=third', '--quiet', 'build');
ok(-f 'third/index.html', 'long options work');

unlink '_config.yml';
($status, $output) = run('build');
is($status, 1, 'a failed build exits 1');
like($output, qr/could not find the project file/, 'and says why');

done_testing();
