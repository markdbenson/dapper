package App::Dapper::MCP;

=head1 NAME

App::Dapper::MCP - Let AI assistants work on a Dapper site over MCP.

=head1 DESCRIPTION

C<dapper mcp> runs a Model Context Protocol server on standard input and
output, so that an AI assistant (Claude, or any other MCP client) can read,
write, build and check a site through Dapper, with Dapper's rules as
guardrails: pages are only written inside the source directory, and a page
that doesn't match its C<_schema.yml> is refused rather than written.

To add it to Claude Code:

    $ claude mcp add dapper -- dapper -C /path/to/site mcp

Other clients take a command and arguments in their configuration:

    { "command": "dapper", "args": ["-C", "/path/to/site", "mcp"] }

=head2 Tools

=over 4

=item B<site_info>

The site's settings, directories, categories, tags and schemas.

=item B<list_pages>

Every page (optionally only those in a C<category> or with a C<tag>), with
its source file, URL, title, date, categories and tags.

=item B<read_page>

A page's front matter and body, given its source file.

=item B<write_page>

Create or replace a page from front matter and a body. The page is checked
against its schema first and is not written if it doesn't match.

=item B<build>

Build the site.

=item B<check>

Find problems without touching the output directory (see
L<App::Dapper::Check>).

=back

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use JSON ();
use YAML::PP;
use File::Spec;
use File::Spec::Functions qw/ canonpath catfile /;
use File::Basename qw/ dirname /;
use File::Find ();
use IO::Handle;

use App::Dapper::Utils;
use App::Dapper::Schema;

my $PROTOCOL_VERSION = '2025-06-18';

my @TOOLS = (
    {
        name        => 'site_info',
        description => 'Describe the Dapper site: its settings, directories, number of pages, categories, tags, and the front matter schemas pages must follow.',
        inputSchema => { type => 'object', properties => {} },
    },
    {
        name        => 'list_pages',
        description => 'List the pages of the site with their source file, URL, title, date, categories and tags. Optionally only pages in a category or with a tag.',
        inputSchema => {
            type       => 'object',
            properties => {
                category => { type => 'string', description => 'Only pages in this category' },
                tag      => { type => 'string', description => 'Only pages with this tag' },
            },
        },
    },
    {
        name        => 'read_page',
        description => 'Read a page: its front matter (as an object) and its body (Markdown or HTML).',
        inputSchema => {
            type       => 'object',
            properties => {
                source => { type => 'string', description => 'The source file, e.g. blog/my-post.md (relative to the source directory)' },
            },
            required => ['source'],
        },
    },
    {
        name        => 'write_page',
        description => 'Create or replace a page in the source directory. The front matter is checked against the nearest _schema.yml first; if it does not match, nothing is written and the problems are returned. Run check or build afterwards.',
        inputSchema => {
            type       => 'object',
            properties => {
                source       => { type => 'string', description => 'The source file to write, e.g. blog/my-post.md (relative to the source directory)' },
                front_matter => { type => 'object', description => 'The page settings, e.g. {"title": "...", "date": "2026-01-01T09:00:00", "categories": ["blog"]}' },
                body         => { type => 'string', description => 'The page content, in Markdown for .md files' },
                overwrite    => { type => 'boolean', description => 'Replace the file if it already exists (default false)' },
            },
            required => ['source', 'front_matter', 'body'],
        },
    },
    {
        name        => 'build',
        description => 'Build the site into the output directory.',
        inputSchema => { type => 'object', properties => {} },
    },
    {
        name        => 'check',
        description => 'Check the site for problems (front matter, schemas, layouts, templates, broken links) without touching the output directory.',
        inputSchema => { type => 'object', properties => {} },
    },
);

=head2 serve

Takes a Dapper object, and answers MCP requests from standard input on
standard output until standard input closes.

=cut

sub serve {
    my ($dapper) = @_;

    # Responses go to the real standard output; anything else that would be
    # printed while a tool runs (such as Pagefind's output) goes to standard
    # error, so that it can't corrupt the conversation
    open(my $out, '>&', \*STDOUT) or die "error: could not open standard output: $!\n";
    binmode($out, ':raw');
    $out->autoflush(1);
    open(STDOUT, '>&', \*STDERR) or die "error: could not redirect standard output: $!\n";
    binmode(STDIN, ':raw');

    my $json = JSON->new->utf8->canonical;

    while (my $line = <STDIN>) {
        next unless $line =~ /\S/;

        my $request = eval { $json->decode($line) };
        if (not $request or ref $request ne 'HASH') {
            print $out $json->encode({ jsonrpc => '2.0', id => undef,
                error => { code => -32700, message => 'Parse error' } }), "\n";
            next;
        }

        my $response = handle($dapper, $request);
        print $out $json->encode($response), "\n" if $response;
    }
}

=head2 handle

Takes a Dapper object and a JSON-RPC request, and returns the response (or
nothing, for notifications).

=cut

