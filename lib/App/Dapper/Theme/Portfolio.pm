package App::Dapper::Theme::Portfolio;

=head1 NAME

App::Dapper::Theme::Portfolio - A portfolio starter for "dapper init --template portfolio".

=head1 DESCRIPTION

A home page with an introduction and a grid of projects, a page per project
with its image and details, and about and contact pages. Projects live in
C<_source/projects/> and must match C<_source/projects/_schema.yml>.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

=head2 description

A one-line description of the theme.

=cut

sub description { 'A portfolio: a grid of projects with images, and about and contact pages' }

=head2 notes

Notes about the theme for AGENTS.md.

=cut

sub notes {
    return <<'NOTES';
## About this portfolio

- Each project is a Markdown file in `_source/projects/` with `layout: project`,
  `categories: projects`, a `title`, a `date`, a `description` (one sentence,
  shown on its card) and an `image` (shown on its card and at the top of its
  page). `role`, `client` and `link` are optional.
- Project images go in `images/` (any format; 1200x800 works well). Every image
  needs alt text, set with `image_alt`.
- The home page (`_source/index.html`) shows every project, newest first.
- Contact details and social links are in `_data/profile.yml`.
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
name: Alex Rivera
description: Designer and illustrator making identities, books and posters.
author: Alex Rivera

# The address the site will be published at, without a trailing slash.
url: https://example.com

# The default image when the site is shared on social media.
image: /images/project-1.svg

timezone: America/Chicago
FILE

        '_data/profile.yml' => <<'FILE',
# Shown in the header, the footer and on the contact page (site.data.profile)
tagline: Designer and illustrator
email: hello@example.com
location: Chicago, Illinois
links:
  - label: Instagram
    url: https://instagram.com/
  - label: LinkedIn
    url: https://linkedin.com/
FILE

        '_layout/index.html' => <<'FILE',
---
description: The page wrapper used by every page (header, footer, SEO tags)
---
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>[% IF page.title AND page.url != '/' %][% page.title | html %] - [% END %][% site.name | html %]</title>
[% page.seo %]
  <link rel="stylesheet" href="/css/site.css">
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
  <header class="site-header">
    <a class="site-name" href="/">[% site.name | html %]</a>
    <nav aria-label="Main">
      <a href="/">Work</a>
      <a href="/about.html">About</a>
      <a href="/contact.html">Contact</a>
    </nav>
  </header>
  <main id="main">
[% page.content %]
  </main>
  <footer class="site-footer">
    <p>&copy; [% site.time.year %] [% site.author | html %]</p>
    <p>
[% FOR link IN site.data.profile.links %]
      <a href="[% link.url %]">[% link.label | html %]</a>
[% END %]
    </p>
  </footer>
</body>
</html>
FILE

        '_layout/project.html' => <<'FILE',
---
layout: index
description: A project page, with its image, details and write-up
---
<article class="project">
  <header>
    <h1>[% page.title | html %]</h1>
    <p class="lede">[% page.description | html %]</p>
    <dl class="details">
[% IF page.client %]
      <dt>Client</dt><dd>[% page.client | html %]</dd>
[% END %]
[% IF page.role %]
      <dt>Role</dt><dd>[% page.role | html %]</dd>
[% END %]
      <dt>Year</dt><dd>[% page.year %]</dd>
    </dl>
  </header>
  <img class="hero" src="[% page.image %]" alt="[% page.image_alt | html %]">
  <div class="prose">
[% page.content %]
  </div>
[% IF page.link %]
  <p><a class="button" href="[% page.link %]">See the project</a></p>
[% END %]
  <p><a href="/">&larr; All work</a></p>
</article>
FILE

        '_source/index.html' => <<'FILE',
---
title: Work
description: Identities, books and posters by Alex Rivera.
template: true
---
<section class="intro">
  <h1>[% site.data.profile.tagline | html %]</h1>
  <p>[% site.description | html %]</p>
</section>

<ul class="grid" role="list">
[% FOR project IN site.categories.projects.reverse %]
  <li class="card">
    <a href="[% project.url %]">
      <img src="[% project.image %]" alt="[% project.image_alt | html %]" loading="lazy">
      <h2>[% project.title | html %]</h2>
      <p>[% project.description | html %]</p>
    </a>
  </li>
[% END %]
</ul>
FILE

        '_source/about.md' => <<'FILE',
---
title: About
description: About Alex Rivera, a designer and illustrator in Chicago.
---

# About

I'm Alex, a designer and illustrator in Chicago. I make identities, books and
posters for studios, publishers and small businesses.

Edit `_source/about.md` to tell visitors who you are, what you do, and who you
like working with.
FILE

        '_source/contact.html' => <<'FILE',
---
title: Contact
description: How to get in touch with Alex Rivera.
template: true
---
<h1>Contact</h1>
<p>I'm taking on new projects. The best way to reach me is by email.</p>
<p><a class="button" href="mailto:[% site.data.profile.email %]">[% site.data.profile.email %]</a></p>
<p>Based in [% site.data.profile.location | html %].</p>
FILE

        '_source/projects/_schema.yml' => <<'FILE',
# Every project must have these. Run "dapper check" to see any problems.
required: [title, date, categories, description, image, image_alt]
fields:
  title:
    type: string
    max_length: 80
  date:
    type: date
  categories:
    type: list
    values: [projects]
  description:
    type: string
    max_length: 160
  image:
    type: string
    pattern: '^/'
  image_alt:
    type: string
    min_length: 5
  role:
    type: string
  client:
    type: string
  link:
    type: string
FILE

        '_source/projects/riverside-books.md' => <<'FILE',
---
title: Riverside Books
layout: project
categories: projects
date: 2026-03-01
description: A new identity and shop signage for an independent bookshop.
image: /images/project-1.svg
image_alt: The Riverside Books logo in blue on a cream background
client: Riverside Books
role: Identity and signage
---

Riverside Books wanted to look as welcoming as it feels inside. We built the
identity around a hand-drawn river line that wraps the name, and carried it
onto the shop sign, bags and bookmarks.

Replace this project with your own: change the text, put your image in
`images/`, and update the front matter.
FILE

        '_source/projects/night-market.md' => <<'FILE',
---
title: Night Market Posters
layout: project
categories: projects
date: 2025-09-15
description: A series of posters for a summer night market.
image: /images/project-2.svg
image_alt: Three posters with lanterns in orange and deep purple
client: Westside Night Market
role: Illustration
---

Three posters for the market's summer season, one for each month, sharing a
palette of lantern orange and late-evening purple.
FILE

        'images/project-1.svg' => <<'FILE',
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 800" role="img" aria-label="Placeholder image"><rect width="1200" height="800" fill="#f3efe6"/><path d="M0 520 C 300 420 500 640 800 520 S 1100 420 1200 480 V800 H0Z" fill="#2f5d8a"/><text x="600" y="380" font-family="Georgia, serif" font-size="96" text-anchor="middle" fill="#2f5d8a">Riverside</text></svg>
FILE

        'images/project-2.svg' => <<'FILE',
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 800" role="img" aria-label="Placeholder image"><rect width="1200" height="800" fill="#2b1840"/><circle cx="300" cy="320" r="90" fill="#f28c28"/><circle cx="600" cy="260" r="110" fill="#f6a443"/><circle cx="900" cy="330" r="80" fill="#f28c28"/><text x="600" y="620" font-family="Georgia, serif" font-size="88" text-anchor="middle" fill="#f6a443">Night Market</text></svg>
FILE

        'css/site.css' => <<'FILE',
:root {
  --bg: #fbfaf7;
  --text: #1d1d1f;
  --muted: #5f5f66;
  --accent: #2f5d8a;
  --card: #ffffff;
  --border: #e6e2d9;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #121214;
    --text: #ececef;
    --muted: #a3a3ad;
    --accent: #8fb8e6;
    --card: #1c1c20;
    --border: #2c2c33;
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--text);
  font: 18px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
}
a { color: var(--accent); }
a:focus-visible, .button:focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; }
.skip { position: absolute; left: -999px; }
.skip:focus { left: 1rem; top: 1rem; background: var(--card); padding: .5rem 1rem; }
.site-header, main, .site-footer { max-width: 72rem; margin: 0 auto; padding: 0 1.25rem; }
.site-header { display: flex; flex-wrap: wrap; gap: 1rem; justify-content: space-between; align-items: baseline; padding-top: 1.5rem; padding-bottom: 2rem; }
.site-name { font-weight: 700; font-size: 1.25rem; color: var(--text); text-decoration: none; }
.site-header nav { display: flex; flex-wrap: wrap; gap: .4rem 1.25rem; }
.site-header nav a { color: var(--text); text-decoration: none; }
.site-header nav a:hover { color: var(--accent); }
.intro { max-width: 40rem; margin-bottom: 2.5rem; }
.intro h1 { font-size: clamp(2rem, 5vw, 3.25rem); line-height: 1.1; margin: 0 0 .5rem; }
.intro p { color: var(--muted); font-size: 1.15rem; margin: 0; }
.grid { list-style: none; padding: 0; margin: 0; display: grid; gap: 1.5rem; grid-template-columns: repeat(auto-fill, minmax(18rem, 1fr)); }
.card a { display: block; background: var(--card); border: 1px solid var(--border); border-radius: 12px; overflow: hidden; color: var(--text); text-decoration: none; transition: transform .15s ease; }
.card a:hover { transform: translateY(-3px); }
.card img { display: block; width: 100%; aspect-ratio: 3 / 2; object-fit: cover; }
.card h2 { font-size: 1.15rem; margin: 1rem 1rem .25rem; }
.card p { color: var(--muted); margin: 0 1rem 1.25rem; font-size: .95rem; }
.project header { max-width: 44rem; }
.project h1 { font-size: clamp(2rem, 4vw, 2.75rem); line-height: 1.15; margin-bottom: .25rem; }
.lede { color: var(--muted); font-size: 1.2rem; margin-top: 0; }
.details { display: grid; grid-template-columns: max-content 1fr; gap: .25rem 1rem; color: var(--muted); }
.details dt { font-weight: 600; color: var(--text); }
.details dd { margin: 0; }
.hero { display: block; width: 100%; border-radius: 12px; margin: 2rem 0; }
.prose { max-width: 44rem; }
.button { display: inline-block; background: var(--accent); color: var(--bg); padding: .6rem 1.2rem; border-radius: 8px; text-decoration: none; font-weight: 600; }
.site-footer { margin-top: 4rem; padding-top: 1.5rem; padding-bottom: 2rem; border-top: 1px solid var(--border); color: var(--muted); display: flex; flex-wrap: wrap; justify-content: space-between; }
.site-footer a { margin-left: 1rem; color: var(--muted); }
FILE
    };
}

1;
