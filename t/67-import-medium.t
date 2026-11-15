use utf8;
use 5.010;
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Spec;

use lib 't/lib';
use DapperTest;
use App::Dapper;
use App::Dapper::Import;

# Importing Medium's export, as a folder or a zip file

binmode Test::More->builder->$_, ':encoding(UTF-8)' for qw/ output failure_output todo_output /;

sub project {
    my (%opt) = @_;
    my $old = tempdir(CLEANUP => 1);
    make_site($opt{bare} ? {} : { '_layout/post.html' => "<article>[% page.content %]</article>" });
    return $old;
}

sub run_import {
    my ($kind, $from, %options) = @_;
    my $loud = delete $options{loud};
    my $d = App::Dapper->new();
    $d->{quiet} = $loud ? 0 : 1;
    my $out = '';
    open(my $fh, '>', \$out) or die;
    my $old = select $fh;
    my $state = eval { $d->import_from($kind, $from, %options) };
    my $error = $@;
    select $old;
    die $error if $error;
    return wantarray ? ($state, $out) : $state;
}

sub front { my ($file) = @_; (App::Dapper::Utils::split_frontmatter(slurp($file), $file))[0] }
sub body  { my ($file) = @_; my $b = (App::Dapper::Utils::split_frontmatter(slurp($file), $file))[1]; $b =~ s/^\n//; $b }

sub which { my ($p) = @_; for (File::Spec->path) { return "$_/$p" if -x "$_/$p" } return }

# story(%parts) - A story as Medium exports it
sub story {
    my (%s) = @_;
    my $title = defined $s{title} ? $s{title} : 'Why I Write';
    my $html = "<!DOCTYPE html><html><head><title>" . (defined $s{head_title} ? $s{head_title} : $title) . "</title></head><body><article class=\"h-entry\">\n";
    $html .= qq{<header><h1 class="p-name">$title</h1></header>\n} unless $s{no_h1};
    $html .= qq{<section data-field="subtitle" class="p-summary">$s{subtitle}</section>\n} if defined $s{subtitle};
    $html .= qq{<section data-field="body" class="e-content">$s{body}</section>\n} if defined $s{body};
    $html .= "<footer><p>By Me";
    $html .= qq{ on <a href="https://medium.com/p/x"><time class="dt-published" datetime="$s{date}">A day</time></a>} if defined $s{date};
    $html .= qq{.</p><p><a href="$s{canonical}" class="p-canonical">Canonical link</a></p>} if defined $s{canonical};
    $html .= "</footer></article></body></html>\n";
    return $html;
}

my $BODY = '<section name="a1" class="section section--body"><div class="section-content"><div class="section-inner sectionLayout--insetColumn">'
    . '<h3 name="b2" id="b2" class="graf graf--h3 graf--leading graf--title">Why I Write</h3>'
    . '<p name="c3" id="c3" class="graf graf--p" data-selectable-paragraph="">Because I <em class="markup--em markup--p-em">must</em>.</p>'
    . '<figure name="d4" id="d4" class="graf graf--figure"><img class="graf-image" data-image-id="x.jpeg" data-width="800" src="https://cdn-images-1.medium.com/x.jpeg"><figcaption class="imageCaption">Cap</figcaption></figure>'
    . '<blockquote name="e5" class="graf graf--blockquote">Quote</blockquote>'
    . '<ul class="postList"><li name="f6" class="graf graf--li">One</li><li name="g7" class="graf graf--li">Two</li></ul>'
    . '</div></div></section>'
    . '<section name="h8" class="section section--body"><div class="section-divider"><hr class="section-divider"></div><div class="section-content"><div class="section-inner">'
    . '<h4 name="i9" class="graf graf--h4">Later</h4><pre name="j1" class="graf graf--pre">code</pre></div></div></section>';

subtest 'a story, exactly' => sub {
    my $old = project();
    spew("$old/posts/2020-02-02_Why-I-Write-1a2b3c4d5e6f.html", story(
        subtitle => 'A <em>few</em> reasons &amp; more.', body => $BODY, date => '2020-02-02T10:00:00.000Z',
        canonical => 'https://medium.com/@me/why-i-write-1a2b3c4d5e6f'));
    my ($state, $out) = run_import('medium', $old, loud => 1);
    is(slurp('_source/blog/why-i-write.html'), <<'HTML', 'the whole file');
---
title: Why I Write
date: 2020-02-02T10:00:00Z
layout: post
description: A few reasons & more.
---
<p>Because I <em>must</em>.</p>
<figure><img src="https://cdn-images-1.medium.com/x.jpeg"><figcaption>Cap</figcaption></figure>
<blockquote>Quote</blockquote>
<ul><li>One</li>
<li>Two</li>
</ul>
<hr>
<h4>Later</h4>
<pre>code</pre>
HTML
    is_deeply($state->{pages}, [{ file => '_source/blog/why-i-write.html', kind => 'post', draft => 0 }], 'a post');
    is($out, "Imported 1 post and 0 pages into _source.\nRun \"dapper check\" to find links that need fixing.\n", 'the report');
};

subtest 'titles, slugs, dates and drafts' => sub {
    my $old = project();
    my %stories = (
        'a.html'      => story(title => 'Canonical', canonical => 'https://medium.com/@me/a-better-name-abcdef123456', date => '2021-01-01T00:00:00.000Z', body => '<p>x</p>'),
        'b.html'      => story(title => 'No hash', canonical => 'https://me.medium.com/plain-slug?source=rss#x', date => '2021-01-02T00:00:00.000Z', body => '<p>x</p>'),
        'e.html'      => story(title => 'Bare Canonical', canonical => 'https://medium.com/', date => '2021-01-10T00:00:00.000Z', body => '<p>x</p>'),
        'c.html'      => story(title => 'No Canonical: Here!', date => '2021-01-03T00:00:00.000Z', body => '<p>x</p>'),
        'd.html'      => story(title => '', head_title => 'From the &lt;head&gt;', no_h1 => 1, date => '2021-01-04T00:00:00.000Z', body => '<p>x</p>'),
        'draft_Unfinished-9f8e7d6c5b4a.html' => story(title => 'Unfinished', body => '<p>Soon.</p>'),
        'draft_Dated-1234567890ab.html'      => story(title => 'Dated draft', date => '2021-01-05T00:00:00.000Z', body => '<p>x</p>'),
        'undated.html' => story(title => 'Undated', body => '<p>x</p>'),
        'draft_.html'  => story(title => '???', no_h1 => 1, head_title => '', body => '<p>x</p>'),
        'nobody.html'  => story(title => 'No Body', date => '2021-01-06T00:00:00.000Z'),
        'tags.html'    => story(title => '<b>Bold</b> &amp; <i>tagged</i>', date => '2021-01-07T00:00:00.000Z', body => '<p>x</p>'),
        'same1.html'   => story(title => 'Same', date => '2021-01-08T00:00:00.000Z', body => '<p>one</p>'),
        'same2.html'   => story(title => 'Same', date => '2021-01-09T00:00:00.000Z', body => '<p>two</p>'),
    );
    spew("$old/posts/$_", $stories{$_}) for keys %stories;
    spew("$old/posts/notes.txt", "not a story");
    spew("$old/profile/profile.html", story(title => 'Not a story'));
    spew("$old/posts/sub/deeper.html", story(title => 'Too deep'));

    my $state = run_import('medium', $old);
    my %pages = map { $_->{file} => $_->{draft} } @{$state->{pages}};
    is_deeply(\%pages, {
        '_source/blog/a-better-name.html' => 0, '_source/blog/plain-slug.html' => 0, '_source/blog/no-canonical-here.html' => 0,
        '_source/blog/from-the-head.html' => 0, '_source/blog/unfinished.html' => 1, '_source/blog/dated-draft.html' => 1,
        '_source/blog/undated.html' => 1, '_source/blog/untitled.html' => 1, '_source/blog/no-body.html' => 0,
        '_source/blog/bold-tagged.html' => 0, '_source/blog/same.html' => 0, '_source/blog/same-2.html' => 0,
        '_source/blog/bare-canonical.html' => 0,
    }, 'file names and drafts');
    is(front('_source/blog/a-better-name.html')->{title}, 'Canonical', 'the slug from the canonical link, without its ID');
    is(front('_source/blog/from-the-head.html')->{title}, 'From the <head>', 'the title from <title> when there is no heading');
    is(front('_source/blog/bold-tagged.html')->{title}, 'Bold & tagged', 'tags and entities removed from the title');
    is(front('_source/blog/a-better-name.html')->{date}, '2021-01-01T00:00:00Z', 'the date');
    ok(!exists front('_source/blog/undated.html')->{date}, 'no date');
    is(front('_source/blog/unfinished.html')->{draft}, 1, 'draft_ files are drafts');
    is(front('_source/blog/dated-draft.html')->{date}, '2021-01-05T00:00:00Z', 'even with a date');
    is(body('_source/blog/no-body.html'), "\n", 'no body');
    is(body('_source/blog/same.html'), "<p>one</p>\n", 'the same slug twice: the first file');
    is(body('_source/blog/same-2.html'), "<p>two</p>\n", 'then -2');
    ok(!-e '_source/blog/not-a-story.html' && !-e '_source/blog/too-deep.html', 'only HTML files directly in posts');
    ok(!exists $pages{'_source/blog/.html'}, 'a story with no title or name gets one');
};

subtest 'markup cleanup' => sub {
    my $old = project(bare => 1);
    spew("$old/posts/m.html", story(title => 'Clean', date => '2021-01-01T00:00:00.000Z',
        body => '<section class="s"><div class="d"><h3 class="graf--title">Clean</h3><h3 class="x">Another heading</h3>'
              . '<p class="a" name="b" id="c" data-x="1" data-foo-bar="2" style="color:red">Kept <a href="/x" class="link" data-href="/x">link</a></p>'
              . '<div class="section-divider"><hr class="section-divider"></div><h1>H1</h1><h2>H2</h2><h5>H5</h5><h6>H6</h6><ol><li>A</li></ol><p>Last</p></div></section>'));
    run_import('medium', $old);
    is(body('_source/blog/clean.html'),
        qq{<h3>Another heading</h3>\n<p style="color:red">Kept <a href="/x">link</a></p>\n<hr>\n<h1>H1</h1>\n<h2>H2</h2>\n<h5>H5</h5>\n<h6>H6</h6>\n<ol><li>A</li>\n</ol>\n<p>Last</p>\n},
        "the title heading, sections, divs, classes, names, ids and data- attributes removed");
    ok(!exists front('_source/blog/clean.html')->{layout}, 'no post layout in the project: none given');
    is(App::Dapper::Import::medium_html('<p>x</p>', ''), "<p>x</p>\n", 'medium_html with an empty title');
    is(App::Dapper::Import::medium_html('<h3>T (1)</h3><p>x</p>', 'T (1)'), "<p>x</p>\n", 'a title with regex characters');
    is(App::Dapper::Import::medium_html('', undef), "\n", 'nothing');
};

subtest 'a zip file' => sub {
    SKIP: {
        skip 'zip and unzip are needed', 7 unless which('zip') and which('unzip');
        my $old = project();
        my $export = tempdir(CLEANUP => 1);
        spew("$export/medium-export/posts/2020-02-02_Zipped-1a2b3c4d5e6f.html", story(title => 'Zipped', date => '2020-02-02T10:00:00.000Z',
            canonical => 'https://medium.com/@me/zipped-1a2b3c4d5e6f', body => '<p>From a zip.</p>'));
        spew("$export/medium-export/posts/draft_Later-aaaaaaaaaaaa.html", story(title => 'Later', body => '<p>Soon.</p>'));
        spew("$export/medium-export/README.html", "<p>readme</p>");
        system("cd '$export' && zip -q -r '$old/export.zip' medium-export") == 0 or die "zip failed";
        my ($state, $out) = run_import('medium', "$old/export.zip", loud => 1);
        is_deeply([ sort map { $_->{file} } @{$state->{pages}} ], ['_source/blog/later.html', '_source/blog/zipped.html'], 'imported from the zip');
        is(body('_source/blog/zipped.html'), "<p>From a zip.</p>\n", 'the story');
        is(front('_source/blog/later.html')->{draft}, 1, 'the draft');
        is($out, "Imported 2 posts and 0 pages into _source (1 as drafts).\nRun \"dapper check\" to find links that need fixing.\n", 'the report');

        spew("$old/upper.ZIP", slurp("$old/export.zip", ':raw'), ':raw');
        make_site({});
        $state = run_import('medium', "$old/upper.ZIP");
        is(scalar @{$state->{pages}}, 2, '.ZIP in capitals');

        spew("$old/broken.zip", "not a zip", ':raw');
        my $error;
        {
            open(my $saved, '>&', \*STDERR) or die;
            open(STDERR, '>', File::Spec->devnull) or die;
            eval { run_import('medium', "$old/broken.zip") };
            $error = $@;
            open(STDERR, '>&', $saved) or die;
        }
        is($error, "error: could not unzip $old/broken.zip (is unzip installed?)\n", 'a zip that cannot be opened');

        my $empty = tempdir(CLEANUP => 1);
        spew("$empty/x/readme.txt", "x");
        system("cd '$empty' && zip -q -r '$old/empty.zip' x") == 0 or die "zip failed";
        eval { run_import('medium', "$old/empty.zip") };
        is($@, "error: there are no stories in $old/empty.zip (Medium's export has them in a posts folder)\n", 'a zip with no stories');
    }
};

subtest '--to, dry runs and errors' => sub {
    my $old = project();
    spew("$old/posts/a.html", story(title => 'A', date => '2021-01-01T00:00:00.000Z', body => '<p>x</p>'));
    my ($state, $out) = run_import('medium', $old, to => 'stories', dry_run => 1, loud => 1);
    is_deeply([ map { $_->{file} } @{$state->{pages}} ], ['_source/stories/a.html'], 'into --to');
    ok(!-e '_source/stories', 'nothing written');
    is($out, "Would import 1 post and 0 pages into _source.\n", 'the report');

    spew("$old/export.tar.gz", "x");
    eval { run_import('medium', "$old/export.tar.gz") };
    is($@, "error: give Medium's export (the .zip file, or the folder it unzips to)\n", 'not a zip');
    my $empty = tempdir(CLEANUP => 1);
    eval { run_import('medium', $empty) };
    is($@, "error: there are no stories in $empty (Medium's export has them in a posts folder)\n", 'a folder with no stories');
};

done_testing();
