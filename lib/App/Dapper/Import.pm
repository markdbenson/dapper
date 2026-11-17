package App::Dapper::Import;

=head1 NAME

App::Dapper::Import - Bring a site in from WordPress, Jekyll, Hugo or Medium.

=head1 DESCRIPTION

C<dapper import> copies the writing from another site into the source
directory of a Dapper project, so you can move over without retyping
anything. Run it in a Dapper project (C<dapper init> first):

    $ dapper import wordpress export.xml
    $ dapper import jekyll ../old-site
    $ dapper import hugo ../old-site
    $ dapper import medium medium-export.zip
    $ dapper import jekyll ../old-site --dry-run    # show what would happen
    $ dapper import wordpress export.xml --to posts # posts go in _source/posts

=over 4

=item B<wordpress>

Takes the export file from Tools, Export in WordPress. Posts go in
C<_source/blog> and pages in C<_source>, as HTML, with their title, date,
categories, tags and excerpt. Drafts, pending and private posts are imported
as drafts. Each page keeps its old address (with C<urlpattern>), so links to
it keep working. Videos from C<[embed]> and YouTube or Vimeo addresses on a
line of their own become embedded videos, and C<[caption]> becomes a figure.

=item B<jekyll>

Takes the site's directory. Posts in C<_posts> and drafts in C<_drafts> go
in C<_source/blog>, and other pages keep their place. Each page keeps its
address, worked out from C<permalink> as Jekyll does. Liquid that Dapper can
replace (C<highlight> blocks, C<site.baseurl>, C<relative_url>, C<post_url>)
is replaced. Folders such as C<assets> and C<images> are copied to the
project.

=item B<hugo>

Takes the site's directory. Pages in C<content> keep their place and their
address (from C<url>, C<slug>, or C<permalinks> in the Hugo configuration).
YAML, TOML and JSON front matter are all read. Files in page bundles are
copied with their page, C<static> is copied into the source directory,
C<aliases> become redirects, and the C<youtube>, C<vimeo> and C<figure>
shortcodes become components.

=item B<medium>

Takes the export from Medium's settings (the zip file, or the folder it
unzips to). Each story becomes an HTML page in C<_source/blog>, with Medium's
classes removed. Unpublished stories are imported as drafts.

=back

Nothing that is already in the source directory is overwritten. Redirects
are added to C<_data/redirects.yml>. Afterwards, C<dapper import> lists what
it couldn't convert (such as shortcodes and Liquid tags it doesn't know)
for you to look at, and C<dapper check> finds any links that need fixing.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use File::Spec::Functions qw/ catfile /;
use File::Basename qw/ basename dirname /;
use File::Find ();
use File::Temp qw/ tempdir /;
use YAML::PP ();
use JSON ();
use Encode ();

use App::Dapper::Utils;
use App::Dapper::Components;
use App::Dapper::Schema;
use App::Dapper::Publish;

my %IMPORTERS = (wordpress => \&wordpress, jekyll => \&jekyll, hugo => \&hugo, medium => \&medium);

=head2 kinds

Returns the kinds of site that can be imported.

=cut

sub kinds { return sort keys %IMPORTERS }

=head2 run

Takes a Dapper object, the kind of site (C<wordpress>, C<jekyll>, C<hugo> or
C<medium>), the file or directory to import, and options: C<to> (the
directory under the source directory for posts, default C<blog>) and
C<dry_run>. Imports the site and returns a summary as a hash reference.

=cut

sub run {
    my ($dapper, $kind, $from, %options) = @_;

    die "error: say what to import from: dapper import <" . join('|', kinds()) . "> <file or directory>\n"
        unless defined $kind and defined $from;
    $kind = lc $kind;
    die "error: Dapper can't import from \"$kind\"; it can import from " . join(', ', kinds()) . "\n"
        unless $IMPORTERS{$kind};
    die "error: \"$from\" doesn't exist\n" unless -e $from;

    $dapper->read_project();

    my $to = defined $options{to} ? $options{to} : 'blog';
    $to =~ s{^/+|/+$}{}g;

    my $state = {
        dapper    => $dapper,
        source    => $dapper->{source},
        to        => $to,
        dry_run   => $options{dry_run},
        layouts   => { map { App::Dapper::Utils::filter_stem($_) => 1 } (-d $dapper->{layout} ? App::Dapper::Utils::read_dir($dapper->{layout}) : ()) },
        pages     => [],
        skipped   => [],
        copied    => 0,
        redirects => {},
        notes     => {},
        taken     => {},
    };

    $IMPORTERS{$kind}->($state, $from);
    write_redirects($state);

    report($state);
    return $state;
}

# --- Writing ---------------------------------------------------------------

# add_page(state, path, \@front_matter_pairs, body, kind) - Write a page to
# the source directory, unless something is already there.
sub add_page {
    my ($state, $path, $front, $body, $kind) = @_;

    $path =~ s{^/+}{};
    my $file = "$state->{source}/$path";

    # Two imported pages with the same name get -2, -3, ...
    if ($state->{taken}->{$file}) {
        my $n = 2;
        my ($stem, $ext) = $file =~ /^(.*?)(\.[^.\/]+)?$/;
        $ext = '' unless defined $ext;
        $n++ while $state->{taken}->{"$stem-$n$ext"};
        $file = "$stem-$n$ext";
    }
    $state->{taken}->{$file} = 1;

    if (-e $file) {
        push @{$state->{skipped}}, $file;
        return;
    }

    fit_schema($state, $file, $front);

    # One spelling for each category and tag across the import ("Markup" on
    # one post and "markup" on another would make two pages at one address)
    for my $pair (grep { $_->[0] eq 'categories' or $_->[0] eq 'tags' } @$front) {
        next unless ref $pair->[1] eq 'ARRAY';
        my $spelling = $state->{spelling}->{$pair->[0]} ||= {};
        my %seen;
        $pair->[1] = [ grep { !$seen{lc $_}++ }
                       map { my $key = lc App::Dapper::Utils::slugify($_); $spelling->{$key} = $_ unless defined $spelling->{$key}; $spelling->{$key} }
                       grep { defined and !ref } @{$pair->[1]} ];
    }

    my %front = map { $_->[0] => $_->[1] } @$front;
    push @{$state->{pages}}, { file => $file, kind => $kind || 'page', draft => $front{draft} ? 1 : 0 };
    return if $state->{dry_run};

    App::Dapper::Utils::write_file($file, "---\n" . front_matter($front) . "---\n" . $body);
}

