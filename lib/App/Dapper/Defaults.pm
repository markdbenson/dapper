package App::Dapper::Defaults;

use utf8;
use open ':std', ':encoding(UTF-8)';
use 5.006;
use strict;
use warnings FATAL => 'all';

use YAML::Tiny qw(Load);

my $defaults = <<'DEFAULTS';
urlpattern : /:category/:year/:month/:slug/
DEFAULTS

sub get_defaults {
    return Load($defaults);
}

1;
