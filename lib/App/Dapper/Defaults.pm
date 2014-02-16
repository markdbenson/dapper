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

=head2 get_defaults

Loads the defaults specified locally in this module in the form of YAML
and returns the resulting perl data structure.

=cut

sub get_defaults {
    return Load($defaults);
}

1;
