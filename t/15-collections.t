use 5.010;
use strict;
use warnings;
use Test::More;
use Cwd qw(getcwd);

use lib 't/lib';
use DapperTest;
use App::Dapper;

sub posts {
    my %files;
    for my $n (1 .. 5) {
        my $tags = $n % 2 ? "[perl, Open Source]" : "[perl]";
        $files{"_source/blog/post$n.md"} = "---\ntitle: Post $n\ncategories: blog\ntags: $tags\ndate: 2020-01-0$n\n---\nPost $n.\n";
    }
    $files{'_source/notes/note.md'} = "---\ntitle: A note\ncategories: notes\ndate: 2020-02-01\n---\nNote.\n";
    return %files;
}

subtest 'site.tags' => sub {
    make_site({ posts() });
    my $d = quiet_build();
    is(scalar @{ $d->{site}->{tags}->{perl} }, 5, 'every post tagged perl');
    is_deeply([ map { $_->{title} } @{ $d->{site}->{tags}->{'Open Source'} } ], ['Post 1', 'Post 3', 'Post 5'], 'oldest first, like categories');
};

subtest 'paginate in front matter' => sub {
    make_site({
        posts(),
        '_source/index.html' => "---\ntitle: Home\npaginate:\n  category: blog\n  per_page: 2\n---\n",
        '_layout/index.html' => "[% IF paginator %][% paginator.page %]/[% paginator.total_pages %]:"
            . "[% FOR p IN paginator.items %][% p.title %];[% END %]"
            . "prev=[% paginator.previous_url %] next=[% paginator.next_url %][% ELSE %][% page.title %][% END %]",
    });
    quiet_build();
    is(slurp('_output/index.html'), '1/3:Post 5;Post 4;prev= next=/page/2/', 'page 1 keeps the URL');
    is(slurp('_output/page/2/index.html'), '2/3:Post 3;Post 2;prev=/ next=/page/3/', 'page 2');
    is(slurp('_output/page/3/index.html'), '3/3:Post 1;prev=/page/2/ next=', 'last page');
};

subtest 'paginate all posts with a number, from a non-index page' => sub {
    make_site({
        posts(),
        '_source/archive.html' => "---\ntitle: Archive\npaginate: 4\n---\n",
        '_layout/index.html'   => "[% paginator.total_items %]:[% FOR p IN paginator.pages %][% p.number %]=[% p.url %] [% END %]",
    });
    quiet_build();
    is(slurp('_output/archive.html'), '6:1=/archive.html 2=/archive/page/2/ ', 'every post, with URLs below the page');
    ok(-e '_output/archive/page/2/index.html', 'page 2 written');
};

subtest 'paginated content with template: true' => sub {
    make_site({
        posts(),
        '_source/blog/index.html' => "---\ntitle: Blog\ntemplate: true\npaginate:\n  tag: Open Source\n  per_page: 2\n---\n[% FOR p IN paginator.items %][% p.title %],[% END %]",
        '_layout/index.html' => "[% page.content %]",
    });
    quiet_build();
    is(slurp('_output/blog/index.html'), 'Post 5,Post 3,', 'content rendered per page');
    is(slurp('_output/blog/page/2/index.html'), 'Post 1,', 'second page');
};

subtest 'category and tag pages' => sub {
    make_site({
        posts(),
        '_config.yml' => "---\nname: x\ncategory_pages:\n  layout: list\ntag_pages:\n  layout: list\n  per_page: 2\n",
        '_layout/list.html' => "[% page.title %]([% page.category %][% page.tag %]):[% FOR p IN page.posts %][% p.title %];[% END %]"
            . "[% IF paginator %] [% paginator.page %]/[% paginator.total_pages %][% END %]",
        '_source/index.html' => "---\ntitle: Home\n---\n",
        '_layout/index.html' => "[% site.category_pages.blog %] [% site.tag_pages.item('Open Source') %]",
    });
    my $d = quiet_build();
    is(slurp('_output/blog/index.html'), 'blog(blog):Post 5;Post 4;Post 3;Post 2;Post 1;', 'category page, newest first');
    is(slurp('_output/notes/index.html'), 'notes(notes):A note;', 'every category gets a page');
    is(slurp('_output/tags/open-source/index.html'), 'Open Source(Open Source):Post 5;Post 3; 1/2', 'tag page with a slugified URL, paginated');
    is(slurp('_output/tags/open-source/page/2/index.html'), 'Open Source(Open Source):Post 1; 2/2', 'second page of a tag');
    like(slurp('_output/index.html'), qr{^/blog/ }, 'site.category_pages holds the URLs');
};

subtest 'category pages need a layout' => sub {
    make_site({ posts(), '_config.yml' => "---\nname: x\ncategory_pages:\n  urlpattern: /c/:category/\n" });
    eval { quiet_build() };
    like($@, qr/category_pages in _config\.yml needs a layout/, 'clear error');
};

subtest 'search runs the search command' => sub {
    make_site({ '_source/index.md' => "---\ntitle: x\n---\nx\n" });
    my $dir = getcwd();
    spew("$dir/fake-pagefind", "#!$^X\nopen my \$f, '>', 'search-ran'; print \$f join(' ', \@ARGV);\n");
    chmod 0755, "$dir/fake-pagefind";
    spew('_config.yml', "---\nname: x\nsearch: true\nsearch_command: $dir/fake-pagefind\nignore: ['^\\\\.', '^_', 'fake-pagefind', 'search-ran']\n");
    quiet_build();
    is(slurp('search-ran'), '--site _output --quiet', 'command run on the output directory');

    spew('_config.yml', "---\nname: x\nsearch: true\nsearch_command: no-such-pagefind-command\n");
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    like(join('', @warnings), qr/search: true needs Pagefind/, 'missing command is a warning, not a failure');
};

done_testing();
