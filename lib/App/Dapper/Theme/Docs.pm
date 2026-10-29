package App::Dapper::Theme::Docs;

=head1 NAME

App::Dapper::Theme::Docs - A documentation starter for "dapper init --template docs".

=head1 DESCRIPTION

Documentation pages with a sidebar built from C<_data/nav.yml>, previous and
next links in the same order, highlighted code, and optional search. Every
page must match C<_source/_schema.yml>.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

=head2 description

A one-line description of the theme.

=cut

sub description { 'Documentation: a sidebar from a data file, previous and next links, code highlighting and search' }

=head2 notes

Notes about the theme for AGENTS.md.

=cut

sub notes {
    return <<'NOTES';
## About these docs

- Every page is Markdown with a `title` and a `description`; they live in
  `_source/` (sections can be folders, like `_source/guide/`).
- **The sidebar is `_data/nav.yml`.** When you add, move or remove a page, update
  it too: it decides the sidebar and the previous and next links. A page that
  isn't in it can still be reached by URL, but readers won't find it.
- Use fenced code blocks with a language (```` ```bash ````) so they are
  highlighted.
- Set `search: true` in `_config.yml` (with Pagefind installed) to add search.
NOTES
}

=head2 files

Returns the theme's files, as a hash of path to content.

=cut

sub files {
    return {
        '_config.yml' => <<'FILE',
# Dapper configuration file. See https://github.com/markdbenson/dapper
---
name: Widget Docs
description: How to install, configure and use Widget.

# The address the site will be published at, without a trailing slash.
url: https://example.com

# Set to true to build a search index with Pagefind (https://pagefind.app).
search: false

# Where "dapper deploy" publishes the site. Uncomment "deploy:" and one
# of the targets below. See "Deploying with dapper deploy" in the README.
#deploy:
#  s3:
#    bucket: example.com
#  github_pages:
#    branch: gh-pages
#  command: rsync -av --delete _output/ me@example.com:/var/www/site/
FILE

        '_data/nav.yml' => <<'FILE',
# The sidebar, in reading order (site.data.nav). Each page's url must match
# its address on the site.
- section: Introduction
  pages:
    - title: Overview
      url: /
    - title: Getting Started
      url: /getting-started.html
- section: Guide
  pages:
    - title: Configuration
      url: /guide/configuration.html
    - title: Writing Pages
      url: /guide/writing-pages.html
FILE

        '_layout/index.html' => <<'FILE',
---
description: "Every docs page: sidebar from _data/nav.yml, the page, and previous and next links"
---
[% all = [] %][% FOR section IN site.data.nav %][% FOR p IN section.pages %][% all.push(p) %][% END %][% END %]
[% here = -1 %][% i = 0 %][% FOR p IN all %][% IF p.url == page.url %][% here = i %][% END %][% i = i + 1 %][% END %]
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>[% page.title | html %] - [% site.name | html %]</title>
[% page.seo %]
  <link rel="stylesheet" href="/css/site.css">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css" media="(prefers-color-scheme: light)">
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css" media="(prefers-color-scheme: dark)">
[% IF site.search %]
  <link rel="stylesheet" href="/pagefind/pagefind-ui.css">
[% END %]
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
  <header class="site-header">
    <a class="site-name" href="/">[% site.name | html %]</a>
[% IF site.search %]
    <div id="search"></div>
[% END %]
  </header>
  <div class="layout">
    <nav class="sidebar" aria-label="Documentation">
[% FOR section IN site.data.nav %]
      <h2>[% section.section | html %]</h2>
      <ul>
[% FOR p IN section.pages %]
        <li><a href="[% p.url %]"[% IF p.url == page.url %] aria-current="page"[% END %]>[% p.title | html %]</a></li>
[% END %]
      </ul>
[% END %]
    </nav>
    <main id="main" data-pagefind-body>
      <h1>[% page.title | html %]</h1>
[% page.content %]
      <nav class="pager" aria-label="Previous and next">
[% IF here > 0 %][% before = here - 1 %][% earlier = all.$before %]
        <a class="prev" href="[% earlier.url %]">&larr; [% earlier.title | html %]</a>
[% END %]
[% IF here >= 0 AND here < all.size - 1 %][% after = here + 1 %][% later = all.$after %]
        <a class="next" href="[% later.url %]">[% later.title | html %] &rarr;</a>
[% END %]
      </nav>
    </main>
  </div>
  <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
  <script>hljs.highlightAll();</script>
[% IF site.search %]
  <script src="/pagefind/pagefind-ui.js"></script>
  <script>new PagefindUI({ element: "#search", showSubResults: true });</script>
[% END %]
</body>
</html>
FILE

        '_source/_schema.yml' => <<'FILE',
# Every docs page must have these. Run "dapper check" to see any problems.
required: [title, description]
fields:
  title:
    type: string
    max_length: 70
  description:
    type: string
    max_length: 200
FILE

        '_source/index.md' => <<'FILE',
---
title: Overview
description: What Widget is, and where to start.
---

Widget turns your notes into tidy reports. These docs show you how to install
it, set it up and get the most from it.

- New to Widget? Start with [Getting Started](/getting-started.html).
- Setting it up for a team? See [Configuration](/guide/configuration.html).

Replace these pages with your own: edit the Markdown in `_source/`, and the
sidebar in `_data/nav.yml`.
FILE

        '_source/getting-started.md' => <<'FILE',
---
title: Getting Started
description: Install Widget and make your first report in five minutes.
---

## Install

```bash
curl -fsSL https://example.com/install.sh | sh
```

## Make a report

```bash
widget report notes/ --out report.html
```

Open `report.html` in your browser. Next, read about
[configuration](/guide/configuration.html).
FILE

        '_source/guide/configuration.md' => <<'FILE',
---
title: Configuration
description: Every setting in widget.yml, with examples.
---

Widget reads `widget.yml` in the current directory:

```yaml
title: Weekly report
include:
  - notes/*.md
```

Setting   | Meaning
----------|---------------------------------------
`title`   | The report's title
`include` | Which files to read, as glob patterns
FILE

        '_source/guide/writing-pages.md' => <<'FILE',
---
title: Writing Pages
description: How to write notes that make good reports.
---

Write one note per topic, starting with a heading. Widget uses the first
paragraph of each note as its summary.

> Short notes make better reports than long ones.
FILE

        'css/site.css' => <<'FILE',
:root {
  --bg: #ffffff;
  --text: #1f2328;
  --muted: #59636e;
  --accent: #0b62c4;
  --sidebar: #f6f8fa;
  --border: #d1d9e0;
  --code: #f6f8fa;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0d1117;
    --text: #e6edf3;
    --muted: #9198a1;
    --accent: #58a6ff;
    --sidebar: #151b23;
    --border: #2f3742;
    --code: #151b23;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 17px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
a { color: var(--accent); }
a:focus-visible { outline: 3px solid var(--accent); outline-offset: 2px; }
.skip { position: absolute; left: -999px; }
.skip:focus { left: 1rem; top: 1rem; background: var(--bg); padding: .5rem 1rem; }
.site-header { display: flex; justify-content: space-between; align-items: center; gap: 1rem; padding: 1rem 1.5rem; border-bottom: 1px solid var(--border); }
.site-name { font-weight: 700; color: var(--text); text-decoration: none; }
#search { min-width: 16rem; }
.layout { display: grid; grid-template-columns: 16rem minmax(0, 1fr); max-width: 76rem; margin: 0 auto; }
.sidebar { background: var(--sidebar); border-right: 1px solid var(--border); padding: 1.5rem; min-height: calc(100vh - 4rem); }
.sidebar h2 { font-size: .8rem; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); margin: 1.5rem 0 .5rem; }
.sidebar h2:first-child { margin-top: 0; }
.sidebar ul { list-style: none; margin: 0; padding: 0; }
.sidebar a { display: block; padding: .25rem .5rem; border-radius: 6px; color: var(--text); text-decoration: none; }
.sidebar a:hover { background: var(--border); }
.sidebar a[aria-current="page"] { background: var(--accent); color: var(--bg); }
main { padding: 2rem 2.5rem 3rem; max-width: 50rem; }
main h1 { margin-top: 0; }
pre, code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .9em; }
pre { background: var(--code); border: 1px solid var(--border); border-radius: 8px; padding: 1rem; overflow-x: auto; }
pre code.hljs { background: transparent; padding: 0; }
:not(pre) > code { background: var(--code); padding: .1em .35em; border-radius: 4px; }
table { border-collapse: collapse; }
th, td { border: 1px solid var(--border); padding: .4rem .75rem; text-align: left; }
blockquote { margin: 0; padding: .25rem 1rem; border-left: 4px solid var(--accent); color: var(--muted); }
.pager { display: flex; justify-content: space-between; gap: 1rem; margin-top: 3rem; padding-top: 1.5rem; border-top: 1px solid var(--border); }
.pager .next { margin-left: auto; }
@media (max-width: 760px) {
  .layout { grid-template-columns: 1fr; }
  .sidebar { min-height: 0; border-right: 0; border-bottom: 1px solid var(--border); }
  main { padding: 1.5rem 1.25rem; }
}
FILE
    };
}

1;
