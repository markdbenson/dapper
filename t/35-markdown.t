use 5.010;
use strict;
use warnings;
use utf8;
use Test::More;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Markdown;

binmode(Test::More->builder->$_, ':encoding(UTF-8)') for qw(output failure_output todo_output);

sub md { App::Dapper::Markdown::to_html(@_) }

subtest 'code_block' => sub {
    my $cb = \&App::Dapper::Markdown::code_block;
    is($cb->("x\n", 'perl'), qq{<pre><code class="language-perl">x\n</code></pre>}, 'with a language');
    is($cb->("x\n"), "<pre><code>x\n</code></pre>", 'without a language');
    is($cb->("x", ''), '<pre><code>x</code></pre>', 'empty language means no class');
    is($cb->(undef), '<pre><code></code></pre>', 'undef code');
    is($cb->(''), '<pre><code></code></pre>', 'empty code');
    is($cb->('a < b && c > d'), '<pre><code>a &lt; b &amp;&amp; c &gt; d</code></pre>', 'HTML escaped');
    is($cb->('&lt;'), '<pre><code>&amp;lt;</code></pre>', 'entities are escaped again');
    is($cb->(q{"quotes" and 'apostrophes'}), q{<pre><code>"quotes" and 'apostrophes'</code></pre>},
        'quotes are left alone');
    is($cb->('Zoë ☃', 'text'), '<pre><code class="language-text">Zoë ☃</code></pre>', 'Unicode');
    is($cb->('x', '0'), '<pre><code class="language-0">x</code></pre>', 'a language of 0');
};

subtest 'to_html basics' => sub {
    is(md(undef), '', 'undef is an empty string');
    is(md(''), "\n", 'empty text');
    is(md("Hello *world*\n"), "<p>Hello <em>world</em></p>\n", 'ordinary Markdown');
    is(md("Hi", {}), "<p>Hi</p>\n", 'options are optional');
    is(md("Hi", undef), "<p>Hi</p>\n", 'undef options');
};

subtest 'backtick and tilde fences' => sub {
    is(md("```\nplain\n```\n"), "<pre><code>plain\n</code></pre>\n", 'backticks, no language');
    is(md("~~~\nplain\n~~~\n"), "<pre><code>plain\n</code></pre>\n", 'tildes, no language');
    is(md("```perl\nprint 1;\n```\n"), qq{<pre><code class="language-perl">print 1;\n</code></pre>\n}, 'backticks with a language');
    is(md("~~~ruby\nputs 1\n~~~\n"), qq{<pre><code class="language-ruby">puts 1\n</code></pre>\n}, 'tildes with a language');
    is(md("````\nfour\n````\n"), "<pre><code>four\n</code></pre>\n", 'four backticks');
    is(md("```\nno newline at the end\n```"), "<pre><code>no newline at the end\n</code></pre>\n", 'closing fence at the end of the text');
    is(md("```\nshort fence closes long\n``````\n"), "<pre><code>short fence closes long\n</code></pre>\n", 'a longer closing fence');
    is(md("```\n\n```\n"), "<pre><code>\n</code></pre>\n", 'a blank line inside');
    is(md("```\n```\n"), "<pre><code></code></pre>\n", 'an empty block');
    is(md("```\nline 1\n\n\nline 4\n```\n"), "<pre><code>line 1\n\n\nline 4\n</code></pre>\n", 'blank lines kept');
    is(md("```\n    indented\n\ttabbed\n```\n"), "<pre><code>    indented\n\ttabbed\n</code></pre>\n", 'indentation inside is kept');
    is(md("```\ntrailing   \n```\n"), "<pre><code>trailing   \n</code></pre>\n", 'trailing spaces kept');
};

