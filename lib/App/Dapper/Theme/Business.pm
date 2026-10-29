package App::Dapper::Theme::Business;

=head1 NAME

App::Dapper::Theme::Business - A small business starter for "dapper init --template business".

=head1 DESCRIPTION

A home page with services, opening hours and contact details, a news section,
and about and contact pages. Everything about the business (its address,
hours and services) lives in one data file, C<_data/business.yml>, which also
feeds the structured data search engines and AI tools read.

=cut

use utf8;
use 5.010;
use strict;
use warnings;

=head2 description

A one-line description of the theme.

=cut

sub description { 'A small business: services, opening hours, contact details and news, from one data file' }

=head2 notes

Notes about the theme for AGENTS.md.

=cut

sub notes {
    return <<'NOTES';
## About this business site

- **Everything about the business is in `_data/business.yml`:** name, tagline,
  phone, email, address, opening hours and services. Change it there and every
  page (and the structured data search engines read) updates. Don't copy these
  details into pages.
- Hours are a list of `days` and `hours` (`hours: Closed` for closed days);
  holiday changes go in `notice`, which shows as a banner on every page.
- News posts go in `_source/news/` with `layout: post`, `categories: news`, a
  `title`, a `date` and a `description`. The news page (`_source/news.html`) lists them, newest first.
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
name: Hearth & Crumb Bakery
description: A neighborhood bakery making sourdough, pastries and coffee every morning.
author: Hearth & Crumb Bakery

# The address the site will be published at, without a trailing slash.
url: https://example.com

image: /images/storefront.svg
timezone: America/Chicago

feed:
  category: news

# Where "dapper deploy" publishes the site. Uncomment "deploy:" and one
# of the targets below. See "Deploying with dapper deploy" in the README.
#deploy:
#  s3:
#    bucket: example.com
#  github_pages:
#    branch: gh-pages
#  command: rsync -av --delete _output/ me@example.com:/var/www/site/
FILE

        '_data/business.yml' => <<'FILE',
# Everything about the business, used on every page (site.data.business)
name: Hearth & Crumb Bakery
tagline: Bread, pastries and coffee, baked here every morning.
phone: (312) 555-0142
email: hello@example.com
address:
  street: 1418 W Division St
  city: Chicago
  region: IL
  postcode: "60642"
  country: US
map: https://www.openstreetmap.org/search?query=1418%20W%20Division%20St%20Chicago

# A short notice shown at the top of every page, such as holiday hours.
# Leave it empty when there is nothing to say.
notice: ""

hours:
  - days: Tuesday to Friday
    hours: 7am to 3pm
  - days: Saturday and Sunday
    hours: 8am to 2pm
  - days: Monday
    hours: Closed

services:
  - name: Sourdough
    description: Country loaves, rye and seeded sourdough, from our own starter.
  - name: Pastries
    description: Croissants, cardamom buns and seasonal fruit tarts.
  - name: Coffee
    description: Espresso and filter coffee from a roaster down the street.
  - name: Special orders
    description: Birthday cakes and catering trays, with three days' notice.
FILE

        '_layout/index.html' => <<'FILE',
---
description: The page wrapper used by every page (header, notice, footer with hours and address, SEO tags)
---
[% b = site.data.business %]<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>[% IF page.title AND page.url != '/' %][% page.title | html %] - [% END %][% b.name | html %]</title>
[% page.seo %]
[% ld = {
  '@context' => 'https://schema.org',
  '@type' => 'LocalBusiness',
  'name' => b.name,
  'description' => site.description,
  'url' => site.url,
  'telephone' => b.phone,
  'email' => b.email,
  'address' => {
    '@type' => 'PostalAddress',
    'streetAddress' => b.address.street,
    'addressLocality' => b.address.city,
    'addressRegion' => b.address.region,
    'postalCode' => b.address.postcode,
    'addressCountry' => b.address.country,
  },
} %]
  <script type="application/ld+json">[% ld.json %]</script>
  <link rel="stylesheet" href="/css/site.css">
</head>
<body>
  <a class="skip" href="#main">Skip to content</a>
[% IF b.notice %]
  <p class="notice" role="status">[% b.notice | html %]</p>
[% END %]
  <header class="site-header">
    <a class="site-name" href="/">[% b.name | html %]</a>
    <nav aria-label="Main">
      <a href="/">Home</a>
      <a href="/news.html">News</a>
      <a href="/about.html">About</a>
      <a href="/contact.html">Contact</a>
    </nav>
  </header>
  <main id="main">
[% page.content %]
  </main>
  <footer class="site-footer">
    <div>
      <h2>Hours</h2>
      <dl class="hours">
[% FOR row IN b.hours %]
        <dt>[% row.days | html %]</dt><dd>[% row.hours | html %]</dd>
[% END %]
      </dl>
    </div>
    <div>
      <h2>Visit</h2>
      <address>
        [% b.address.street | html %]<br>
        [% b.address.city | html %], [% b.address.region | html %] [% b.address.postcode | html %]<br>
        <a href="tel:[% b.phone | html %]">[% b.phone | html %]</a><br>
        <a href="mailto:[% b.email | html %]">[% b.email | html %]</a>
      </address>
    </div>
    <p class="copyright">&copy; [% site.time.year %] [% b.name | html %]</p>
  </footer>
</body>
</html>
FILE

        '_layout/post.html' => <<'FILE',
---
layout: index
description: A news post
---
<article class="prose">
  <h1>[% page.title | html %]</h1>
  <p class="meta">[% page.date.strftime('%d %B %Y') %]</p>
  [% page.content %]
  <p><a href="/news.html">&larr; All news</a></p>
</article>
FILE

        '_source/index.html' => <<'FILE',
---
title: Home
description: A neighborhood bakery in Chicago making sourdough, pastries and coffee every morning.
template: true
---
[% b = site.data.business %]
<section class="hero">
  <img src="/images/storefront.svg" alt="The front of the bakery, with loaves in the window" width="1200" height="600">
  <div>
    <h1>[% b.tagline | html %]</h1>
    <p><a class="button" href="/contact.html">Find us</a></p>
  </div>
</section>

<section aria-labelledby="services">
  <h2 id="services">What we make</h2>
  <ul class="services" role="list">
[% FOR s IN b.services %]
    <li>
      <h3>[% s.name | html %]</h3>
      <p>[% s.description | html %]</p>
    </li>
[% END %]
  </ul>
</section>

[% IF site.categories.news %]
<section aria-labelledby="latest">
  <h2 id="latest">Latest news</h2>
[% FOR post IN site.categories.news.reverse %][% LAST IF loop.count > 3 %]
  <p><a href="[% post.url %]">[% post.title | html %]</a> <span class="meta">[% post.date.strftime('%d %B') %]</span></p>
[% END %]
</section>
[% END %]
FILE

        '_source/about.md' => <<'FILE',
---
title: About
description: The story of Hearth & Crumb, a neighborhood bakery in Chicago.
---

# About us

We opened Hearth & Crumb in 2019 with one oven and a sourdough starter called
Gus. We still bake everything here, every morning, and we still feed Gus.

Edit `_source/about.md` to tell your own story.
FILE

        '_source/contact.html' => <<'FILE',
---
title: Contact
description: Hearth & Crumb's address, phone number, email and opening hours.
template: true
---
[% b = site.data.business %]
<div class="prose">
<h1>Find us</h1>
<p>
  [% b.address.street | html %], [% b.address.city | html %]<br>
  <a href="[% b.map %]">Open in a map</a>
</p>
<p>Call <a href="tel:[% b.phone | html %]">[% b.phone | html %]</a> or email
<a href="mailto:[% b.email | html %]">[% b.email | html %]</a>. For special orders,
please give us three days' notice.</p>
</div>
FILE

        '_source/news.html' => <<'FILE',
---
title: News
description: News from Hearth & Crumb Bakery.
template: true
paginate:
  category: news
  per_page: 10
---
<div class="prose">
<h1>News</h1>
[% FOR post IN paginator.items %]
<article>
  <h2><a href="[% post.url %]">[% post.title | html %]</a></h2>
  <p class="meta">[% post.date.strftime('%d %B %Y') %]</p>
  [% post.excerpt %]
</article>
[% END %]
[% IF paginator.next_url %]<p><a href="[% paginator.next_url %]">Older news</a></p>[% END %]
</div>
FILE

        '_source/news/_schema.yml' => <<'FILE',
# Every news post must have these. Run "dapper check" to see any problems.
required: [title, date, categories, description]
fields:
  title:
    type: string
    max_length: 90
  date:
    type: date
  categories:
    type: list
    values: [news]
  description:
    type: string
    max_length: 200
FILE

        '_source/news/now-open-sundays.md' => <<'FILE',
---
title: Now Open on Sundays
layout: post
categories: news
date: 2026-02-01
description: Starting in February, Hearth & Crumb is open on Sundays from 8am to 2pm.
---

Good news for weekend mornings: starting in February, we're open on Sundays
from 8am to 2pm, with the full bread and pastry lineup.
FILE

        'images/storefront.svg' => <<'FILE',
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 600" role="img" aria-label="Placeholder image of a storefront"><rect width="1200" height="600" fill="#f4e9dc"/><rect x="200" y="140" width="800" height="400" rx="8" fill="#8a4b2a"/><rect x="260" y="230" width="320" height="250" fill="#fbe3c0"/><rect x="640" y="230" width="300" height="310" fill="#5c2f1a"/><circle cx="340" cy="420" r="38" fill="#c98a4b"/><circle cx="430" cy="420" r="38" fill="#b87538"/><circle cx="520" cy="420" r="38" fill="#c98a4b"/><text x="600" y="200" font-family="Georgia, serif" font-size="44" text-anchor="middle" fill="#fbe3c0">Hearth &amp; Crumb</text></svg>
FILE

        'css/site.css' => <<'FILE',
:root {
  --bg: #fffaf3;
  --text: #2a1d16;
  --muted: #6d5a4f;
  --accent: #9c4a1f;
  --accent-text: #ffffff;
  --panel: #f4e9dc;
  --notice: #ffe7a8;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #18120e;
    --text: #f3e9df;
    --muted: #c2ae9f;
    --accent: #e89b6c;
    --accent-text: #18120e;
    --panel: #261c16;
    --notice: #5a4513;
  }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text); font: 18px/1.6 Georgia, "Iowan Old Style", serif; }
