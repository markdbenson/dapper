use 5.010;
use strict;
use warnings;
use Test::More;

# The dapper command when things go wrong: exit statuses, and the exact
# messages on standard error.

use lib 't/lib';
use DapperTest;
use App::Dapper;
use Cwd qw(abs_path);
use File::Spec;
use File::Temp qw(tempdir);

my $dapper = abs_path(File::Spec->catfile('bin', 'dapper'));
my $lib = abs_path('lib');
my $io = tempdir(CLEANUP => 1);

sub sh_quote {
    my ($s) = @_;
    $s =~ s/'/'\\''/g;
    return "'$s'";
}

sub dapper {
    my @args = @_;
    my $cmd = join(' ', map { sh_quote($_) } $^X, "-I$lib", $dapper, @args)
        . ' >' . sh_quote("$io/out") . ' 2>' . sh_quote("$io/err") . ' <' . File::Spec->devnull;
    system($cmd);
    my $status = $? >> 8;
    my ($out, $err) = (slurp("$io/out"), slurp("$io/err"));
    return ($status, defined $out ? $out : '', defined $err ? $err : '');
}

subtest 'unknown command' => sub {
    for my $command (qw(frobnicate Build INIT serve-me)) {
        my ($status, $out, $err) = dapper($command);
        is($status, 2, "$command exits 2");
        like($err, qr/\Aerror: unknown command "\Q$command\E"\n\nUsage:\n/, "$command is named, then the usage");
        like($err, qr/^Options:$/m, "$command: the options follow");
        is($out, '', "$command: nothing on standard output");
    }
};

subtest 'bad options' => sub {
    my @cases = (
        [ ['--bogus'],           "Unknown option: bogus\n" ],
        [ ['-V'],                "Unknown option: V\n" ],
        [ ['-Q', 'build'],       "Unknown option: Q\n" ],
        [ ['-p', 'abc', 'serve'], qr/Value "abc" invalid for option p \((?:\w+ )?number expected\)\n/ ],
        [ ['--port=8o', 'serve'], qr/Value "8o" invalid for option port \((?:\w+ )?number expected\)\n/ ],
        [ ['-t'],                "Option t requires an argument\n" ],
        [ ['--template'],        "Option template requires an argument\n" ],
        [ ['--to'],              "Option to requires an argument\n" ],
        [ ['-C'],                "Option C requires an argument\n" ],
        [ ['--json=1', 'check'], "Option json does not take an argument\n" ],
        [ ['--drafts=yes', 'build'], "Option drafts does not take an argument\n" ],
        [ ['--dry-run=1', 'deploy'], "Option dry-run does not take an argument\n" ],
    );
    for my $case (@cases) {
        my ($args, $message) = @$case;
        my ($status, $out, $err) = dapper(@$args);
        is($status, 2, "@$args exits 2");
        my $pattern = ref $message ? $message : qr/\Q$message\E/;
        like($err, qr/\A${pattern}Usage:\n/, "@$args: the message, then the usage");
        is($out, '', "@$args: nothing on standard output");
    }
};

subtest '-C' => sub {
    make_site({ 'afile' => "x\n" }, bare => 1);
    my ($status, $out, $err) = dapper('-C', 'no-such-dir', 'build');
    is($status, 1, 'a missing directory exits 1');
    like($err, qr/\Aerror: could not change to "no-such-dir": .+\n\z/, 'and says so');

    ($status, $out, $err) = dapper('-C', 'afile', 'build');
    is($status, 1, 'a file exits 1');
    like($err, qr/\Aerror: could not change to "afile": .+\n\z/, 'and says so');

    ($status, $out, $err) = dapper('-C', 'no-such-dir', '-v');
    is($status, 0, '-v is answered before changing directory');
};

subtest 'init refuses to overwrite' => sub {
    make_site({ '_config.yml' => "---\nname: Mine\n" }, bare => 1);
    my ($status, $out, $err) = dapper('init');
    is($status, 1, 'exits 1');
    is($err, "error: refusing to initialize, these files already exist: _config.yml\n", 'names the file that is there');
    is($out, '', 'prints nothing else');
    is(slurp('_config.yml'), "---\nname: Mine\n", 'the project file is untouched');
    ok(!-e '_source' && !-e '_layout' && !-e '.gitignore' && !-e 'AGENTS.md', 'nothing else is written');

    make_site({}, bare => 1);
    is((dapper('-q', 'init'))[0], 0, 'a first init works');
    ($status, $out, $err) = dapper('init');
    is($status, 1, 'a second exits 1');
    is($err, "error: refusing to initialize, these files already exist: _config.yml _layout/index.html _source/index.md\n", 'and lists every file, sorted');

    ($status, $out, $err) = dapper('-t', 'blog', 'init');
    is($status, 1, 'another template over it exits 1');
    is($err, "error: refusing to initialize, these files already exist: _config.yml _layout/index.html\n", 'listing the files the two share');
    ok(!-e '_source/blog', 'and writes none of the blog');
};