subtest 'languages' => sub {
    my %cases = (
        'c++'           => 'c++',
        'c#'            => 'c#',
        'objective-c'   => 'objective-c',
        '.net'          => '.net',
        'python3'       => 'python3',
        'shell_session' => 'shell_session',
        'JSON'          => 'JSON',
    );
    for my $lang (sort keys %cases) {
        is(md("```$lang\nx\n```\n"), qq{<pre><code class="language-$cases{$lang}">x\n</code></pre>\n}, "language $lang");
    }
    is(md("```   ruby   \nx\n```\n"), qq{<pre><code class="language-ruby">x\n</code></pre>\n}, 'spaces around the language');
    is(md("```\truby\nx\n```\n"), qq{<pre><code class="language-ruby">x\n</code></pre>\n}, 'a tab before the language');
    is(md("~~~~ perl extra words\nx\n~~~~\n"), qq{<pre><code class="language-perl">x\n</code></pre>\n}, 'words after the language ignored');
    is(md("```perl {linenos}\nx\n```\n"), qq{<pre><code class="language-perl">x\n</code></pre>\n}, 'attributes after the language ignored');
    is(md("```{.python}\nx\n```\n"), "<pre><code>x\n</code></pre>\n", 'a brace attribute is not a language');
    is(md(qq{```"><script>\nx\n```\n}), "<pre><code>x\n</code></pre>\n", 'markup is never put in the class');
};

subtest 'escaping and Markdown inside a fence' => sub {
    is(md("```\n<script>alert(1)</script>\n```\n"), "<pre><code>&lt;script&gt;alert(1)&lt;/script&gt;\n</code></pre>\n", 'HTML is escaped');
    is(md("```\n&copy; & &amp;\n```\n"), "<pre><code>&amp;copy; &amp; &amp;amp;\n</code></pre>\n", 'ampersands are escaped');
    is(md("```\n*not em* __not strong__ [not](link)\n```\n"), "<pre><code>*not em* __not strong__ [not](link)\n</code></pre>\n", 'Markdown is not applied');
    is(md("```\n# not a heading\n- not a list\n> not a quote\n```\n"), "<pre><code># not a heading\n- not a list\n&gt; not a quote\n</code></pre>\n", 'block syntax is not applied');
    is(md("```\n[% page.title %]\n```\n"), "<pre><code>[% page.title %]\n</code></pre>\n", 'template tags are left alone');
    is(md("```\nbackslash \\* and \\\\\n```\n"), "<pre><code>backslash \\* and \\\\\n</code></pre>\n", 'backslashes kept');
    is(md("```\nZoë 日本 😀\n```\n"), "<pre><code>Zoë 日本 😀\n</code></pre>\n", 'Unicode kept');
    is(md("```\n`inline` ``double``\n```\n"), "<pre><code>`inline` ``double``\n</code></pre>\n", 'backticks inside');
};

subtest 'nesting fences' => sub {
    is(md("````\n```\ninner\n```\n````\n"), "<pre><code>```\ninner\n```\n</code></pre>\n", 'three backticks inside four');
    is(md("~~~\n```\ninner\n```\n~~~\n"), "<pre><code>```\ninner\n```\n</code></pre>\n", 'backticks inside tildes');
    is(md("```\na\n~~~\nb\n```\n"), "<pre><code>a\n~~~\nb\n</code></pre>\n", 'tildes do not close backticks');
    is(md("```\nfirst\n```\n\n```\nsecond\n```\n"), "<pre><code>first\n</code></pre>\n\n<pre><code>second\n</code></pre>\n", 'two blocks');
    is(md("```a\n1\n```\n```b\n2\n```\n"),
        qq{<pre><code class="language-a">1\n</code></pre>\n\n<pre><code class="language-b">2\n</code></pre>\n}, 'two blocks with no blank line between');
};

subtest 'indentation of fences' => sub {
    is(md("   ```c++\nx\n   ```\n"), qq{<pre><code class="language-c++">x\n</code></pre>\n}, 'up to three spaces before the fences');
    is(md(" ```\nx\n```\n"), "<pre><code>x\n</code></pre>\n", 'opening indented, closing not');
    is(md("  ~~~\nx\n  ~~~~~~\n"), "<pre><code>x\n</code></pre>\n", 'indented tildes');
    is(md("    ```\nx\n    ```\n"), "<pre><code>```\n</code></pre>\n\n<p>x\n    ```</p>\n",
        'four spaces is an ordinary indented code block, not a fence');
    is(md("- item\n\n  ```\n  in a list\n  ```\n"), "<ul>\n<li>item</li>\n</ul>\n\n<pre><code>  in a list\n</code></pre>\n",
        'a fence in a list item keeps its indentation and leaves the list');
};

