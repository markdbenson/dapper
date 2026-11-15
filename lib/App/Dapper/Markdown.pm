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

It also expands components such as C<::: note> and C<::: youtube>; see
L<App::Dapper::Components>.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

use Text::MultiMarkdown ();
use App::Dapper::Components;

=head2 to_html

Takes Markdown text and returns HTML. Options (a hash reference) are passed
to L<App::Dapper::Components/expand>.

=cut

sub to_html {
    my ($text, $options) = @_;

    return '' unless defined $text;
    $options ||= {};

    my (@blocks, @fences);

    # Replace each fenced code block with a placeholder paragraph, so that
    # Markdown leaves its contents alone, and put the HTML back afterwards
    $text =~ s{
        ^([ ]{0,3})(`{3,}|~{3,})[ \t]*([\w+#.-]*)[^\n]*\n   # opening fence and language
        (.*?)                                               # code
        ^[ ]{0,3}\2[`~]*[ \t]*$                              # closing fence
    }{
        push @fences, $&;
        push @blocks, code_block($4, $3);
        "\n\nDAPPERCODEBLOCK" . $#blocks . "\n\n";
    }gemsx;

    # Components (::: note, ::: youtube, ...); the Markdown inside them is
    # converted with its code blocks put back
    my $components = [];
    if ($text =~ /^[ ]{0,3}:{3,}[ \t]*[A-Za-z]/m) {
        ($text, $components) = App::Dapper::Components::expand($text, sub {
            my ($body, $opts) = @_;
            $body =~ s{^DAPPERCODEBLOCK(\d+)$}{$fences[$1]}gm;
            return to_html($body, $opts);
        }, $options);
    }

    my $html = Text::MultiMarkdown::markdown($text);

    $html =~ s{<p>DAPPERCOMPONENT(\d+)</p>}{$components->[$1]}g;
    $html =~ s{DAPPERCOMPONENT(\d+)}{$components->[$1]}g;

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