subtest 'init with a template that is not there' => sub {
    make_site({}, bare => 1);
    my ($status, $out, $err) = dapper('-t', '/no/such/theme', 'init');
    is($status, 1, 'exits 1');
    is($err, "error: there is no template called \"/no/such/theme\"; use one of: blog, business, default, docs, portfolio, a directory, or a git URL\n", 'says so');

    my $empty = tempdir(CLEANUP => 1);
    ($status, $out, $err) = dapper('-t', $empty, 'init');
    is($status, 1, 'an empty directory exits 1');
    is($err, "error: the template $empty has no files\n", 'and says it has no files');
};

subtest 'the project file' => sub {
    make_site({ '_source/index.md' => "---\ntitle: x\n---\nx\n" }, bare => 1);
    my ($status, $out, $err) = dapper('build');
    is($status, 1, 'build without a project file exits 1');
    is($err, "error: could not find the project file \"_config.yml\". Run \"dapper init\" to create a new project.\n", 'and says to run dapper init');
    is($out, '', 'nothing on standard output');

    ($status, $out, $err) = dapper('check');
    is($status, 1, 'check without a project file exits 1');
    is($out, "error: _config.yml: could not find the project file \"_config.yml\". Run \"dapper init\" to create a new project.\nChecked 0 pages: 1 error, 0 warnings.\n", 'reports it as an error in the report');
    is($err, '', 'on standard output');

    ($status, $out, $err) = dapper('-c', 'other.yml', 'build');
    is($err, "error: could not find the project file \"other.yml\". Run \"dapper init\" to create a new project.\n", '-c names the file it looked for');

    spew('_config.yml', "name: [\n");
    ($status, $out, $err) = dapper('build');
    is($status, 1, 'a project file that is not YAML exits 1');
    like($err, qr/\Aerror: could not parse "_config\.yml": /, 'and says so');

    spew('_config.yml', "- a\n- b\n");
    ($status, $out, $err) = dapper('build');
    is($status, 1, 'a list exits 1');
    is($err, "error: \"_config.yml\" must contain key: value pairs\n", 'and says what it must be');

    for my $key (qw(source output layout)) {
        spew('_config.yml', "---\nname: x\n$key: ''\n");
        ($status, $out, $err) = dapper('build');
        is($status, 1, "an empty $key exits 1");
        is($err, "error: \"$key\" must be defined in project file\n", "and names $key");
    }

    spew('_config.yml', '');
    spew('_layout/index.html', '[% page.content %]');
    ($status, $out, $err) = dapper('-q', 'build');
    is($status, 0, 'an empty project file is fine');
};

subtest 'a build that fails' => sub {
    make_site({ '_source/index.md' => "---\ntitle: x\n---\nx\n", '_layout/index.html' => '[% IF %]' });
    my ($status, $out, $err) = dapper('-q', 'build');
    is($status, 1, 'a template error exits 1');
    like($err, qr/\Aerror: could not process _source\/index\.md with layout index: parse error - input text line 1 char \d+: Missing END directive\n\z/, 'and names the page, layout and problem');
    is($out, '', 'nothing on standard output with -q');

    ($status, $out, $err) = dapper('check');
    is($status, 1, 'check exits 1');
    like($out, qr/^error: _source\/index\.md: could not process _source\/index\.md with layout index: parse error/m, 'and reports it');
    is($err, '', 'on standard output');
};

