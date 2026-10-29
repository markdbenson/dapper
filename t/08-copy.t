use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

subtest 'top-level files and directories are copied without a shell' => sub {
    make_site({
        '_source/index.md'          => "---\ntitle: x\n---\nHi\n",
        'my file.txt'               => "spaces\n",
        'quote\'s & $(touch pwned)' => "metacharacters\n",
        'css/site.css'              => "body {}\n",
        'css/deep/more.css'         => "p {}\n",
        'notes/.keep'               => "",
    });
    quiet_build();
    is(slurp('_output/my file.txt'), "spaces\n", 'name with spaces copied');
    is(slurp('_output/quote\'s & $(touch pwned)'), "metacharacters\n", 'shell metacharacters are just a name');
    ok(!-e 'pwned', 'no shell command ran');
    is(slurp('_output/css/deep/more.css'), "p {}\n", 'directories copied recursively');
};

subtest 'ignore patterns' => sub {
    make_site({
        '_config.yml'      => "---\nname: x\nignore:\n  - ^\\.\n  - ^_\n  - ^README\\.md\$\n",
        '_source/index.md' => "---\ntitle: x\n---\nHi\n",
        'README.md'        => "readme\n",
        '.hidden'          => "secret\n",
        '_drafts/a.md'     => "draft\n",
        'kept.txt'         => "kept\n",
    });
    quiet_build();
    ok(-f '_output/kept.txt', 'unmatched file copied');
    ok(!-e '_output/README.md', 'ignored by name');
    ok(!-e '_output/.hidden', 'dot file ignored');
    ok(!-e '_output/_drafts', 'underscore directory ignored');
};

subtest 'output inside a copied directory is not copied into itself' => sub {
    make_site({
        '_config.yml'      => "---\nname: x\noutput: build/site\n",
        '_source/index.md' => "---\ntitle: x\n---\nHi\n",
        'build/notes.txt'  => "notes\n",
    });
    quiet_build();
    ok(-f 'build/site/index.html', 'page written');
    ok(-f 'build/site/build/notes.txt', 'sibling content copied');
    ok(!-e 'build/site/build/site', 'output not copied into itself');
};

done_testing();
