use utf8;
use 5.010;
use strict;
use warnings;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Markdown;
use App::Dapper::Components;

# Components of your own, from templates in _layout/components

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw/ output failure_output todo_output /;

my %templates = (
    '_layout/components/show.html'    => '[[% name %]|[% args.size %]|[% args.0 %]|[% args.1 %]|[% args.2 %]|[% args.plan %]|'
                                       . '[% FOR a IN args.list %]<[% a %]>[% END %]|[% content %]|[% page.title %]|[% site.name %]]',
    '_layout/components/youtube.html' => 'YT([% args.0 %])',
    '_layout/components/note.htm'     => 'NOTE([% content %])',
    '_layout/components/x.tt'         => 'TT',
    '_layout/components/x.html'       => 'HTML',
    '_layout/components/uni.html'     => 'é[% args.0 %]',
    '_layout/components/esc.html'     => '[% args.0 %]|[% args.0 | html %]',
    '_layout/components/count.html'   => '[% args.list.size %]-[% args.list.join("+") %]',
    '_layout/components/badge.html'   => '<span class="badge">[% FOR a IN args.list %][% a | upper %][% END %]</span>',
    '_layout/components/empty.html'   => '',
    '_layout/components/bad.html'     => '[% IF %]',
);

sub opts { return { layout => '_layout', vars => { page => { title => 'P' }, site => { name => 'S' } }, @_ } }
sub html { my ($text, %o) = @_; App::Dapper::Markdown::to_html($text, opts(%o)) }
sub show { my ($size, $a0, $a1, $a2, $plan, $list, $content, $title, $site) = @_; "[" . join("|", "show", $size, map { defined $_ ? $_ : "" } $a0, $a1, $a2, $plan, $list, $content, defined $title ? $title : "P", defined $site ? $site : "S") . "]" }

subtest 'arguments, content, page and site' => sub {
    make_site({ %templates });
    is(html(qq{::: show plan=Pro "a b" c\n}), show(3, 'plan=Pro', 'a b', 'c', 'Pro', '<plan=Pro><a b><c>') . "\n", 'args.N, args.name, args.size, args.list');
    is(html(qq{::: show\n}), show(0) . "\n", 'no arguments');
    is(html(qq{::: show x=1 x=2\n}), show(2, 'x=1', 'x=2', undef, undef, '<x=1><x=2>') . "\n", 'a name given twice');
    is(html(qq{::: show "plan=Basic plan"\n}), show(1, 'plan=Basic plan', undef, undef, 'Basic plan', '<plan=Basic plan>') . "\n", 'a quoted name=value');
    is(html(qq{::: show plan=\n}), show(1, 'plan=', undef, undef, '', '<plan=>') . "\n", 'an empty value');
    is(html(qq{::: show 2x=no\n}), show(1, '2x=no', undef, undef, undef, '<2x=no>') . "\n", 'names must start with a letter or _');
    is(html(qq{::: SHOW a\n}), show(1, 'a', undef, undef, undef, '<a>') . "\n", 'the name in capitals uses the lowercase template');
    is(html(qq{::: show\nbody *em*\n:::\n}), show(0, (undef) x 5, "<p>body <em>em</em></p>\n") . "\n", 'content is the HTML of the Markdown inside');
    is(html(qq{::: show\n:::\n}), show(0) . "\n", 'closed straight away: empty content');
    is(html(qq{::: count a b c\n}), "3-a+b+c\n", 'args.list methods');
    is(html(qq{::: badge new hot\n}), qq{<span class="badge">NEWHOT</span>\n}, 'filters');
    is(html(qq{::: uni \x{fc}\n}), "\x{e9}\x{fc}\n", 'characters outside ASCII');
    is(html(qq{::: esc "<b>"\n}), "<b>|&lt;b&gt;\n", 'arguments are not escaped unless the template says so');
    is(html(qq{::: empty\n}), "\n", 'an empty template');
    is(html(qq{::: show a\n}, vars => undef), show(1, 'a', undef, undef, undef, '<a>', undef, '', '') . "\n", 'without page and site');
};