sub handle {
    my ($dapper, $request) = @_;

    my $id = $request->{id};
    my $method = defined $request->{method} ? $request->{method} : '';
    my $params = ref $request->{params} eq 'HASH' ? $request->{params} : {};

    return if not defined $id;    # a notification, such as notifications/initialized

    my $result;
    if ($method eq 'initialize') {
        my $requested = $params->{protocolVersion};
        $result = {
            protocolVersion => defined $requested ? $requested : $PROTOCOL_VERSION,
            capabilities    => { tools => {} },
            serverInfo      => { name => 'dapper', version => "$App::Dapper::VERSION" },
            instructions    => 'Dapper builds a static website from Markdown and HTML files with YAML front matter. '
                             . 'Use site_info first to learn the site\'s schemas and categories, write_page to create pages '
                             . '(it refuses pages that do not match their schema), then check to find problems and build to publish.',
        };
    }
    elsif ($method eq 'ping') {
        $result = {};
    }
    elsif ($method eq 'tools/list') {
        $result = { tools => \@TOOLS };
    }
    elsif ($method eq 'tools/call') {
        $result = call_tool($dapper, $params->{name}, ref $params->{arguments} eq 'HASH' ? $params->{arguments} : {});
    }
    else {
        return { jsonrpc => '2.0', id => $id, error => { code => -32601, message => "Method not found: $method" } };
    }

    return { jsonrpc => '2.0', id => $id, result => $result };
}

=head2 call_tool

Takes a Dapper object, a tool name and its arguments, runs the tool, and
returns an MCP tool result.

=cut

sub call_tool {
    my ($dapper, $name, $args) = @_;

    my %tools = (
        site_info  => \&site_info,
        list_pages => \&list_pages,
        read_page  => \&read_page,
        write_page => \&write_page,
        build      => \&build,
        check      => \&check,
    );

    my $tool = defined $name ? $tools{$name} : undef;
    return tool_result({ error => "There is no tool called \"" . (defined $name ? $name : '') . "\"." }, 1) unless $tool;

    my ($data, $is_error);
    eval { ($data, $is_error) = $tool->($dapper, $args); 1 } or do {
        (my $message = $@) =~ s/^error: //;
        $message =~ s/\s+\z//;
        ($data, $is_error) = ({ error => $message }, 1);
    };

    return tool_result($data, $is_error);
}

=head2 tool_result

Takes a result (a hash) and whether it is an error, and returns it in the form
MCP expects: as JSON text, and as structured content.

=cut

sub tool_result {
    my ($data, $is_error) = @_;

    return {
        content           => [ { type => 'text', text => JSON->new->canonical->pretty->encode($data) } ],
        structuredContent => $data,
        isError           => $is_error ? JSON::true : JSON::false,
    };
}

# Read the project and source files without writing anything
sub _load {
    my ($dapper) = @_;

    local $dapper->{quiet} = 1;
    $dapper->{problems} = [];
    $dapper->{written} = {};
    $dapper->{page_owner} = {};
    $dapper->parse();
    $dapper->transform();
}

sub _page_summary {
    my ($dapper, $page) = @_;

    my $source = $page->{source};
    my $prefix = "$dapper->{source}/";
    $source = substr($source, length $prefix) if index($source, $prefix) == 0;

    my %summary = (source => $source, url => $page->{url});
    $summary{title} = $page->{title} if defined $page->{title};
    $summary{date} = "$page->{date}" if defined $page->{date};
    $summary{layout} = $page->{layout} if defined $page->{layout};
    for my $list (qw/ categories tags /) {
        my $value = $page->{$list};
        next unless defined $value;
        $summary{$list} = ref $value eq 'ARRAY' ? $value : [$value];
    }
    $summary{generated} = JSON::true if $page->{generated};
    return \%summary;
}

=head2 site_info

The C<site_info> tool.

=cut

sub site_info {
    my ($dapper) = @_;

    _load($dapper);
    my $site = $dapper->{site};

    my %settings;
    for my $key (sort keys %$site) {
        next if $key =~ /^(?:pages|categories|tags|data|time|category_pages|tag_pages)$/;
        my $value = $site->{$key};
        next if ref $value and ref $value ne 'HASH' and ref $value ne 'ARRAY';
        $settings{$key} = $value;
    }

    my @schemas;
    File::Find::find({
        no_chdir => 1,
        wanted   => sub {
            return unless $_ =~ m{/_schema\.yml$};
            my $name = App::Dapper::Utils::name_chars($File::Find::name);
            my $schema = eval { App::Dapper::Schema::load($name) };
            my $dir = dirname($name);
            push @schemas, $schema
                ? { applies_to => $dir, file => $name, required => $schema->{required},
                    fields => $schema->{fields}, additional => $schema->{additional} ? JSON::true : JSON::false }
                : { applies_to => $dir, file => $name, error => "$@" };
        },
    }, App::Dapper::Utils::name_bytes($dapper->{source}));

    return {
        name        => $site->{name},
        url         => $site->{url},
        description => $site->{description},
        directories => { source => $dapper->{source}, output => $dapper->{output}, layout => $dapper->{layout}, data => $dapper->{data_dir} },
        pages       => scalar @{$site->{pages}},
        categories  => { map { $_ => scalar @{$site->{categories}->{$_}} } keys %{$site->{categories}} },
        tags        => { map { $_ => scalar @{$site->{tags}->{$_}} } keys %{$site->{tags}} },
        layouts     => [ sort keys %{$dapper->{layout_content}} ],
        schemas     => [ sort { $a->{applies_to} cmp $b->{applies_to} } @schemas ],
        settings    => \%settings,
    };
}

