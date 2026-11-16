use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;

# _schema.yml files in a real build and in dapper check: which pages each
# applies to, and how problems are reported.

sub build_error {
    eval { quiet_build() };
    return $@;
}

sub check_errors {
    my $report = App::Dapper->new()->check();
    return [ map { "$_->{type} $_->{file}: $_->{message}" } @{ $report->{errors} } ], $report;
}

subtest 'one problem: singular, with the file and message' => sub {
    make_site({
        '_source/_schema.yml' => "required: [title]\n",
        '_source/a.md'        => "---\ndescription: x\n---\nx\n",
    });
    is(build_error(), "error: 1 problem with front matter (see the _schema.yml files):\n  _source/a.md: \"title\" is required\n",
        'exact message');
};

subtest 'several problems across pages: plural, in source order' => sub {
    make_site({
        '_source/_schema.yml' => "required: [title, date]\nfields:\n  date: date\n",
        '_source/a.md'        => "---\ntitle: A\n---\nx\n",
        '_source/b.md'        => "---\ndate: never\n---\nx\n",
    });
    is(build_error(), "error: 3 problems with front matter (see the _schema.yml files):\n"
        . "  _source/a.md: \"date\" is required\n"
        . "  _source/b.md: \"title\" is required\n"
        . "  _source/b.md: \"date\" must be a date, e.g. 2014-05-02T10:30:00\n",
        'every problem listed');
    ok(!-e '_output/a.html', 'nothing is written');
};

subtest 'a schema applies to its directory and every directory below' => sub {
    make_site({
        '_source/_schema.yml'        => "required: [title]\n",
        '_source/a/b/c/deep.md'      => "---\ndescription: deep\n---\nx\n",
        '_source/a/mid.md'           => "---\ndescription: mid\n---\nx\n",
    });
    like(build_error(), qr{\Aerror: 2 problems.*\n  _source/a/b/c/deep\.md: "title" is required\n  _source/a/mid\.md: "title" is required\n\z}s,
        'inherited at every depth');
};

subtest 'a nearer schema replaces the parent one, it does not add to it' => sub {
    make_site({
        '_source/_schema.yml'       => "required: [title]\nfields:\n  rating: integer\n",
        '_source/notes/_schema.yml' => "required: [summary]\n",
        '_source/notes/n.md'        => "---\nsummary: S\nrating: high\n---\nx\n",
        '_source/notes/sub/m.md'    => "---\ntitle: T\n---\nx\n",
    });
    is(build_error(), "error: 1 problem with front matter (see the _schema.yml files):\n  _source/notes/sub/m.md: \"summary\" is required\n",
        'notes/ pages follow notes/_schema.yml only, and so do its subdirectories');
};

subtest 'sibling directories do not share a schema' => sub {
    make_site({
        '_source/blog/_schema.yml' => "required: [date]\n",
        '_source/blog/p.md'        => "---\ntitle: P\ndate: 2020-01-01T00:00:00Z\n---\nx\n",
        '_source/pages/q.md'       => "---\ntitle: Q\n---\nx\n",
        '_source/top.md'           => "---\ntitle: Top\n---\nx\n",
    });
    is(build_error(), '', 'pages outside blog/ are not checked');
    ok(-f '_output/pages/q.html', 'and are built');
    ok(!-e '_output/blog/_schema.yml', 'the schema is not copied');
};

subtest 'files without front matter are not checked' => sub {
    make_site({
        '_source/_schema.yml' => "required: [title]\n",
        '_source/image.png'   => "PNG",
        '_source/a.md'        => "---\ntitle: A\n---\nx\n",
    });
    is(build_error(), '', 'static files are copied without checking');
    ok(-f '_output/image.png', 'copied');
};

subtest 'an invalid schema stops the build with its own message' => sub {
    make_site({
        '_source/_schema.yml' => "fields:\n  title:\n    type: text\n",
        '_source/a.md'        => "---\ntitle: A\n---\nx\n",
    });
    is(build_error(), "error: the schema \"_source/_schema.yml\" has problems:\n"
        . "  \"title\" has the unknown type \"text\" (use any, boolean, date, integer, list, map, number, string)\n",
        'exact message');
};

subtest 'check: schema problems name the schema file, and the page is left out' => sub {
    make_site({
        '_source/blog/_schema.yml' => "required: [title, date]\nfields:\n  rating:\n    type: integer\n    min: 1\n",
        '_source/blog/a.md'        => "---\ntitle: A\nrating: 0\n---\nx\n",
        '_source/ok.md'            => "---\ntitle: OK\n---\nx\n",
    });
    my ($errors, $report) = check_errors();
    is_deeply($errors, [
        'schema _source/blog/a.md: "date" is required (see _source/blog/_schema.yml)',
        'schema _source/blog/a.md: "rating" is 0; the smallest allowed is 1 (see _source/blog/_schema.yml)',
    ], 'each problem, typed schema') or diag explain $errors;
    is($report->{pages}, 1, 'the page that failed is not counted');
};

subtest 'check: an invalid schema is one error, and its pages are not checked against it' => sub {
    make_site({
        '_source/_schema.yml' => "fields:\n  title:\n    bogus: 1\n",
        '_source/a.md'        => "---\ntitle: A\n---\nx\n",
    });
    my ($errors, $report) = check_errors();
    is_deeply($errors, [
        "schema _source/_schema.yml: the schema \"_source/_schema.yml\" has problems:\n  \"title\" has the unknown rule \"bogus\"",
    ], 'reported against the schema file') or diag explain $errors;
    is($report->{pages}, 1, 'the page is still built');
};

subtest 'check: a nested invalid schema falls back to the parent schema' => sub {
    make_site({
        '_source/_schema.yml'     => "required: [title]\n",
        '_source/sub/_schema.yml' => "- not a map\n",
        '_source/sub/a.md'        => "---\ndescription: x\n---\nx\n",
    });
    my ($errors) = check_errors();
    is_deeply($errors, [
        'schema _source/sub/_schema.yml: the schema "_source/sub/_schema.yml" must contain key: value pairs',
        'schema _source/sub/a.md: "title" is required (see _source/_schema.yml)',
    ], 'the parent schema still applies') or diag explain $errors;
};

subtest 'drafts are checked against the schema too' => sub {
    make_site({
        '_source/_schema.yml' => "required: [title]\n",
        '_source/d.md'        => "---\ndraft: true\n---\nx\n",
    });
    like(build_error(), qr{_source/d\.md: "title" is required}, 'a draft must still match');
};

done_testing();