subtest 'single line or wrapping' => sub {
    make_site({ %templates });
    is(html("::: show one\n::: show two\n:::\n"), show(1, 'one', undef, undef, undef, '<one>') . "\n\n" . show(1, 'two', undef, undef, undef, '<two>') . "\n",
        'another opening first makes it a single line; the next one does not wrap either');
    is(html("::: show a\nText after\n"), show(1, 'a', undef, undef, undef, '<a>') . "\n\n<p>Text after</p>\n", 'never closed: a single line');
    is(html("::: show a\n::::\n"), show(1, 'a', undef, undef, undef, '<a>') . "\n\n<p>::::</p>\n", 'more colons do not close it');
    is(html(":::: show\n::: note\nin\n:::\n::::\n"), show(0, (undef) x 5, "NOTE(<p>in</p>\n)\n") . "\n", 'nested, with a built-in replaced');
    is(html(":::: show\n::: show inner\n::::\n"), show(0, (undef) x 5, show(1, 'inner', undef, undef, undef, '<inner>') . "\n") . "\n", 'itself inside itself');
    is(html("::: show a\n\nPara\n\n:::\n"), show(1, 'a', undef, undef, undef, '<a>', "<p>Para</p>\n") . "\n", 'blank lines inside');
};

subtest 'replacing built-ins' => sub {
    make_site({ %templates });
    is(html("::: youtube abc\n"), "YT(abc)\n", 'a single-line built-in, replaced (no ID check)');
    is(html("::: youtube abc\n:::\n"), "YT(abc)\n\n<p>:::</p>\n", 'still a single line: the colons after it are text');
    is(html("::: note\nx\n:::\n"), "NOTE(<p>x</p>\n)\n", 'a wrapping built-in, replaced (.htm)');
    is(html("::: note\nnever closed\n"), "NOTE()\n\n<p>never closed</p>\n", 'replaced and never closed: a single line');
    is(html("::: tip\nx\n:::\n"), qq{<aside class="callout callout-tip" role="note">\n<p>x</p>\n</aside>\n}, 'the others are still built in');
    is(html("::: x\n"), "HTML\n", '.html wins over .tt');
    my @unknown;
    html("::: show\n::: x\n::: nope\n", unknown => \@unknown);
    is_deeply(\@unknown, ['nope'], 'components of your own are known');
};

subtest 'template errors' => sub {
    make_site({ %templates });
    eval { html("::: bad\n") };
    is($@, "error: could not process the component template _layout/components/bad.html: parse error - input text line 1 char 8: Missing END directive\n", 'a broken template');

    make_site({ %templates, '_source/index.md' => "---\ntitle: Home\n---\n::: bad\n" });
    eval { quiet_build() };
    like($@, qr{^error: could not process the component template _layout/components/bad\.html: parse error}, 'stops the build');

    my $report = App::Dapper->new()->check();
    ok(!$report->{ok}, 'check fails');
    ok((grep { $_->{message} =~ m{component template _layout/components/bad\.html} } @{$report->{errors}}), 'and reports it');
};

subtest 'in a site' => sub {
    make_site({
        %templates,
        '_config.yml' => "---\nname: My Site\n",
        '_source/index.md' => "---\ntitle: Home\n---\n::: show plan=Pro \"Most popular\"\n**\$10** a month\n:::\n\n::: badge new\n\n::: note\nMine\n:::\n",
        '_source/blog/post.md' => "---\ntitle: A Post\n---\n::: show\n",
        '_layout/components/pagevars.html' => '[% page.url %]|[% site.name %]|[% page.title %]',
        '_source/vars.md' => "---\ntitle: Vars\n---\n::: pagevars\n",
    });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    is_deeply(\@warnings, [], 'no warnings');
    is(slurp('_output/index.html'),
        "<title>Home</title>\n[show|2|plan=Pro|Most popular||Pro|<plan=Pro><Most popular>|<p><strong>\$10</strong> a month</p>\n|Home|My Site]\n\n"
        . qq{<span class="badge">NEW</span>\n\nNOTE(<p>Mine</p>\n)\n},
        'the whole page');
    is(slurp('_output/blog/post.html'), "<title>A Post</title>\n" . show(0, (undef) x 6, 'A Post', 'My Site') . "\n", 'the page it is on');
    is(slurp('_output/vars.html'), "<title>Vars</title>\n/vars.html|My Site|Vars\n", 'page.url and site.name');
};

subtest 'a theme layout directory' => sub {
    make_site({
        '_config.yml' => "---\nname: x\nlayout: mylayouts\n",
        'mylayouts/index.html' => "[% page.content %]",
        'mylayouts/components/hello.html' => 'Hello [% args.0 %]',
        '_source/index.md' => "---\ntitle: Home\n---\n::: hello world\n\n::: gone\n",
    });
    my @warnings;
    local $SIG{__WARN__} = sub { push @warnings, @_ };
    quiet_build();
    is(slurp('_output/index.html'), "Hello world\n\n<p>::: gone</p>\n", 'templates come from the layout directory');
    like(join('', @warnings), qr{others can be added in mylayouts/components\n}, 'the warning names it');
};

done_testing();