=head2 list_pages

The C<list_pages> tool.

=cut

sub list_pages {
    my ($dapper, $args) = @_;

    _load($dapper);
    my $site = $dapper->{site};

    my @pages = @{$site->{pages}};
    if (defined $args->{category}) {
        @pages = reverse @{ $site->{categories}->{$args->{category}} || [] };
    }
    elsif (defined $args->{tag}) {
        @pages = reverse @{ $site->{tags}->{$args->{tag}} || [] };
    }

    return { pages => [ map { _page_summary($dapper, $_) } @pages ] };
}

=head2 source_path

Takes a Dapper object and a path given by a client, and returns the path of
the file in the source directory. Dies if the path would lead outside it.

=cut

sub source_path {
    my ($dapper, $path) = @_;

    die "error: give the source file, e.g. blog/my-post.md\n" unless defined $path and length $path;
    die "error: \"$path\" must be relative to the source directory\n" if File::Spec->file_name_is_absolute($path);

    my $source = canonpath($dapper->{source});
    my $relative = canonpath($path);
    $relative = substr($relative, length($source) + 1) if index($relative, "$source/") == 0;

    my @parts = File::Spec->splitdir($relative);
    die "error: \"$path\" must not contain ..\n" if grep { $_ eq '..' } @parts;
    die "error: \"$path\" must not be a hidden file\n" if grep { /^\./ } @parts;

    return canonpath(catfile($source, $relative));
}

=head2 read_page

The C<read_page> tool.

=cut

sub read_page {
    my ($dapper, $args) = @_;

    $dapper->read_project();
    my $file = source_path($dapper, $args->{source});
    die "error: there is no file \"$file\"\n" unless -f $file;

    my $text = App::Dapper::Utils::read_file($file);
    my ($front_matter, $body) = App::Dapper::Utils::split_frontmatter($text, $file);
    return { source => $args->{source}, file => $file, front_matter => undef, body => $text } unless defined $front_matter;

    $body =~ s/^(?:\r?\n)+//;
    return { source => $args->{source}, file => $file, front_matter => $front_matter, body => $body };
}

=head2 schema_for

Takes a Dapper object and a file in the source directory, and returns the
schema that applies to it (from the nearest C<_schema.yml> at or above its
directory), or nothing.

=cut

sub schema_for {
    my ($dapper, $file) = @_;

    my $source = canonpath($dapper->{source});
    my $dir = dirname($file);
    while (1) {
        my $schema_file = catfile($dir, '_schema.yml');
        return App::Dapper::Schema::load($schema_file) if -f $schema_file;
        last if canonpath($dir) eq $source or $dir eq '.' or $dir eq '/';
        $dir = dirname($dir);
    }
    return;
}

=head2 write_page

The C<write_page> tool.

=cut

sub write_page {
    my ($dapper, $args) = @_;

    $dapper->read_project();
    my $file = source_path($dapper, $args->{source});

    my $front_matter = $args->{front_matter};
    die "error: front_matter must be an object of page settings\n" unless ref $front_matter eq 'HASH';
    my $body = defined $args->{body} ? $args->{body} : '';
    die "error: body must be text\n" if ref $body;

    if (-e $file and not $args->{overwrite}) {
        return ({ written => JSON::false, error => "$file already exists; set overwrite to true to replace it" }, 1);
    }

    if (my $schema = schema_for($dapper, $file)) {
        my @problems = App::Dapper::Schema::validate($schema, $front_matter);
        if (@problems) {
            return ({ written => JSON::false, schema => $schema->{file}, problems => \@problems,
                      error => "The front matter does not match $schema->{file}, so the page was not written." }, 1);
        }
    }

    my $yaml = YAML::PP->new(boolean => 'JSON::PP')->dump_string($front_matter);
    $yaml = "---\n$yaml" unless $yaml =~ /^---/;
    $yaml .= "\n" unless $yaml =~ /\n\z/;
    $body .= "\n" unless $body =~ /\n\z/;

    App::Dapper::Utils::write_file($file, "$yaml---\n\n$body");

    return { written => JSON::true, file => $file, note => 'Run check to find problems, or build to publish.' };
}

=head2 build

The C<build> tool.

=cut

sub build {
    my ($dapper) = @_;

    local $dapper->{quiet} = 1;
    $dapper->build();

    return {
        built  => JSON::true,
        output => $dapper->{output},
        pages  => scalar @{$dapper->{site}->{pages}},
        files  => scalar keys %{$dapper->{written}},
    };
}

=head2 check

The C<check> tool.

=cut

sub check {
    my ($dapper) = @_;

    return $dapper->check();
}

1;
