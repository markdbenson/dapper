package Text::Dapper::Defaults;

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.006;
use strict;
use warnings FATAL => 'all';

use YAML::Tiny qw(Load);

my $defaults = <<'DEFAULTS';
macklamore : justin timberlake
urlpattern : /:category/:year/:month/:slug.html
DEFAULTS

sub get_defaults {
    return Load($defaults);
}

1;