subtest 'deploy' => sub {
    make_site({ '_source/index.md' => "---\ntitle: x\n---\nx\n" });
    my ($status, $out, $err) = dapper('deploy');
    is($status, 1, 'no deploy settings exits 1');
    is($err, "error: there is nowhere to deploy to; add deploy settings to _config.yml (see \"Deploying with dapper deploy\" in the README)\n", 'and says how to add them');

    spew('_config.yml', "---\nname: x\ndeploy:\n  ftp: host\n");
    ($status, $out, $err) = dapper('deploy');
    is($status, 1, 'an unknown target exits 1');
    is($err, "error: unknown deploy target \"ftp\" in _config.yml; use s3, github_pages, command\n", 'and lists the targets');

    spew('_config.yml', "---\nname: x\ndeploy:\n  s3:\n    bucket: a\n  command: 'true'\n");
    ($status, $out, $err) = dapper('deploy');
    is($status, 1, 'several targets exit 1');
    is($err, "error: _config.yml has several deploy targets (s3, command); say which: dapper deploy <target>\n", 'and asks which');

    ($status, $out, $err) = dapper('deploy', 'github_pages');
    is($status, 1, 'a target without settings exits 1');
    is($err, "error: there are no \"github_pages\" deploy settings in _config.yml\n", 'and says so');

    spew('_config.yml', "---\nname: x\ndeploy:\n  command: 'sh -c \"exit 3\"'\n");
    ($status, $out, $err) = dapper('-q', 'deploy', '--no-build');
    is($status, 1, '--no-build without an output directory exits 1');
    is($err, "error: the output directory \"_output\" doesn't exist; build the site first\n", 'and says to build first');

    ($status, $out, $err) = dapper('-q', 'deploy');
    is($status, 1, 'a failing command exits 1');
    is($err, "error: the deploy command failed (exit status 3)\n", 'with its exit status');

    spew('_config.yml', "---\nname: x\ndeploy:\n  command: no-such-command-for-dapper\n");
    ($status, $out, $err) = dapper('-q', 'deploy');
    is($status, 1, 'a command that cannot be run exits 1');
    unlike($err, qr/exit status \d{5,}/, 'without a nonsense exit status');
};

subtest 'import' => sub {
    make_site({ '_source/index.md' => "---\ntitle: x\n---\nx\n", 'notes.txt' => "x\n" });
    my ($status, $out, $err) = dapper('import');
    is($status, 1, 'nothing to import exits 1');
    is($err, "error: say what to import from: dapper import <hugo|jekyll|medium|wordpress> <file or directory>\n", 'and says how');

    ($status, $out, $err) = dapper('import', 'jekyll');
    is($err, "error: say what to import from: dapper import <hugo|jekyll|medium|wordpress> <file or directory>\n", 'a kind without a path too');

    ($status, $out, $err) = dapper('import', 'blogger', '.');
    is($status, 1, 'an unknown kind exits 1');
    is($err, "error: Dapper can't import from \"blogger\"; it can import from hugo, jekyll, medium, wordpress\n", 'and lists the kinds');

    ($status, $out, $err) = dapper('import', 'Blogger', '.');
    like($err, qr/can't import from "blogger"/, 'the kind is lowercased in the message');

    ($status, $out, $err) = dapper('import', 'jekyll', 'missing');
    is($status, 1, 'a missing path exits 1');
    is($err, "error: \"missing\" doesn't exist\n", 'and says so');

    ($status, $out, $err) = dapper('import', 'wordpress', '.');
    is($err, "error: give the WordPress export file (Tools, Export in WordPress), not a directory\n", 'WordPress needs a file');
    ($status, $out, $err) = dapper('import', 'wordpress', 'notes.txt');
    is($err, "error: notes.txt is not a WordPress export file\n", 'and an export file');
    ($status, $out, $err) = dapper('import', 'jekyll', 'notes.txt');
    is($err, "error: give the Jekyll site's directory\n", 'Jekyll needs a directory');
    ($status, $out, $err) = dapper('import', 'hugo', 'notes.txt');
    is($err, "error: give the Hugo site's directory\n", 'Hugo needs a directory');
    ($status, $out, $err) = dapper('import', 'hugo', '_source');
    is($err, "error: _source has no content directory, so it doesn't look like a Hugo site\n", 'with a content directory');
    ($status, $out, $err) = dapper('import', 'medium', 'notes.txt');
    is($err, "error: give Medium's export (the .zip file, or the folder it unzips to)\n", 'Medium needs its export');

    unlink '_config.yml';
    my $jekyll = tempdir(CLEANUP => 1);
    ($status, $out, $err) = dapper('import', 'jekyll', $jekyll);
    is($status, 1, 'without a project file exits 1');
    like($err, qr/could not find the project file/, 'and says so');
};

done_testing();