subtest 'unclosed and mismatched fences' => sub {
    is(md("```\nunclosed\n"), "<p>```\nunclosed</p>\n", 'an unclosed fence is left as text');
    is(md("~~~\nx\n```\n"), "<p>~~~\nx\n```</p>\n", 'backticks do not close tildes');
    unlike(md("````\nx\n```\n"), qr{<pre>}, 'a shorter fence does not close a longer one');
    is(md("~~~\nx\n```\n```\ny\n```\n"), "<p>~~~\nx</p>\n\n<pre><code></code></pre>\n\n<p>y\n```</p>\n",
        'later fences pair up among themselves');
    is(md("```\nx\n``` not a close\n```\n"), "<pre><code>x\n``` not a close\n</code></pre>\n", 'a fence with text after it does not close');
    is(md("``\nx\n``\n"), "<p><code>\nx\n</code></p>\n", 'two backticks is inline code, not a fence');
};

subtest 'fences among other Markdown' => sub {
    is(md("Text before\n```js\nvar a = 1;\n```\nText after *em*\n"),
        qq{<p>Text before</p>\n\n<pre><code class="language-js">var a = 1;\n</code></pre>\n\n<p>Text after <em>em</em></p>\n},
        'paragraphs around a fence need no blank lines');
    is(md("> quote\n```\nafter\n```\n"), "<blockquote>\n  <p>quote</p>\n</blockquote>\n\n<pre><code>after\n</code></pre>\n",
        'after a blockquote');
    is(md("# Title\n\n```\nx\n```\n\n## Sub\n"),
        qq{<h1 id="title">Title</h1>\n\n<pre><code>x\n</code></pre>\n\n<h2 id="sub">Sub</h2>\n}, 'between headings');
    is(md("Inline `code` here\n"), "<p>Inline <code>code</code> here</p>\n", 'inline code untouched');
    is(md("```\nDAPPERCODEBLOCK0\n```\n"), "<pre><code>DAPPERCODEBLOCK0\n</code></pre>\n",
        'the placeholder text inside a code block');
    local $SIG{__WARN__} = sub {};
    is(md("Para mentions DAPPERCODEBLOCK0\n"), "<p>Para mentions DAPPERCODEBLOCK0</p>\n",
        'the placeholder text in a paragraph');
};

subtest 'fences and components' => sub {
    my @unknown;
    my $html = md("::: note\nHello *there*\n\n```perl\nmy \$x = 1 < 2;\n```\n:::\n", { unknown => \@unknown });
    is($html, qq{<aside class="callout callout-note" role="note">\n<p>Hello <em>there</em></p>\n\n}
        . qq{<pre><code class="language-perl">my \$x = 1 &lt; 2;\n</code></pre>\n</aside>\n},
        'a fence inside a component is a code block, escaped once');
    is_deeply(\@unknown, [], 'no unknown components');

    is(md("```\n::: note\nnot a component\n:::\n```\n"), "<pre><code>::: note\nnot a component\n:::\n</code></pre>\n",
        'a component inside a fence is just code');

    @unknown = ();
    is(md("::: nosuch\nx\n:::\n", { unknown => \@unknown }), "<p>::: nosuch\nx\n:::</p>\n", 'an unknown component is left as text');
    is_deeply(\@unknown, ['nosuch'], 'and reported');

    is(md("```\n:::\n```\n"), "<pre><code>:::\n</code></pre>\n", 'colons without a name are not a component');
};

subtest 'in a built page' => sub {
    make_site({
        '_source/code.md' => "---\ntitle: Code\n---\n```html\n<p>[% page.title %]</p>\n```\n",
        '_source/tmpl.md' => "---\ntitle: Tmpl\ntemplate: true\n---\n```\n[% page.title %]\n```\n",
        '_source/raw.html' => "---\ntitle: Raw\n---\n```\nnot markdown\n```\n",
        '_layout/index.html' => '[% page.content %]',
    });
    quiet_build();
    is(slurp('_output/code.html'), qq{<pre><code class="language-html">&lt;p&gt;[% page.title %]&lt;/p&gt;\n</code></pre>\n},
        'template tags in code are not run');
    is(slurp('_output/tmpl.html'), "<pre><code>Tmpl\n</code></pre>\n", 'unless the page sets template: true');
    is(slurp('_output/raw.html'), "```\nnot markdown\n```\n", 'only .md files are Markdown');
};

done_testing();
