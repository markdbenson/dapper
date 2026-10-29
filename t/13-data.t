use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

subtest 'YAML and JSON data files are available as site.data' => sub {
    make_site({
        '_data/authors.yml'    => "- name: Zoë\n  role: editor\n- name: Sam\n  role: writer\n",
        '_data/settings.json'  => qq({"colour": "blue", "count": 3}),
        '_data/menus/main.yml' => "- { label: Home, url: / }\n",
        '_data/notes.txt'      => "ignored\n",
        '_source/index.md'     => "---\ntitle: x\n---\nx\n",
        '_layout/index.html'   => "[% FOR a IN site.data.authors %][% a.name %]:[% a.role %];[% END %]"
                                . "|[% site.data.settings.colour %][% site.data.settings.count %]"
                                . "|[% site.data.menus.main.0.label %]",
    });
    my $d = quiet_build();
    is(slurp('_output/index.html'), 'Zoë:editor;Sam:writer;|blue3|Home', 'data rendered');
    ok(!exists $d->{site}->{data}->{notes}, 'other file types are ignored');
    ok(!-e '_output/_data', 'the data directory is not copied');
};

subtest 'a custom data directory' => sub {
    make_site({
        '_config.yml'        => "---\nname: x\ndata_dir: data\n",
        'data/site.yml'      => "tagline: Hello\n",
        '_source/index.md'   => "---\ntitle: x\n---\nx\n",
        '_layout/index.html' => "[% site.data.site.tagline %]",
    });
    quiet_build();
    is(slurp('_output/index.html'), 'Hello', 'data_dir setting used');
    ok(!-e '_output/data', 'the custom data directory is not copied');
};

subtest 'a broken data file names the file' => sub {
    make_site({ '_data/bad.json' => '{"x": ', '_source/index.md' => "---\ntitle: x\n---\nx\n" });
    eval { quiet_build() };
    like($@, qr{could not parse the data file "_data/bad.json"}, 'error names the file');
};

done_testing();
