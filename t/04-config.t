use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

# GitHub issue #8: directories in the config file must be honoured.

subtest 'config file directories are used' => sub {
    make_site({
        '_config.yml'        => "---\nname: Test\nsource: src\noutput: public\nlayout: layouts\n",
        'src/index.md'       => "---\ntitle: Home\n---\nHome page\n",
        'src/blog/post.md'   => "---\ntitle: A Post\ncategories: blog\ndate: 2015-08-02T10:00:00\n---\nPost\n",
        'layouts/index.html' => "[% page.content %]",
    }, bare => 1);

    my $d = quiet_build();
    is($d->{source}, 'src', 'source comes from the config file');
    is($d->{output}, 'public', 'output comes from the config file');
    is($d->{layout}, 'layouts', 'layout comes from the config file');
    ok(-f 'public/index.html', 'plain page is written to the configured output');
    ok(-f 'public/blog/2015/08/a-post/index.html', 'categorized page is written to the configured output');
    ok(!-e '_output', 'the default output directory is not created');
    ok(!-e 'public/public', 'the output directory is not copied into itself');
    ok(!-e 'public/src' && !-e 'public/layouts', 'source and layout directories are not copied');
};

subtest 'explicit directories override the config file' => sub {
    make_site({
        '_config.yml'      => "---\nname: Test\noutput: public\n",
        '_source/index.md' => "---\ntitle: Home\n---\nHome\n",
    });

    my $d = quiet_build(undef, 'elsewhere');
    is($d->{output}, 'elsewhere', 'explicit output wins');
    ok(-f 'elsewhere/index.html', 'page written to the explicit output');
    ok(!-e 'public', 'configured output is not used');
};

subtest 'trailing slashes are normalised' => sub {
    make_site({
        '_config.yml'      => "---\nname: Test\noutput: public/\n",
        '_source/index.md' => "---\ntitle: Home\n---\nHome\n",
    });

    my $d = quiet_build();
    is($d->{output}, 'public', 'trailing slash removed');
    is($d->{site}->{output}, 'public', 'site.output matches');
};

subtest 'missing or broken config' => sub {
    make_site({ '_source/index.md' => "---\ntitle: x\n---\n" }, bare => 1);
    eval { quiet_build() };
    like($@, qr/could not find the project file "_config.yml"/, 'missing config is a clear error');

    make_site({ '_config.yml' => "---\nname: [unclosed\n" });
    eval { quiet_build() };
    like($@, qr/could not parse "_config.yml"/, 'invalid YAML names the file');

    make_site({ '_config.yml' => "", '_source/index.md' => "---\ntitle: x\n---\nx\n" });
    eval { quiet_build() };
    is($@, '', 'an empty config file is allowed');
};

subtest 'site variables from the config file reach templates' => sub {
    make_site({
        '_config.yml'        => "---\nname: Config Name\nauthor: Someone\n",
        '_source/index.md'   => "---\ntitle: Home\n---\nHome\n",
        '_layout/index.html' => "[% site.name %] by [% site.author %]",
    });
    quiet_build();
    is(slurp('_output/index.html'), 'Config Name by Someone', 'site.* rendered');
};

subtest 'a Dapper object can be built more than once' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nHome\n" });
    my $d = quiet_build();
    $d->build();
    is(scalar @{ $d->{site}->{pages} }, 1, 'pages are not duplicated by a second build');
};

done_testing();