# fit_schema(state, file, \@pairs) - Make an imported page's front matter fit
# the _schema.yml of the folder it lands in, so the site still builds: a list
# keeps only the values the schema allows (categories it doesn't allow become
# tags where tags are free), a required list that ends up empty gets the
# first allowed value (so a post in a blog starter is in "blog"), a required
# title that is missing becomes "Untitled", and text that is too long is
# shortened. Each change is noted for the report.
sub fit_schema {
    my ($state, $file, $pairs) = @_;

    my $schema = eval { App::Dapper::Schema::for_file($state->{source}, $file) } or return;
    my $fields = $schema->{fields} || {};
    my %required = map { $_ => 1 } @{$schema->{required} || []};
    my %index = map { $pairs->[$_]->[0] => $_ } 0 .. $#$pairs;
    my $get = sub { my ($key) = @_; defined $index{$key} ? $pairs->[$index{$key}]->[1] : undef };
    my $set = sub {
        my ($key, $value) = @_;
        if (defined $index{$key}) { $pairs->[$index{$key}]->[1] = $value }
        else { push @$pairs, [ $key => $value ]; $index{$key} = $#$pairs }
    };
    my $schema_file = 'its folder\'s _schema.yml';

    # Free tags: the schema lists "tags" as a list without fixed values, or
    # doesn't list it but allows other fields
    my $tag_rules = $fields->{tags};
    my $tags_free = $tag_rules ? ($tag_rules->{type} eq 'list' && !$tag_rules->{values})
                               : $schema->{additional};

    for my $key (sort keys %$fields) {
        my $rules = $fields->{$key};
        next unless $rules->{type} eq 'list' and $rules->{values};
        my $value = $get->($key);
        my @items = ref $value eq 'ARRAY' ? @$value : defined $value && length $value ? ($value) : ();
        my %allowed = map { $_ => 1 } @{$rules->{values}};
        my @kept = grep { $allowed{$_} } @items;
        my @left = grep { !$allowed{$_} } @items;
        if (@left) {
            if ($key eq 'categories' and $tags_free) {
                # A category that is already a tag (in any case) isn't added twice
                my %has = map { lc($_) => 1 } @{ $get->('tags') || [] };
                $set->(tags => [ @{ $get->('tags') || [] }, grep { !$has{lc $_}++ } @left ]);
                note($state, "categories $schema_file doesn't allow, kept as tags", $file);
            }
            else {
                note($state, "values of \"$key\" $schema_file doesn't allow, left out", $file);
            }
        }
        if (not @kept and $required{$key}) {
            @kept = ($rules->{values}->[0]);
            note($state, "pages given \"$key: $kept[0]\", which $schema_file requires", $file) unless @items;
        }
        $set->($key => \@kept);
    }

    if ($required{title}) {
        my $title = $get->('title');
        if (not defined $title or ref $title or not length $title) {
            $set->(title => 'Untitled');
            note($state, 'pages without a title, now called "Untitled"', $file);
        }
    }

    for my $key (sort keys %$fields) {
        my $max = $fields->{$key}->{max_length};
        my $value = $get->($key);
        next unless defined $max and defined $value and !ref $value and length $value > $max;
        my $short = substr($value, 0, $max - 1);
        $short =~ s/\s+\S*\z// if $short =~ /\s/;
        $set->($key => "$short\x{2026}");
        note($state, "\"$key\" shortened to the $max characters $schema_file allows", $file);
    }
}

# front_matter(\@pairs) - YAML for front matter, in the order given, leaving
# out empty values.
sub front_matter {
    my ($pairs) = @_;

    my $yaml = YAML::PP->new(header => 0);
    my $out = '';
    for my $pair (@$pairs) {
        my ($key, $value) = @$pair;
        next unless defined $value;
        next if ref $value eq 'ARRAY' and not @$value;
        next if !ref $value and not length $value;
        if ($key eq 'draft') {
            $out .= "draft: true\n" if $value;
            next;
        }
        $out .= $yaml->dump_string({ $key => $value });
    }
    return $out;
}

# copy_files(state, from, to) - Copy a file or directory into the project,
# skipping files that are already there.
sub copy_files {
    my ($state, $from, $to) = @_;

    if (-d $from) {
        for my $entry (App::Dapper::Utils::read_dir($from)) {
            next if $entry =~ /^\./;
            copy_files($state, "$from/$entry", "$to/$entry");
        }
        return;
    }
    return unless -f $from;
    if (-e $to) {
        push @{$state->{skipped}}, $to;
        return;
    }
    $state->{copied}++;
    return if $state->{dry_run};
    App::Dapper::Utils::create_dir(dirname($to)) unless -d dirname($to);
    App::Dapper::Utils::copy_recursive($from, $to);
}

# note(state, message) - Remember something to tell the user, once per page.
sub note {
    my ($state, $message, $file) = @_;
    push @{$state->{notes}->{$message}}, $file;
}

sub write_redirects {
    my ($state) = @_;

    my %new = %{$state->{redirects}};
    return unless %new;

    my $file = catfile($state->{dapper}->{data_dir}, 'redirects.yml');
    my $existing = -f $file ? YAML::PP::LoadFile($file) : {};
    $existing = {} unless ref $existing eq 'HASH';
    my $added = 0;
    for my $from (sort keys %new) {
        next if exists $existing->{$from};
        $existing->{$from} = $new{$from};
        $added++;
    }
    $state->{redirects_added} = $added;
    return if $state->{dry_run} or not $added;
    App::Dapper::Utils::write_file($file, YAML::PP->new(header => 0)->dump_string($existing));
}

sub report {
    my ($state) = @_;

    my $dapper = $state->{dapper};
    my @pages = @{$state->{pages}};
    my $posts  = grep { $_->{kind} eq 'post' } @pages;
    my $drafts = grep { $_->{draft} } @pages;
    my $verb = $state->{dry_run} ? 'Would import' : 'Imported';

    $dapper->_log("$verb $posts post" . ($posts == 1 ? '' : 's') . " and " . (@pages - $posts) . " page"
        . (@pages - $posts == 1 ? '' : 's') . " into $state->{source}" . ($drafts ? " ($drafts as drafts)" : '') . ".");
    $dapper->_log(($state->{dry_run} ? 'Would copy' : 'Copied') . " $state->{copied} other file" . ($state->{copied} == 1 ? '' : 's') . ".")
        if $state->{copied};
    $dapper->_log(($state->{dry_run} ? 'Would add' : 'Added') . " $state->{redirects_added} redirect"
        . ($state->{redirects_added} == 1 ? '' : 's') . " to " . catfile($dapper->{data_dir}, 'redirects.yml') . ".")
        if $state->{redirects_added};

    if (my @skipped = @{$state->{skipped}}) {
        $dapper->_log("Left alone " . scalar(@skipped) . " file" . (@skipped == 1 ? '' : 's') . " that already exist:");
        $dapper->_log("  $_") for @skipped[0 .. ($#skipped < 9 ? $#skipped : 9)];
        $dapper->_log("  ...") if @skipped > 10;
    }

    for my $message (sort keys %{$state->{notes}}) {
        my %seen;
        my @files = grep { defined and !$seen{$_}++ } @{$state->{notes}->{$message}};
        $dapper->_log("Check: $message" . (@files ? " (" . scalar(@files) . " page" . (@files == 1 ? '' : 's') . ", such as $files[0])" : ''));
    }

    $dapper->_log("Run \"dapper check\" to find links that need fixing.") if @pages and not $state->{dry_run};
}

# --- Helpers ---------------------------------------------------------------

sub decode_entities {
    my ($text) = @_;
    return '' unless defined $text;
    $text =~ s/&lt;/</g;
    $text =~ s/&gt;/>/g;
    $text =~ s/&quot;/"/g;
    $text =~ s/&#0*39;|&apos;/'/g;
    $text =~ s/&#(\d+);/chr($1)/ge;
    $text =~ s/&#x([0-9a-f]+);/chr(hex $1)/gie;
    $text =~ s/&amp;/&/g;
    return $text;
}

sub strip_tags {
    my ($html) = @_;
    $html = '' unless defined $html;
    $html =~ s/<[^>]*>//g;
    $html = decode_entities($html);
    $html =~ s/\s+/ /g;
    $html =~ s/^ | $//g;
    return $html;
}

# url_path(url) - The path of a URL: https://example.com/a/b/?x=1 is /a/b/.
# decode_path(text) - Percent-encoded letters outside ASCII (as WordPress
# writes "επίπεδο") back to the letters; encoded ASCII such as %2F is left as
# it is, since decoding it would change what the address means.
sub decode_path {
    my ($text) = @_;
    return $text unless defined $text and $text =~ /%[89A-Fa-f][0-9A-Fa-f]/;
    my $bytes = $text =~ /[^\x00-\x7F]/ ? Encode::encode('UTF-8', $text) : $text;
    $bytes =~ s/%([89A-Fa-f][0-9A-Fa-f])/chr hex $1/ge;
    my $decoded = eval { Encode::decode('UTF-8', $bytes, Encode::FB_CROAK()) };
    return defined $decoded ? $decoded : $text;
}

sub url_path {
    my ($url) = @_;
    return unless defined $url and length $url;
    $url =~ s{^[a-z]+://[^/]+}{}i;
    $url =~ s/[?#].*$//;
    $url =~ s{/{2,}}{/}g;
    $url = decode_path($url);
    $url = "/$url" unless $url =~ m{^/};
    return $url;
}

# date_string(text) - A date as YYYY-MM-DDTHH:MM:SS, or nothing.
sub date_string {
    my ($date) = @_;
    return unless defined $date;
    $date = "$date";
    return if $date =~ /^0000-/;
    # Jekyll writes "2019-12-31 23:00:00 +0100"
    $date =~ s/^(\d{4}-\d\d-\d\d)[ T](\d\d:\d\d(?::\d\d)?)\s*([+-]\d\d):?(\d\d)$/$1T$2$3:$4/;
    my $parsed = eval { App::Dapper::Utils::parse_date($date) } or return;
    my $out = $parsed->strftime('%Y-%m-%dT%H:%M:%S');
    if (not $parsed->time_zone->is_floating) {
        my $offset = $parsed->strftime('%z');
        $offset =~ s/(\d\d)$/:$1/;
        $out .= $offset eq '+00:00' && $date =~ /Z$/ ? 'Z' : $offset;
    }
    return $out;
}

sub list {
    my ($value) = @_;
    return [] unless defined $value;
    return [ grep { defined and length } @$value ] if ref $value eq 'ARRAY';
    return [ grep { length } split /\s*,\s*|\s+/, $value ] if !ref $value;
    return [];
}

sub layout_for {
    my ($state, $name) = @_;
    return defined $name && $state->{layouts}->{$name} ? $name : undef;
}

# video(url) - The HTML for a YouTube or Vimeo address, or nothing.
sub video {
    my ($url) = @_;
    for my $site (qw/ youtube vimeo /) {
        next unless $url =~ ($site eq 'youtube' ? qr{youtu\.?be} : qr{vimeo\.com});
        my $id = App::Dapper::Components::video_id($site, $url) or next;
        return App::Dapper::Components::built_in($site, [$id], '');
    }
    return;
}

# --- WordPress -------------------------------------------------------------

sub wordpress {
    my ($state, $from) = @_;

    die "error: give the WordPress export file (Tools, Export in WordPress), not a directory\n" if -d $from;
    my $xml = App::Dapper::Utils::read_file($from);
    die "error: $from is not a WordPress export file\n" unless $xml =~ /<rss\b/ and $xml =~ /<wp:/;

    my $cdata = sub {
        my ($text) = @_;
        return undef unless defined $text;
        return $text =~ /^\s*<!\[CDATA\[(.*)\]\]>\s*$/s ? $1 : decode_entities($text);
    };

    my $layout = layout_for($state, 'post');

    while ($xml =~ m{<item>(.*?)</item>}gs) {
        my $item = $1;
        my $get = sub {
            my ($tag) = @_;
            return $item =~ m{<\Q$tag\E>(.*?)</\Q$tag\E>}s ? $cdata->($1) : undef;
        };

        my $type = $get->('wp:post_type') || 'post';
        next unless $type eq 'post' or $type eq 'page';
        my $status = $get->('wp:status') || 'publish';
        next if $status =~ /^(?:trash|auto-draft|inherit)$/;

        my $title = $get->('title');
        $title = '' unless defined $title;
        my $slug = decode_path($get->('wp:post_name'));
        $slug = App::Dapper::Utils::slugify($title) unless defined $slug and length $slug;
        $slug = 'post-' . ($get->('wp:post_id') || scalar @{$state->{pages}}) unless defined $slug and length $slug;

        my (@categories, @tags);
        while ($item =~ m{<category\s+domain="(category|post_tag)"[^>]*>(.*?)</category>}gs) {
            # WordPress keeps names escaped, even in CDATA
            my $name = decode_entities($cdata->($2));
            next if $1 eq 'category' and $name eq 'Uncategorized';
            push @{ $1 eq 'category' ? \@categories : \@tags }, $name;
        }

        my $draft = $status =~ /^(?:draft|pending|private)$/ ? 1 : 0;
        # A link like /?p=5 only means "post 5"; the post has no address of its own
        my $raw_link = $get->('link');
        my $link = defined $raw_link && $raw_link !~ /[?&](?:p|page_id)=/ ? url_path($raw_link) : undef;
        my $urlpattern = !$draft && defined $link ? $link : undef;

        # WordPress's "posts page" only holds the list of posts; where the
        # project makes a page per category, the blog's own list page is at
        # that address already
        if ($type eq 'page' and defined $urlpattern and $urlpattern eq "/$state->{to}/"
            and $state->{dapper}->{site}->{category_pages}
            and App::Dapper::Publish::enabled($state->{dapper}->{site}, 'category_pages')) {
            note($state, "pages at the address of the list of posts (/$state->{to}/), left out since the project makes that list", "$slug.html");
            next;
        }

        my $path = $type eq 'post' ? "$state->{to}/$slug.html" : "$slug.html";
        my $body = wordpress_html($state, $get->('content:encoded'), $path);
        my $excerpt = strip_tags($get->('excerpt:encoded'));

        add_page($state, $path, [
            [ title       => $title ],
            [ date        => date_string($get->('wp:post_date')) ],
            [ layout      => $type eq 'post' ? $layout : undef ],
            [ categories  => \@categories ],
            [ tags        => \@tags ],
            [ description => $excerpt ],
            [ urlpattern  => $urlpattern ],
            [ draft       => $draft ],
        ], $body, $type);
    }
}

# wordpress_html(state, html, path) - WordPress content as plain HTML:
# paragraphs added where WordPress would add them, block comments removed,
# and [caption] and [embed] converted.
sub wordpress_html {
    my ($state, $html, $path) = @_;

    $html = '' unless defined $html;
    $html =~ s/<!--\s*\/?wp:.*?-->\n?//gs;

    # Without the block editor, WordPress adds paragraphs when it shows a post
    my $classic = $html !~ m{<(?:p|div|h[1-6]|ul|ol|figure|blockquote|table|pre|section)\b}i;

    # [embed]URL[/embed], and a video's address on a line of its own
    $html =~ s{\[embed[^\]]*\](.*?)\[/embed\]}{video($1) || $1}ge;
    $html =~ s{^[ \t]*(https?://\S+)[ \t]*$}{video($1) || $1}gme;

    $html =~ s{\[caption[^\]]*\](.*?)\[/caption\]}{
        my $inner = $1;
        my ($image) = $inner =~ /(<a\b[^>]*>\s*<img\b[^>]*>\s*<\/a>|<img\b[^>]*>)/s;
        my $caption = $inner;
        $caption =~ s/\Q$image\E// if defined $image;
        $caption =~ s/^\s+|\s+$//g;
        defined $image ? "<figure>$image<figcaption>$caption</figcaption></figure>" : $inner;
    }gse;

    if ($classic) {
        my @blocks = grep { /\S/ } split /\n\s*\n/, $html;
        $html = join("\n\n", map {
            my $block = $_;
            $block =~ s/^\s+|\s+$//g;
            $block =~ /^<(?:iframe|div|figure)\b/ ? $block : do { $block =~ s/\n/<br>\n/g; "<p>$block</p>" }
        } @blocks);
    }

    my %shortcodes;
    $shortcodes{$1}++ while $html =~ /\[([A-Za-z][\w-]*)(?:\s[^\]]*)?\]/g;
    note($state, "WordPress shortcodes that were left as text: " . join(', ', map { "[$_]" } sort keys %shortcodes), "$state->{source}/$path")
        if %shortcodes;
    note($state, 'images that still load from the old WordPress site (wp-content/uploads); copy them into the site', "$state->{source}/$path")
        if $html =~ m{wp-content/uploads};

    $html .= "\n" unless $html =~ /\n$/;
    return $html;
}

# --- Jekyll ----------------------------------------------------------------

my %JEKYLL_STYLES = (
    date    => '/:categories/:year/:month/:day/:title:output_ext',
    pretty  => '/:categories/:year/:month/:day/:title/',
    ordinal => '/:categories/:year/:y_day/:title:output_ext',
    none    => '/:categories/:title:output_ext',
);

sub jekyll {
    my ($state, $from) = @_;

    die "error: give the Jekyll site's directory\n" unless -d $from;
    my $config = -f "$from/_config.yml" ? (eval { YAML::PP::LoadFile("$from/_config.yml") } || {}) : {};
    $config = {} unless ref $config eq 'HASH';
    my $permalink = defined $config->{permalink} ? $config->{permalink} : 'date';
    $permalink = $JEKYLL_STYLES{$permalink} if $JEKYLL_STYLES{$permalink};

    my @items;

    # Posts and drafts
    for my $dir (qw/ _posts _drafts /) {
        next unless -d "$from/$dir";
        File::Find::find({ no_chdir => 1, wanted => sub {
            return unless -f $_ and /\.(?:md|markdown|mkd|html)$/i;
            my $name = basename($_);
            my ($date, $slug, $ext) = $name =~ /^(\d{4}-\d{2}-\d{2})-(.+)\.(\w+)$/;
            if ($dir eq '_drafts') { ($slug, $ext) = $name =~ /^(.+)\.(\w+)$/ unless defined $slug }
            return unless defined $slug;
            push @items, { file => $_, kind => 'post', date => $date, slug => $slug, ext => $ext, draft => $dir eq '_drafts' };
        } }, "$from/$dir");
    }

    # Pages: files with front matter outside the folders Jekyll keeps to itself
    File::Find::find({ no_chdir => 1, wanted => sub {
        my $rel = length($_) > length($from) ? substr($_, length($from) + 1) : '';
        if (-d $_) {
            $File::Find::prune = 1 if $rel =~ m{(?:^|/)[_.]} or $rel =~ m{^(?:node_modules|vendor|assets|images|img|css|js|scss|sass|files|uploads)$};
            return;
        }
        return unless /\.(?:md|markdown|mkd|html)$/i and App::Dapper::Utils::has_frontmatter($_);
        return if $rel =~ m{^(?:README|LICENSE|CHANGELOG)\b}i;
        my ($stem, $ext) = $rel =~ /^(.+)\.(\w+)$/;
        push @items, { file => $_, kind => 'page', rel => $stem, ext => $ext };
    } }, $from);

    # Work out every post's address first, for {% post_url %}
    my %post_url;
    for my $item (@items) {
        my $text = App::Dapper::Utils::read_file($item->{file});
        my ($front, $body) = App::Dapper::Utils::split_frontmatter($text, $item->{file});
        # A post without front matter is all body
        $body = $text unless defined $front;
        $item->{front} = ref $front eq 'HASH' ? $front : {};
        $item->{body} = defined $body ? $body : '';
        my $f = $item->{front};
        # YAML reads published: false as an empty string
        $item->{draft} = 1 if defined $f->{published} and (!$f->{published} or $f->{published} =~ /^(?:false|no)$/i);
        $item->{date_string} = date_string($f->{date});
        $item->{date_string} = date_string($item->{date}) unless defined $item->{date_string};

        if (defined $f->{permalink}) {
            $item->{url} = jekyll_url($f->{permalink}, $item, $f);
        }
        elsif ($item->{kind} eq 'post' and not $item->{draft}) {
            $item->{url} = jekyll_url($permalink, $item, $f);
        }
        if ($item->{kind} eq 'post' and defined $item->{date}) {
            (my $key = basename($item->{file})) =~ s/\.\w+$//;
            $post_url{$key} = $item->{url};
        }
    }

    my $post_layout = layout_for($state, 'post');
    for my $item (@items) {
        my $f = $item->{front};
        my $markdown = $item->{ext} =~ /^(?:md|markdown|mkd)$/i;
        my $ext = $markdown ? 'md' : 'html';
        my $path = $item->{kind} eq 'post' ? "$state->{to}/$item->{slug}.$ext" : "$item->{rel}.$ext";
        my $body = jekyll_body($state, $item->{body}, $markdown, \%post_url, $config, "$state->{source}/$path");

        my @categories = @{ jekyll_categories($f) };
        my %done = map { $_ => 1 } qw/ title date layout categories category tags permalink published description excerpt draft /;
        my @rest = map { [ $_ => $f->{$_} ] } grep { !$done{$_} } sort keys %$f;

        add_page($state, $path, [
            [ title       => defined $f->{title} ? $f->{title} : undef ],
            [ date        => $item->{date_string} ],
            [ layout      => layout_for($state, $f->{layout}) || ($item->{kind} eq 'post' ? $post_layout : undef) ],
            [ categories  => \@categories ],
            [ tags        => list($f->{tags}) ],
            [ description => defined $f->{description} ? $f->{description} : $f->{excerpt} ],
            [ urlpattern  => $item->{url} ],
            @rest,
            [ draft       => $item->{draft} ],
        ], $body, $item->{kind});
    }

    for my $dir (qw/ assets images img css js files uploads fonts /) {
        copy_files($state, "$from/$dir", $dir) if -d "$from/$dir";
    }
    copy_files($state, "$from/favicon.ico", "favicon.ico") if -f "$from/favicon.ico";
}

# jekyll_categories(front matter) - A page's categories as Jekyll reads them:
# "categories" is a list (or words separated by spaces), and "category" is one.
sub jekyll_categories {
    my ($front) = @_;
    return list($front->{categories}) if defined $front->{categories};
    return defined $front->{category} && !ref $front->{category} && length $front->{category}
        ? [ $front->{category} ] : list($front->{category});
}

# jekyll_url(pattern, item, front matter) - The address Jekyll gives a page.
sub jekyll_url {
    my ($pattern, $item, $front) = @_;

    my $date = eval { App::Dapper::Utils::parse_date($item->{date_string}) } if defined $item->{date_string};
    my @categories = map { App::Dapper::Utils::slugify($_) } @{ jekyll_categories($front) };
    my $title = defined $item->{slug} ? $item->{slug} : basename($item->{rel} || '');
    my %token = (
        categories => join('/', @categories),
        title      => defined $front->{slug} ? $front->{slug} : $title,
        slug       => defined $front->{slug} ? $front->{slug} : $title,
        output_ext => '.html',
        path       => $item->{rel} || '',
    );
    if ($date) {
        %token = (%token,
            year => $date->strftime('%Y'), month => $date->strftime('%m'), day => $date->strftime('%d'),
            i_month => $date->month, i_day => $date->day, short_year => $date->strftime('%y'),
            y_day => $date->strftime('%j'), hour => $date->strftime('%H'), minute => $date->strftime('%M'),
            second => $date->strftime('%S'));
    }

    my $url = $pattern;
    $url =~ s/:(categories|output_ext|short_year|i_month|i_day|y_day|year|month|day|hour|minute|second|title|slug|path)\b/defined $token{$1} ? $token{$1} : ''/ge;
    $url =~ s{/{2,}}{/}g;
    $url = "/$url" unless $url =~ m{^/};
    return $url;
}

# jekyll_body(state, text, markdown?, \%post_url, config, file) - Replace the
# Liquid Dapper can do without.
sub jekyll_body {
    my ($state, $body, $markdown, $post_url, $config, $file) = @_;

    $body =~ s/\{%-?\s*raw\s*-?%\}|\{%-?\s*endraw\s*-?%\}//g;
    if ($markdown) {
        $body =~ s{\{%-?\s*highlight\s+(\w+)[^%]*%\}\n?(.*?)\n?\{%-?\s*endhighlight\s*-?%\}}{```$1\n$2\n```}gs;
    }
    else {
        $body =~ s{\{%-?\s*highlight\s+(\w+)[^%]*%\}\n?(.*?)\n?\{%-?\s*endhighlight\s*-?%\}}{
            my ($lang, $code) = ($1, $2);
            $code =~ s/&/&amp;/g; $code =~ s/</&lt;/g; $code =~ s/>/&gt;/g;
            qq{<pre><code class="language-$lang">$code</code></pre>}
        }gse;
    }
    $body =~ s/\{\{-?\s*site\.(?:baseurl|url)\s*-?\}\}//g;
    $body =~ s/\{\{-?\s*(["'])(.*?)\1\s*\|\s*(?:relative_url|absolute_url)\s*-?\}\}/$2/g;
    $body =~ s{\{%-?\s*post_url\s+(\S+)\s*-?%\}}{
        my $given = $1;
        (my $key = $given) =~ s{^.*/}{};
        defined $post_url->{$key} ? $post_url->{$key} : do { note($state, "post_url links to posts that weren't found", $file); "{% post_url $given %}" }
    }ge;

    note($state, 'Liquid tags Dapper does not run ({{ ... }} or {% ... %}); replace them, or set template: true and use Dapper template code', $file)
        if $body =~ /\{\{.*?\}\}|\{%.*?%\}/s;
    return $body;
}

# --- Hugo ------------------------------------------------------------------

sub hugo {
    my ($state, $from) = @_;

    die "error: give the Hugo site's directory\n" unless -d $from;
    my $content = "$from/content";
    die "error: $from has no content directory, so it doesn't look like a Hugo site\n" unless -d $content;

    my $config = {};
    for my $name (qw/ hugo.toml hugo.yaml hugo.yml hugo.json config.toml config.yaml config.yml config.json /) {
        my $file = "$from/$name";
        next unless -f $file;
        my $text = App::Dapper::Utils::read_file($file);
        $config = $name =~ /\.toml$/ ? toml($text) : $name =~ /\.json$/ ? JSON->new->decode($text) : YAML::PP::Load($text);
        last;
    }
    my $permalinks = ref $config->{permalinks} eq 'HASH' ? $config->{permalinks} : {};

    my $post_layout = layout_for($state, 'post');
    my @files;
    File::Find::find({ no_chdir => 1, wanted => sub { push @files, $_ if -f $_ and /\.(?:md|markdown|html)$/i } }, $content);

    for my $file (sort @files) {
        my $rel = substr($file, length($content) + 1);
        my $name = basename($rel);

        # In a page bundle (a folder with an index.md), other Markdown files
        # are the page's resources, not pages
        if ($name !~ /^_?index\./ and grep { -f catfile(dirname($file), "index.$_") } qw/ md markdown html /) {
            note($state, 'Markdown files inside page bundles were left out (Hugo treats them as resources, not pages)', $file);
            next;
        }
        if ($name =~ /^_index\./) {
            note($state, 'Hugo section pages (_index.md) were not imported; Dapper lists pages with paginate', $file);
            next;
        }

        my ($front, $body) = hugo_front_matter(App::Dapper::Utils::read_file($file), $file);
        my $bundle = $name =~ /^index\./;
        (my $stem = $rel) =~ s/\.\w+$//;
        $stem =~ s{/index$}{} if $bundle;
        my ($ext) = $name =~ /\.(\w+)$/;
        $ext = lc $ext eq 'html' ? 'html' : 'md';

        my @dirs = split m{/}, $stem;
        my $leaf = pop @dirs;
        my $section = @dirs ? $dirs[0] : '';
        my $slug = defined $front->{slug} ? $front->{slug} : $leaf;
        my $url = defined $front->{url} ? $front->{url} : undef;
        if (not defined $url and defined $permalinks->{$section}) {
            $url = hugo_url($permalinks->{$section}, $front, $section, $slug, $leaf);
        }
        $url = '/' . join('/', @dirs, $slug) . '/' unless defined $url;

        for my $alias (@{ list($front->{aliases}) }) {
            $state->{redirects}->{ $alias =~ m{^/} ? $alias : "/$alias" } = $url;
        }

        my $path = $bundle ? "$stem/index.$ext" : "$stem.$ext";
        my %done = map { $_ => 1 } qw/ title date publishDate publishdate lastmod layout type categories tags draft url slug aliases description summary weight /;
        my @rest = map { [ $_ => $front->{$_} ] } grep { !$done{$_} } sort keys %$front;
        my $date = defined $front->{date} ? $front->{date} : $front->{publishDate} || $front->{publishdate};

        add_page($state, $path, [
            [ title       => $front->{title} ],
            [ date        => date_string($date) ],
            [ layout      => layout_for($state, $front->{layout}) || (@{ list($front->{categories}) } || $section =~ /^(?:posts?|blog)$/ ? $post_layout : undef) ],
            [ categories  => list($front->{categories}) ],
            [ tags        => list($front->{tags}) ],
            [ description => defined $front->{description} ? $front->{description} : $front->{summary} ],
            [ urlpattern  => $url ],
            @rest,
            [ draft       => $front->{draft} && $front->{draft} !~ /^(?:false|0)$/i ? 1 : 0 ],
        ], hugo_body($state, $body, "$state->{source}/$path"), $section =~ /^(?:posts?|blog)$/ ? 'post' : 'page');

        # The other files in a page bundle go with it
        if ($bundle) {
            my $dir = dirname($file);
            for my $entry (App::Dapper::Utils::read_dir($dir)) {
                next if $entry =~ /^\./ or $entry =~ /\.(?:md|markdown)$/i or -d "$dir/$entry";
                copy_files($state, "$dir/$entry", "$state->{source}/$stem/$entry");
            }
        }
    }

    copy_files($state, "$from/static", $state->{source}) if -d "$from/static";
}

sub hugo_url {
    my ($pattern, $front, $section, $slug, $leaf) = @_;

    my $date = defined $front->{date} ? eval { App::Dapper::Utils::parse_date($front->{date}) } : undef;
    my $title = App::Dapper::Utils::slugify($front->{title});
    my %token = (
        section  => $section,
        slug     => $slug,
        title    => defined $title && length $title ? $title : $slug,
        filename => $leaf,
        contentbasename => $leaf,
    );
    %token = (%token, year => $date->strftime('%Y'), month => $date->strftime('%m'), day => $date->strftime('%d'),
              yearday => $date->strftime('%j'), monthname => lc $date->strftime('%B')) if $date;

    my $url = $pattern;
    $url =~ s/:(contentbasename|monthname|yearday|section|filename|title|slug|year|month|day)\b/defined $token{$1} ? $token{$1} : ''/ge;
    $url =~ s{/{2,}}{/}g;
    $url = "/$url" unless $url =~ m{^/};
    return $url;
}

# hugo_front_matter(text, file) - The front matter (YAML, TOML or JSON) and
# the body of a Hugo page.
sub hugo_front_matter {
    my ($text, $file) = @_;

    if ($text =~ /\A\+\+\+[ \t]*\r?\n(.*?)^\+\+\+[ \t]*\r?\n?(.*)\z/ms) {
        return (toml($1), $2);
    }
    if ($text =~ /\A---[ \t]*\r?\n(.*?)^---[ \t]*\r?\n?(.*)\z/ms) {
        my ($yaml, $body) = ($1, $2);
        my $front = eval { YAML::PP::Load($yaml) };
        die "error: could not read the front matter of $file: $@" unless ref $front eq 'HASH' or !length $yaml;
        return ($front || {}, $body);
    }
    if ($text =~ /\A\s*\{/) {
        my $json = JSON->new;
        my ($front, $length) = eval { $json->decode_prefix($text) };
        return ($front, substr($text, $length)) if ref $front eq 'HASH';
    }
    return ({}, $text);
}

# hugo_body(state, text, file) - Replace the shortcodes Dapper has components for.
sub hugo_body {
    my ($state, $body, $file) = @_;

    my $args = sub {
        my ($text) = @_;
        my %named;
        while ($text =~ /(\w+)=(?:"((?:[^"\\]|\\.)*)"|(\S+))/g) {
            my ($key, $value) = ($1, defined $2 ? $2 : $3);
            $value =~ s/\\(["\\])/$1/g;
            $named{$key} = $value;
        }
        (my $positional = $text) =~ s/\w+=(?:"(?:[^"\\]|\\.)*"|\S+)//g;
        my @list = App::Dapper::Components::parse_args($positional);
        return (\%named, \@list);
    };
    my $quote = sub { my $t = shift; $t =~ s/"/'/g; qq{"$t"} };

    $body =~ s{\{\{[<%]\s*(youtube|vimeo)\s+(.*?)\s*[>%]\}\}}{
        my ($whole, $kind, $text) = ($&, $1, $2);
        my ($named, $list) = $args->($text);
        my $id = $named->{id} || $list->[0];
        defined $id ? "::: $kind $id" . (defined $named->{title} ? ' ' . $quote->($named->{title}) : '') : $whole
    }ge;
    $body =~ s{\{\{[<%]\s*figure\s+(.*?)\s*/?[>%]\}\}}{
        my ($whole, $text) = ($&, $1);
        my ($named) = $args->($text);
        my $src = $named->{src};
        my $alt = defined $named->{alt} ? $named->{alt} : defined $named->{title} ? $named->{title} : '';
        defined $src
            ? "::: figure $src " . $quote->($alt) . (defined $named->{caption} ? ' ' . $quote->($named->{caption}) : '')
            : $whole
    }ge;
    $body =~ s{\{\{[<%]\s*(?:rel)?ref\s+"([^"]+)"\s*[>%]\}\}}{
        my $target = $1;
        $target =~ s{\.md$}{};
        $target =~ s{(?:^|/)index$}{};
        $target =~ s{^/+}{};
        length $target ? "/$target/" : '/'
    }ge;

    my %shortcodes;
    $shortcodes{$1}++ while $body =~ /\{\{[<%]\s*\/?(\w[\w-]*)/g;
    note($state, "Hugo shortcodes that were left as they are: " . join(', ', sort keys %shortcodes), $file) if %shortcodes;

    return $body;
}

=head2 toml

Takes TOML text and returns it as a hash reference. It reads what front
matter and Hugo's settings use: keys (including dotted keys) and values
(text with escapes, multi-line text, numbers, true and false, dates, and
lists, including lists of lists), tables (C<[params]>) and comments. Numbers
and dates are kept as they are written. Inline tables are kept as text, and
an array of tables (C<[[menu]]>) is read as one table.

=cut

sub toml {
    my ($text) = @_;

    my %data;
    my $table = \%data;
    my @lines = split /\r?\n/, $text;

    while (defined(my $line = shift @lines)) {
        my $plain = _toml_strip($line);
        next if $plain eq '';

        if ($plain =~ /^\[\[?\s*([^\]]+?)\s*\]\]?$/) {
            $table = \%data;
            for my $part (split /\./, $1) {
                $part =~ s/^\s*["']|["']\s*$//g;
                $part =~ s/^\s+|\s+$//g;
                $table = $table->{$part} = ref $table->{$part} eq 'HASH' ? $table->{$part} : {};
            }
            next;
        }

        my ($key, $value) = $plain =~ /^((?:"[^"]*"|'[^']*'|[\w-]+)(?:\s*\.\s*(?:"[^"]*"|'[^']*'|[\w-]+))*)\s*=\s*(.*)$/
            or next;

        # Text over several lines, between """ or '''
        if ($value =~ /^("""|''')/) {
            my $quote = $1;
            my ($raw) = $line =~ /=\s*\Q$quote\E(.*)$/;
            $raw = '' unless defined $raw;
            until ($raw =~ /\Q$quote\E/ or not @lines) {
                $raw .= "\n" . shift @lines;
            }
            $raw =~ s/\Q$quote\E.*\z//s;
            $raw =~ s/^\n//;
            $value = $quote eq '"""' ? _toml_unescape($raw) : $raw;
        }
        else {
            # A list can go over several lines
            while ($value =~ /^\[/ and _brackets($value) > 0 and @lines) {
                my $next = _toml_strip(shift @lines);
                $value .= " $next" if length $next;
            }
            $value = _toml_value($value);
        }

        # A dotted key (a.b = 1) puts the value in a table
        my @parts = $key =~ /("[^"]*"|'[^']*'|[\w-]+)/g;
        s/^["']|["']$//g for @parts;
        my $last = pop @parts;
        my $target = $table;
        $target = $target->{$_} = ref $target->{$_} eq 'HASH' ? $target->{$_} : {} for @parts;
        $target->{$last} = $value;
    }

    return \%data;
}

# _toml_strip(line) - The line without its comment and the spaces around it.
sub _toml_strip {
    my ($line) = @_;

    my ($out, $quote) = ('', '');
    for (my $i = 0; $i < length $line; $i++) {
        my $c = substr($line, $i, 1);
        if ($quote) {
            $out .= $c;
            if ($quote eq '"' and $c eq '\\') { $out .= substr($line, ++$i, 1); next }
            $quote = '' if $c eq $quote;
            next;
        }
        last if $c eq '#';
        $quote = $c if $c eq '"' or $c eq "'";
        $out .= $c;
    }
    $out =~ s/^\s+|\s+$//g;
    return $out;
}

sub _brackets {
    my ($text) = @_;
    (my $plain = $text) =~ s/"(?:[^"\\]|\\.)*"|'[^']*'//g;
    return ($plain =~ tr/[//) - ($plain =~ tr/]//);
}

sub _toml_unescape {
    my ($s) = @_;
    my %simple = (n => "\n", t => "\t", r => "\r", b => "\b", f => "\f", '"' => '"', '\\' => '\\');
    $s =~ s/\\(?:u([0-9A-Fa-f]{4})|U([0-9A-Fa-f]{8})|(.))/
        defined $1 ? chr(hex $1) : defined $2 ? chr(hex $2) : exists $simple{$3} ? $simple{$3} : "\\$3"/gse;
    return $s;
}

# _toml_value(text) - A value; text that can't be read is kept as it is.
sub _toml_value {
    my ($text) = @_;

    my $pos = 0;
    my $value = _toml_parse($text, \$pos);
    return $text unless defined $value;
    return $text if substr($text, $pos) =~ /\S/;
    return $$value;
}

# _toml_parse(text, \pos) - Reads one value from the text at pos, and returns
# a reference to it, or nothing if it can't.
sub _toml_parse {
    my ($text, $pos) = @_;

    pos($text) = $$pos;
    $text =~ /\G\s*/gc;

    if ($text =~ /\G"((?:[^"\\]|\\.)*)"/gc) {
        $$pos = pos($text);
        my $s = _toml_unescape($1);
        return \$s;
    }
    if ($text =~ /\G'([^']*)'/gc) {
        $$pos = pos($text);
        my $s = $1;
        return \$s;
    }
    if ($text =~ /\G\[/gc) {
        my @items;
        my $p = pos($text);
        while (1) {
            pos($text) = $p;
            if ($text =~ /\G\s*\]/gc) { $$pos = pos($text); return \\@items }
            my $item = _toml_parse($text, \$p) or return;
            push @items, $$item;
            pos($text) = $p;
            if ($text =~ /\G\s*,/gc) { $p = pos($text); next }
            if ($text =~ /\G\s*\]/gc) { $$pos = pos($text); return \\@items }
            return;
        }
    }
    return if $text =~ /\G["']/gc;
    if ($text =~ /\G([^,\]]+)/gc) {
        my $bare = $1;
        $bare =~ s/\s+$//;
        $$pos = pos($text);
        my $v = $bare eq 'true' ? 1 : $bare eq 'false' ? 0 : $bare;
        return \$v;
    }
    return;
}

# --- Medium ----------------------------------------------------------------

sub medium {
    my ($state, $from) = @_;

    my $dir = $from;
    if (-f $from) {
        die "error: give Medium's export (the .zip file, or the folder it unzips to)\n" unless $from =~ /\.zip$/i;
        $dir = tempdir(CLEANUP => 1);
        system('unzip', '-q', '-o', $from, '-d', $dir) == 0
            or die "error: could not unzip $from (is unzip installed?)\n";
    }

    my @files;
    File::Find::find({ no_chdir => 1, wanted => sub { push @files, $_ if -f $_ and m{(?:^|/)posts/[^/]+\.html$} } }, $dir);
    die "error: there are no stories in $from (Medium's export has them in a posts folder)\n" unless @files;

    my $layout = layout_for($state, 'post');
    for my $file (sort @files) {
        my $html = App::Dapper::Utils::read_file($file);

        my ($title) = $html =~ m{<h1 class="p-name">(.*?)</h1>}s;
        ($title) = $html =~ m{<title>(.*?)</title>}s unless defined $title;
        $title = strip_tags($title);
        my ($date) = $html =~ m{<time class="dt-published" datetime="([^"]+)"};
        my ($canonical) = $html =~ m{<a href="([^"]+)" class="p-canonical"};
        my ($subtitle) = $html =~ m{<section data-field="subtitle" class="p-summary">(.*?)</section>}s;
        my ($body) = $html =~ m{<section data-field="body" class="e-content">(.*?)</section>\s*<footer>}s;
        $body = '' unless defined $body;

        my $slug;
        if (defined $canonical and $canonical =~ m{/([^/?#]+?)(?:-[0-9a-f]{8,12})?(?:[?#].*)?$}) { $slug = $1 }
        $slug = App::Dapper::Utils::slugify($title) unless defined $slug and length $slug;
        $slug = App::Dapper::Utils::slugify(basename($file, '.html')) unless length $slug;
        $slug =~ s/^draft_//;
        $slug = 'untitled' unless length $slug;

        add_page($state, "$state->{to}/$slug.html", [
            [ title       => $title ],
            [ date        => date_string($date) ],
            [ layout      => $layout ],
            [ description => strip_tags($subtitle) ],
            [ draft       => (basename($file) =~ /^draft_/ or not defined $date) ? 1 : 0 ],
        ], medium_html($body, $title), 'post');
    }
}

# medium_html(html, title) - A Medium story's body without Medium's markup.
sub medium_html {
    my ($html, $title) = @_;

    # The title is repeated as the first heading
    $html =~ s{<h3[^>]*>\s*\Q$title\E\s*</h3>}{}s if defined $title and length $title;
    $html =~ s{<div class="section-divider"><hr class="section-divider"></div>}{<hr>}g;
    $html =~ s{</?(?:section|div)\b[^>]*>}{}g;
    $html =~ s{\s+(?:class|name|id|data-[\w-]+)="[^"]*"}{}g;
    $html =~ s{(</(?:p|h[1-6]|figure|blockquote|pre|ul|ol|li)>|<hr>)}{$1\n}g;
    $html =~ s/^\s+|\s+$//g;
    return "$html\n";
}

1;
