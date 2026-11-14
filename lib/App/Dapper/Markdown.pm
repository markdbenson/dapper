package App::Dapper::Markdown;

=head1 NAME

App::Dapper::Markdown - Convert Markdown to HTML, with fenced code blocks.

=head1 DESCRIPTION

Dapper uses L<Text::MultiMarkdown> for Markdown. On top of it, this module
adds fenced code blocks, which MultiMarkdown does not understand:

    ```perl
    print "Hello, world!\n";
    ```

A fenced block (with three or more backticks or tildes) becomes
C<< <pre><code class="language-perl"> >>, with its contents HTML-escaped and
left untouched by Markdown. The C<language-*> class is what client-side
highlighters such as Prism and highlight.js look for.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use Text::MultiMarkdown ();

=head2 to_html

Takes Markdown text and returns HTML.

=cut

sub to_html {
    my ($text) = @_;

    return '' unless defined $text;

    my @blocks;

    # Replace each fenced code block with a placeholder paragraph, so that
    # Markdown leaves its contents alone, and put the HTML back afterwards
    $text =~ s{
        ^([ ]{0,3})(`{3,}|~{3,})[ \t]*([\w+#.-]*)[^\n]*\n   # opening fence and language
        (.*?)                                               # code
        ^[ ]{0,3}\2[`~]*[ \t]*$                              # closing fence
    }{
        push @blocks, code_block($4, $3);
        "\n\nDAPPERCODEBLOCK" . $#blocks . "\n\n";
    }gemsx;

    my $html = Text::MultiMarkdown::markdown($text);

    $html =~ s{<p>DAPPERCODEBLOCK(\d+)</p>}{$blocks[$1]}g;
    $html =~ s{DAPPERCODEBLOCK(\d+)}{$blocks[$1]}g;

    return $html;
}

=head2 code_block

Takes the code and (optionally) its language, and returns the HTML for a code
block.

=cut

sub code_block {
    my ($code, $language) = @_;

    $code = '' unless defined $code;
    $code =~ s/&/&amp;/g;
    $code =~ s/</&lt;/g;
    $code =~ s/>/&gt;/g;

    my $class = defined $language && length $language ? qq{ class="language-$language"} : '';

    return "<pre><code$class>$code</code></pre>";
}

1;