h1, h2, h3, .site-name, nav, .button { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
a { color: var(--accent); }
a:focus-visible { outline: 3px solid var(--accent); outline-offset: 3px; }
.skip { position: absolute; left: -999px; }
.skip:focus { left: 1rem; top: 1rem; background: var(--bg); padding: .5rem 1rem; }
.notice { margin: 0; padding: .6rem 1rem; text-align: center; background: var(--notice); font-family: sans-serif; }
.site-header, main, .site-footer { max-width: 68rem; margin: 0 auto; padding: 0 1.25rem; }
.site-header { display: flex; flex-wrap: wrap; justify-content: space-between; align-items: baseline; gap: 1rem; padding-top: 1.5rem; padding-bottom: 1.5rem; }
.site-name { font-weight: 800; font-size: 1.3rem; color: var(--text); text-decoration: none; }
.site-header nav { display: flex; flex-wrap: wrap; gap: .4rem 1.25rem; }
.site-header nav a { color: var(--text); text-decoration: none; }
.site-header nav a:hover { color: var(--accent); }
.hero { display: grid; gap: 1.5rem; align-items: center; grid-template-columns: 3fr 2fr; margin-bottom: 3rem; }
.hero img { width: 100%; height: auto; border-radius: 14px; }
.hero h1 { font-size: clamp(1.8rem, 4vw, 2.8rem); line-height: 1.15; margin: 0 0 1rem; }
@media (max-width: 720px) { .hero { grid-template-columns: 1fr; } }
.button { display: inline-block; background: var(--accent); color: var(--accent-text); padding: .65rem 1.3rem; border-radius: 999px; text-decoration: none; font-weight: 700; }
.services { list-style: none; padding: 0; display: grid; gap: 1rem; grid-template-columns: repeat(auto-fit, minmax(14rem, 1fr)); }
.services li { background: var(--panel); border-radius: 12px; padding: 1rem 1.25rem; }
.services h3 { margin: 0 0 .25rem; }
.services p { margin: 0; color: var(--muted); }
.prose { max-width: 42rem; }
.meta { color: var(--muted); font-size: .9em; }
.site-footer { margin-top: 4rem; padding-top: 2rem; padding-bottom: 2rem; border-top: 2px solid var(--panel); display: grid; gap: 2rem; grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr)); }
.site-footer h2 { font-size: 1rem; text-transform: uppercase; letter-spacing: .06em; color: var(--muted); }
.hours { display: grid; grid-template-columns: max-content 1fr; gap: .2rem 1rem; margin: 0; }
.hours dt { font-weight: 600; }
.hours dd { margin: 0; white-space: nowrap; }
address { font-style: normal; }
.copyright { grid-column: 1 / -1; color: var(--muted); font-size: .9rem; margin: 0; }
FILE
    };
}

1;
