use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Schema;

my $schema_yaml = <<'YAML';
required: [title, date]
fields:
  title:
    type: string
    max_length: 20
  date:
    type: date
  categories:
    type: list
    values: [blog, notes]
  draft:
    type: boolean
  rating:
    type: integer
    min: 1
    max: 5
  slug:
    type: string
    pattern: '^[a-z-]+$'
YAML

subtest 'pages that match pass' => sub {
    make_site({
        '_source/blog/_schema.yml' => $schema_yaml,
        '_source/blog/good.md'     => "---\ntitle: Good\ndate: 2020-01-01\ncategories: blog\ndraft: false\nrating: 3\n---\nx\n",
        '_source/index.md'         => "---\ntitle: Outside the schema\n---\nx\n",
    });
    my $d = quiet_build();
    is(scalar @{ $d->{site}->{pages} }, 2, 'both pages built');
    ok(!-e '_output/blog/_schema.yml', 'the schema file is not copied to the output');
};

subtest 'every problem on every page is reported at once' => sub {
    make_site({
        '_source/blog/_schema.yml' => $schema_yaml,
        '_source/blog/a.md' => "---\ntitle: This title is far too long for it\ncategories: [blog, news]\n---\nx\n",
        '_source/blog/b.md' => "---\ntitle: B\ndate: someday\ndraft: maybe\nrating: 9\nslug: Not_Valid\n---\nx\n",
    });
    eval { quiet_build() };
    my $error = $@;
    like($error, qr/7 problems with front matter/, 'counted');
    like($error, qr{_source/blog/a\.md: "date" is required}, 'missing required field');
    like($error, qr{a\.md: "title" is 33 characters long; the most allowed is 20}, 'too long');
    like($error, qr{a\.md: "categories" has "news", which is not one of: blog, notes}, 'list value not allowed');
    like($error, qr{b\.md: "date" must be a date}, 'not a date');
    like($error, qr{b\.md: "draft" must be true or false}, 'not a boolean');
    like($error, qr{b\.md: "rating" is 9; the largest allowed is 5}, 'number too large');
    like($error, qr{b\.md: "slug" does not match the pattern}, 'pattern');
};

subtest 'nested directories use the nearest schema' => sub {
    make_site({
        '_source/_schema.yml'        => "required: [title]\n",
        '_source/notes/_schema.yml'  => "required: [summary]\n",
        '_source/top.md'             => "---\ntitle: Top\n---\nx\n",
        '_source/notes/deep/note.md' => "---\nsummary: Has a summary but no title\n---\nx\n",
    });
    eval { quiet_build() };
    is($@, '', 'each page checked against its nearest schema');
};

subtest 'additional: false' => sub {
    make_site({
        '_source/_schema.yml' => "fields:\n  title: string\nadditional: false\n",
        '_source/a.md'        => "---\ntitle: A\ncolour: blue\n---\nx\n",
    });
    eval { quiet_build() };
    like($@, qr{"colour" is not one of the fields in the schema}, 'unknown field rejected');
};

subtest 'an invalid schema names the schema file' => sub {
    make_site({
        '_source/_schema.yml' => "fields:\n  title:\n    type: text\n    maximum: 3\nrequires: [x]\n",
        '_source/a.md'        => "---\ntitle: A\n---\nx\n",
    });
    eval { quiet_build() };
    like($@, qr{the schema "_source/_schema.yml" has problems}, 'schema file named');
    like($@, qr{"title" has the unknown type "text"}, 'unknown type');
    like($@, qr{"title" has the unknown rule "maximum"}, 'unknown rule');
    like($@, qr{unknown setting "requires"}, 'unknown top-level setting');
};

subtest 'validate directly' => sub {
    my $schema = { required => ['title'], fields => { tags => { type => 'list' } }, additional => 1 };
    is_deeply([ App::Dapper::Schema::validate($schema, { title => 'x', tags => 'one' }) ], [], 'a single value is a one-item list');
    is_deeply([ App::Dapper::Schema::validate($schema, { title => '' }) ], ['"title" is required'], 'empty counts as missing');
};

done_testing();
