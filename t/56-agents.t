use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;
binmode(Test::More->builder->$_, q(:encoding(UTF-8))) for qw(output failure_output todo_output);

# App::Dapper::Agents: the guide in AGENTS.md (every section and every kind
# of schema rule), the markers that keep people's notes, and CLAUDE.md.

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Agents;

my $BEGIN = '<!-- dapper:begin (this part is written by "dapper agents"; edit outside it) -->';
my $END   = '<!-- dapper:end -->';

sub guide { return App::Dapper::Agents::guide(App::Dapper->new(@_)) }

sub update {
    my ($notes) = @_;
    my $d = App::Dapper->new();
    $d->{quiet} = 1;
    return App::Dapper::Agents::update($d, $notes);
}

# The text of a section of the guide, from its heading to the next
sub section {
    my ($text, $heading) = @_;
    return $text =~ /^## \Q$heading\E\n\n(.*?)(?=^## |\z)/ms ? $1 : undef;
}

subtest 'the guide for a small site' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });
    my $text = guide();
    like($text, qr/\A# Working on Test Site\n\nThis is a static website built with \[Dapper\]\(https:\/\/github\.com\/markdbenson\/dapper\)\.\n/, 'opens with the site name and what Dapper is');
    like($text, qr/^HTML in `_output\/`\. Edit the source files, never the output\.$/m, 'names the output directory');
    is_deeply([ $text =~ /^## (.+)$/mg ], ['Commands', 'Where things are', 'Layouts', 'Rules'], 'the sections, in order');

    my $commands = section($text, 'Commands');
    like($commands, qr/^- `dapper serve`: build, watch for changes and serve the site at http:\/\/localhost:8000$/m, 'serve');
    like($commands, qr/^- `dapper check --json`: find problems/m, 'check');
    like($commands, qr/\*\*Run it after every change and fix\n  every error it reports\.\*\*/, 'run check after every change');
    like($commands, qr/^- `dapper build`: build the site into `_output\/`$/m, 'build');
    like($commands, qr/^- `dapper agents`: update this file after adding layouts, schemas or settings$/m, 'agents');
    unlike($commands, qr/dapper deploy/, 'no deploy without deploy settings');

    my $where = section($text, 'Where things are');
    like($where, qr/^- `_source\/`: the pages\./m, 'the source directory');
    like($where, qr/^- `_layout\/`: the layouts, which are templates/m, 'the layout directory');
    like($where, qr/^- `_data\/`: data files \(YAML or JSON\), available in templates as `site\.data`\.$/m, 'the data directory');
    like($where, qr/^- `_config\.yml`: the site's settings\.$/m, 'the project file');
    like($where, qr/except names starting with `\.` or `_`\.$/m, 'what is copied');

    is(section($text, 'Layouts'), "- `index`\n\nA page uses the layout named by its `layout` setting, or `index` if it has none.\n\n", 'the layout, without a description');

    my $rules = section($text, 'Rules');
    like($rules, qr/\A- \*\*Content is not a template\.\*\*/, 'rules start with templates in content');
    like($rules, qr/^- \*\*Dates\*\* are written like `2026-01-01T09:00:00` \(or `2026-01-01`\)\.$/m, 'dates');
    like($rules, qr/^- \*\*Images\*\* need meaningful alt text/m, 'alt text');
    like($rules, qr/^- \*\*Components\*\* add what Markdown can't/m, 'components');
    like($rules, qr/^- \*\*Drafts:\*\* `draft: true` keeps a page off the site/m, 'drafts');
    like($text, qr/^- Don't edit or commit the output directory or `\.dapper\/`\.\n\z/m, 'and the guide ends with the last rule');
    unlike($text, qr/Front matter rules|Categories and tags/, 'no schema or category sections when there are none');
};

subtest 'the guide with everything' => sub {
    make_site({
        '_config.yml'          => "---\nname: Everything\nsource: pages\nlayout: templates\noutput: public\ndata_dir: info\ndeploy:\n  command: 'true'\n",
        'pages/index.md'       => "---\ntitle: Home\ncategories: [news, blog]\ntags: [zebra, apple]\n---\nx\n",
        'pages/_schema.yml'    => "required: [title]\nadditional: false\nfields:\n  title:\n    type: string\n    min_length: 2\n    max_length: 60\n  rating:\n    type: integer\n    min: 1\n    max: 5\n  slug:\n    type: string\n    pattern: '^[a-z-]+\$'\n  categories:\n    type: list\n    values: [news, blog]\n  tags:\n    type: list\n",
        'pages/docs/_schema.yml' => "fields:\n  order:\n    type: number\n",
        'templates/index.html' => "---\ndescription: The wrapper\n---\n[% page.content %]",
        'templates/post.html'  => "---\ndescription: [not, text]\n---\n[% page.content %]",
        'templates/plain.html' => "[% page.content %]",
        'templates/feed.xml'   => "---\ndescription: The Atom feed\n---\n<feed/>",
    }, bare => 1);
    my $text = guide();
    is_deeply([ $text =~ /^## (.+)$/mg ], ['Commands', 'Where things are', 'Layouts', 'Front matter rules', 'Categories and tags in use', 'Rules'], 'every section, in order');
    like(section($text, 'Commands'), qr/^- `dapper build`: build the site into `public\/`\n- `dapper deploy`: build, check and publish the site\n- `dapper agents`/m, 'deploy is listed when there are deploy settings');
    my $where = section($text, 'Where things are');
    like($where, qr/^- `pages\/`: the pages/m, 'the source directory from the project file');
    like($where, qr/^- `templates\/`: the layouts/m, 'the layout directory');
    like($where, qr/^- `info\/`: data files/m, 'the data directory');

    is(section($text, 'Layouts'), "- `feed`: The Atom feed\n- `index`: The wrapper\n- `plain`\n- `post`\n\nA page uses the layout named by its `layout` setting, or `index` if it has none.\n\n",
        'layouts sorted, with their descriptions; a description that is not text is left out');

    is(section($text, 'Front matter rules'), join("\n",
        "Pages must match the `_schema.yml` that applies to their folder; the build refuses",
        "pages that don't.",
        "",
        "### `pages/`",
        "",
        "- Required: `title`",
        "- `categories`: list, one of `news`, `blog`",
        "- `rating`: integer, from 1, up to 5",
        "- `slug`: string, matching `^[a-z-]+\$`",
        "- `tags`: list",
        "- `title`: string, at most 60 characters, at least 2 characters",
        "- Other fields are not allowed",
        "",
        "### `pages/docs/`",
        "",
        "- `order`: number",
        "", ""), 'every rule of every schema, fields sorted');

    is(section($text, 'Categories and tags in use'), "- Categories: `blog`, `news`\n- Tags: `apple`, `zebra`\n\nReuse these where they fit rather than inventing near-duplicates.\n\n", 'categories and tags, sorted');

    like($text, qr/`info\/redirects\.yml`/, 'the redirects rule names the data directory in use');
};

subtest 'categories without tags, and tags without categories' => sub {
    make_site({ '_source/a.md' => "---\ntitle: A\ncategories: notes\n---\nx\n" });
    my $section = section(guide(), 'Categories and tags in use');
    is($section, "- Categories: `notes`\n\nReuse these where they fit rather than inventing near-duplicates.\n\n", 'only categories');

    make_site({ '_source/a.md' => "---\ntitle: A\ntags: [one]\n---\nx\n" });
    $section = section(guide(), 'Categories and tags in use');
    is($section, "- Tags: `one`\n\nReuse these where they fit rather than inventing near-duplicates.\n\n", 'only tags');

    make_site({ '_source/a.md' => "---\ntitle: A\ntags: [one]\ndraft: true\n---\nx\n" });
    is(section(guide(), 'Categories and tags in use'), undef, 'tags only on drafts are not listed');
};

subtest 'a schema with only required fields, and one that is broken' => sub {
    make_site({
        '_source/index.md'       => "---\ntitle: Home\n---\nx\n",
        '_source/a/_schema.yml'  => "required: [title, summary]\n",
        '_source/b/_schema.yml'  => "additional: false\n",
    });
    my $rules = section(guide(), 'Front matter rules');
    like($rules, qr/^### `_source\/a\/`\n\n- Required: `title`, `summary`\n\n### `_source\/b\/`\n\n- Other fields are not allowed\n/m, 'required only; additional: false only');

    spew('_source/c/_schema.yml', "required: x\nbogus: 1\n");
    my $text = guide();
    like($text, qr/^### `_source\/a\/`$/m, 'good schemas are still explained');
    unlike($text, qr/_source\/c/, 'a broken schema is left out');
    unlike($text, qr/Categories and tags/, 'and with the site unreadable, categories are left out');
    like($text, qr/^## Rules$/m, 'but the guide is complete');
};

subtest 'the guide without a project' => sub {
    make_site({}, bare => 1);
    my @warnings;
    my $text = do { local $SIG{__WARN__} = sub { push @warnings, @_ }; guide() };
    like($text, qr/\A# Working on this site\n/, 'a site without a name is "this site"');
    is_deeply(\@warnings, [], 'no warnings');
    like($text, qr/^- `_data\/`: data files/m, 'the default data directory');
    like($text, qr/^- `_source\/`: the pages/m, 'with the default directories');
    unlike($text, qr/^## Layouts$/m, 'no layouts section without layouts');
    unlike($text, qr/Front matter rules/, 'no schemas without a source directory');
    like($text, qr/^## Rules$/m, 'the rules');

    make_site({ '_config.yml' => "name: [\n", '_source/_schema.yml' => "required: [title]\n" }, bare => 1);
    $text = do { local $SIG{__WARN__} = sub {}; guide() };
    like($text, qr/\A# Working on this site\n/, 'a project file that cannot be read');
    like($text, qr/- Required: `title`/, 'schemas are still explained');

    make_site({ '_config.yml' => "---\nname: Named\n", '_layout/index.html' => "---\ndescription: [broken\n---\nx" }, bare => 1);
    $text = guide();
    like($text, qr/\A# Working on Named\n/, 'the name');
    unlike($text, qr/^- `index`/m, 'a layout that cannot be read is left out');
};

subtest 'update writes a new AGENTS.md and CLAUDE.md' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });
    my @written = update();
    is_deeply(\@written, ['AGENTS.md', 'CLAUDE.md'], 'both files written');
    my $agents = slurp('AGENTS.md');
    like($agents, qr/\A\Q$BEGIN\E\n# Working on Test Site\n/, 'AGENTS.md starts with the begin marker');
    like($agents, qr/^- Don't edit or commit the output directory or `\.dapper\/`\.\n\Q$END\E\n\z/m, 'and ends with the end marker');
    is($agents, "$BEGIN\n" . guide() . "$END\n", 'and holds the guide');
    is(slurp('CLAUDE.md'), "This site is built with Dapper. Read AGENTS.md before making changes.\n\n\@AGENTS.md\n", 'CLAUDE.md points at AGENTS.md');

    @written = update();
    is_deeply(\@written, ['AGENTS.md'], 'a second run writes only AGENTS.md');
    is(slurp('AGENTS.md'), $agents, 'which comes out the same');
};

subtest 'notes for a new AGENTS.md' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });
    update("## Theme notes\n\n- Keep it short.\n");
    like(slurp('AGENTS.md'), qr/\Q$END\E\n\n## Theme notes\n\n- Keep it short\.\n\z/, 'notes follow the generated part after a blank line');

    update("## Different notes\n");
    unlike(slurp('AGENTS.md'), qr/Different notes/, 'notes are only added to a new file');
    like(slurp('AGENTS.md'), qr/## Theme notes/, 'the first notes stay');

    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });
    update('');
    like(slurp('AGENTS.md'), qr/\Q$END\E\n\z/, 'empty notes add nothing');
};

subtest 'update keeps what is outside the markers' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });
    spew('AGENTS.md', "# Our project\n\nBefore.\n\n$BEGIN\nold generated text\n$END\n\nAfter.\n");
    my @written = update();
    is_deeply(\@written, ['AGENTS.md', 'CLAUDE.md'], 'AGENTS.md updated and CLAUDE.md written');
    my $text = slurp('AGENTS.md');
    like($text, qr/\A# Our project\n\nBefore\.\n\n\Q$BEGIN\E\n# Working on Test Site\n/, 'what is before is kept');
    like($text, qr/\Q$END\E\n\nAfter\.\n\z/, 'what is after is kept');
    unlike($text, qr/old generated text/, 'the old generated part is replaced');
    is(() = $text =~ /dapper:begin/g, 1, 'one begin marker');
    is(() = $text =~ /dapper:end/g, 1, 'one end marker');

    spew('AGENTS.md', "Top\n$BEGIN\nold$END");
    update();
    is(slurp('AGENTS.md'), "Top\n$BEGIN\n" . guide() . "$END\n", 'an end marker without a newline after it');

    spew('AGENTS.md', "$BEGIN\nfirst\n$END\nmiddle\n$BEGIN\nsecond\n$END\n");
    update();
    $text = slurp('AGENTS.md');
    like($text, qr/\A\Q$BEGIN\E\n# Working on Test Site\n.*\Q$END\E\nmiddle\n\Q$BEGIN\E\nsecond\n\Q$END\E\n\z/s, 'only the first generated part is replaced');
};

subtest 'update appends to an AGENTS.md without markers' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });
    spew('AGENTS.md', "# Hand written\n\nNotes.\n");
    update("## Ignored notes\n");
    my $text = slurp('AGENTS.md');
    is($text, "# Hand written\n\nNotes.\n\n$BEGIN\n" . guide() . "$END\n", 'the generated part is added after a blank line');
    unlike($text, qr/Ignored notes/, 'without the notes');

    spew('AGENTS.md', "<!-- dapper:begin -->\nhalf a marker\n");
    update();
    like(slurp('AGENTS.md'), qr/\A<!-- dapper:begin -->\nhalf a marker\n\n\Q$BEGIN\E/, 'markers that are not exactly right are treated as notes');

    spew('AGENTS.md', '');
    update();
    is(slurp('AGENTS.md'), "\n$BEGIN\n" . guide() . "$END\n", 'an empty AGENTS.md gets a blank line, then the guide');
};

subtest 'CLAUDE.md is never replaced' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n", 'CLAUDE.md' => "Mine.\n" });
    is_deeply([ update() ], ['AGENTS.md'], 'only AGENTS.md written');
    is(slurp('CLAUDE.md'), "Mine.\n", 'CLAUDE.md untouched');

    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n", 'CLAUDE.md/notes.md' => "x\n" });
    is_deeply([ update() ], ['AGENTS.md'], 'a CLAUDE.md directory counts as there');
    ok(-d 'CLAUDE.md', 'and is left alone');
};

subtest 'App::Dapper agents and init report the files' => sub {
    make_site({ '_source/index.md' => "---\ntitle: Home\n---\nx\n" });
    my $d = App::Dapper->new();
    my $out = '';
    {
        local *STDOUT;
        open(STDOUT, '>', \$out);
        $d->agents();
    }
    is($out, "Wrote AGENTS.md\nWrote CLAUDE.md\n", 'agents says what it wrote');

    $out = '';
    $d->{quiet} = 1;
    {
        local *STDOUT;
        open(STDOUT, '>', \$out);
        $d->agents();
    }
    is($out, '', 'and nothing when quiet');

    make_site({}, bare => 1);
    $d = App::Dapper->new();
    $out = '';
    {
        local *STDOUT;
        open(STDOUT, '>', \$out);
        $d->init();
    }
    like($out, qr/^Creating \.gitignore\nCreating AGENTS\.md\nCreating CLAUDE\.md\nProject initialized\.\n\z/m, 'init says it creates them');
    like(slurp('AGENTS.md'), qr/# Working on My Site/, 'about the new site');
};

done_testing();
