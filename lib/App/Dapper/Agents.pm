package App::Dapper::Agents;

=head1 NAME

App::Dapper::Agents - Explain a Dapper project to AI coding agents.

=head1 DESCRIPTION

C<dapper init> writes an C<AGENTS.md> file that tells AI coding agents (and
people) how the project works: where pages, layouts and data live, which
front matter each kind of page needs, the rules Dapper enforces, and the
commands to run. A C<CLAUDE.md> points Claude Code at it.

C<dapper agents> brings C<AGENTS.md> up to date after the project changes.
The part Dapper writes sits between C<< <!-- dapper:begin --> >> and
C<< <!-- dapper:end --> >>; anything outside those lines (your own notes, or
a theme's) is kept.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use File::Basename qw/ dirname /;
use File::Find ();

use App::Dapper::Utils;
use App::Dapper::Schema;

my $BEGIN = '<!-- dapper:begin (this part is written by "dapper agents"; edit outside it) -->';
my $END   = '<!-- dapper:end -->';

=head2 update

Takes a Dapper object (and optionally extra notes for a new file), and writes
or updates C<AGENTS.md> in the current directory, and a C<CLAUDE.md> if there
isn't one. Returns the list of files written.

=cut

sub update {
    my ($dapper, $notes) = @_;

    my $generated = "$BEGIN\n" . guide($dapper) . "$END\n";
    my @written;

    my $file = 'AGENTS.md';
    if (-f $file) {
        my $text = App::Dapper::Utils::read_file($file);
        if ($text =~ s/\Q$BEGIN\E.*?\Q$END\E\n?/$generated/s) {
            App::Dapper::Utils::write_file($file, $text);
        }
        else {
            App::Dapper::Utils::write_file($file, "$text\n$generated");
        }
    }
    else {
        my $text = $generated;
        $text .= "\n$notes" if defined $notes and length $notes;
        App::Dapper::Utils::write_file($file, $text);
    }
    push @written, $file;

    if (not -e 'CLAUDE.md') {
        App::Dapper::Utils::write_file('CLAUDE.md',
            "This site is built with Dapper. Read AGENTS.md before making changes.\n\n\@AGENTS.md\n");
        push @written, 'CLAUDE.md';
    }

    return @written;
}

=head2 guide

Takes a Dapper object and returns the guide to the project, in Markdown.

=cut

sub guide {
    my ($dapper) = @_;

    my $loaded = eval {
        local $dapper->{quiet} = 1;
        local $dapper->{collect} = 1;
        $dapper->{problems} = [];
        $dapper->{written} = {};
        $dapper->{page_owner} = {};
        $dapper->parse();
        $dapper->transform();
        1;
    };

    my $site = $dapper->{site};
    my ($source, $layout, $output, $data) = map { $dapper->{$_} } qw/ source layout output data_dir /;
    my $name = defined $site->{name} ? $site->{name} : 'this site';

    my $text = <<"MD";
# Working on $name

This is a static website built with [Dapper](https://github.com/markdbenson/dapper).
Pages are Markdown or HTML files with YAML front matter; layouts turn them into
HTML in `$output/`. Edit the source files, never the output.

## Commands

- `dapper serve`: build, watch for changes and serve the site at http://localhost:8000
- `dapper check --json`: find problems (broken links, front matter that doesn't match
  a schema, missing layouts, template errors). **Run it after every change and fix
  every error it reports.**
- `dapper build`: build the site into `$output/`
MD
    $text .= "- `dapper deploy`: build, check and publish the site\n" if $site->{deploy};
    $text .= "- `dapper agents`: update this file after adding layouts, schemas or settings\n";

    $text .= <<"MD";

## Where things are

- `$source/`: the pages. A file's path decides its URL unless it has `categories` or
  a `urlpattern` (then its URL comes from the pattern; posts usually live here).
- `$layout/`: the layouts, which are templates (Template Toolkit syntax, `[% ... %]`).
- `$data/`: data files (YAML or JSON), available in templates as `site.data`.
- `$dapper->{config}`: the site's settings.
- Other top-level files and folders (CSS, images, scripts) are copied to the output
  as they are, except names starting with `.` or `_`.
MD

    my @layouts = sort keys %{ $dapper->{layout_content} || {} };
    if (@layouts) {
        $text .= "\n## Layouts\n\n";
        for my $name (@layouts) {
            my $description = _layout_description($dapper, $name);
            $text .= "- `$name`" . (defined $description ? ": $description" : '') . "\n";
        }
        $text .= "\nA page uses the layout named by its `layout` setting, or `index` if it has none.\n";
    }

    my @schemas = _schemas($dapper);
    if (@schemas) {
        $text .= "\n## Front matter rules\n\n";
        $text .= "Pages must match the `_schema.yml` that applies to their folder; the build refuses\n";
        $text .= "pages that don't.\n\n";
        for my $schema (@schemas) {
            my $dir = dirname($schema->{file});
            $text .= "### `$dir/`\n\n";
            $text .= "- Required: " . join(', ', map { "`$_`" } @{$schema->{required}}) . "\n" if @{$schema->{required}};
            for my $field (sort keys %{$schema->{fields}}) {
                my $rules = $schema->{fields}->{$field};
                my @parts = ($rules->{type});
                push @parts, 'one of ' . join(', ', map { "`$_`" } @{$rules->{values}}) if $rules->{values};
                push @parts, "at most $rules->{max_length} characters" if defined $rules->{max_length};
                push @parts, "at least $rules->{min_length} characters" if defined $rules->{min_length};
                push @parts, "from $rules->{min}" if defined $rules->{min};
                push @parts, "up to $rules->{max}" if defined $rules->{max};
                push @parts, "matching `$rules->{pattern}`" if defined $rules->{pattern};
                $text .= "- `$field`: " . join(', ', @parts) . "\n";
            }
            $text .= "- Other fields are not allowed\n" unless $schema->{additional};
            $text .= "\n";
        }
    }
    $text =~ s/\n\n\z/\n/;

    if ($loaded) {
        my @categories = sort keys %{ $site->{categories} || {} };
        my @tags = sort keys %{ $site->{tags} || {} };
        if (@categories or @tags) {
            $text .= "\n## Categories and tags in use\n\n";
            $text .= "- Categories: " . join(', ', map { "`$_`" } @categories) . "\n" if @categories;
            $text .= "- Tags: " . join(', ', map { "`$_`" } @tags) . "\n" if @tags;
            $text .= "\nReuse these where they fit rather than inventing near-duplicates.\n";
        }
    }

    $text .= <<'MD';

## Rules

- **Content is not a template.** `[% ... %]` in a page is shown as text. Only add
  `template: true` to a page that needs template code (such as a list of posts);
  layouts are always templates.
- **Dates** are written like `2026-01-01T09:00:00` (or `2026-01-01`).
- **Every page needs a `title`**; give pages a `description` (about 150 characters)
  for search engines, social media and AI tools.
- **Links between pages** start with `/` (for example `/about.html` or
  `/blog/2026/01/my-post/`). `dapper check` reports links that lead nowhere.
- **Images** need meaningful alt text: `![A loaf of sourdough on a board](/images/loaf.jpg)`.
- When you rename or move a page, add a redirect from its old URL in
  `_data/redirects.yml` (`/old-url/: /new-url/`).
- In layouts, don't name template variables after directives (`next`, `last`, `loop`,
  `block`, `wrapper`, ...): Dapper's templates are case-insensitive, so they are read as
  directives. Use names like `later` or `count` instead.
- Don't edit or commit the output directory or `.dapper/`.
MD

    return $text;
}

sub _layout_description {
    my ($dapper, $name) = @_;

    my $file;
    for my $candidate (App::Dapper::Utils::read_dir($dapper->{layout})) {
        if (App::Dapper::Utils::filter_stem($candidate) eq $name) { $file = "$dapper->{layout}/$candidate"; last }
    }
    return unless defined $file and -f $file;

    my ($frontmatter) = eval { App::Dapper::Utils::split_frontmatter(App::Dapper::Utils::read_file($file), $file) };
    return unless ref $frontmatter eq 'HASH' and defined $frontmatter->{description} and !ref $frontmatter->{description};
    return $frontmatter->{description};
}

sub _schemas {
    my ($dapper) = @_;

    my @schemas;
    return unless -d $dapper->{source};
    File::Find::find({
        no_chdir => 1,
        wanted   => sub {
            my $name = App::Dapper::Utils::name_chars($File::Find::name);
            return unless $name =~ m{(?:^|/)_schema\.yml$};
            my $schema = eval { App::Dapper::Schema::load($name) };
            push @schemas, $schema if $schema;
        },
    }, App::Dapper::Utils::name_bytes($dapper->{source}));

    return sort { $a->{file} cmp $b->{file} } @schemas;
}

1;
