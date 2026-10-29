# Dapper Roadmap

This is the plan for making Dapper the best tool for people who want to
build static websites quickly with an AI assistant, and publish them
wherever they like.

## The idea

**Describe the site you want to your AI assistant; Dapper makes it real,
keeps it correct, and publishes it wherever you like.**

Dapper doesn't contain an AI and never charges for one. It works with the
assistant a person already uses (Claude, ChatGPT, Cursor, or anything that
speaks MCP or can run a command), and gives that assistant what it needs to
do good work safely: clear conventions, guardrails, checks that explain what
is wrong, and a fast loop from edit to preview to publish.

## Principles

1. **You own everything.** A site is plain files: Markdown, HTML, YAML and
   CSS. No database, no account, no lock-in. Any host that serves files
   works.
2. **Safe by default.** Content is never run as code. AI changes are checked
   against schemas before they're written, and `dapper check` must pass
   before a deploy.
3. **Explain, don't just fail.** Every error names the file, says what is
   wrong, and is available as JSON, so an assistant can fix it without help.
4. **Bring your own AI.** Dapper meets assistants where they are: MCP for
   assistants that support it, `AGENTS.md` for coding agents, `--json` for
   scripts.
5. **Small and durable.** Dapper has run since 2002. New features earn their
   place, and a site built today should still build in ten years.

## Who it's for

- **People who want a site, not a website project:** a bakery, a band, a
  consultant, a club, a portfolio. They use an AI assistant and want the
  result to look good and stay current.
- **Writers and bloggers** who want Markdown, a feed and a fast site without
  running WordPress.
- **Developers and documentation teams** who want a small, scriptable
  generator that their agents can drive.

## What a session looks like

1. Install Dapper in one line (single file, Homebrew or Docker).
2. `dapper init --template business` (or a theme from a git URL).
3. Ask your assistant: "Make this the site for my bakery. Here are our
   hours, and here's our menu." It reads `AGENTS.md` (or uses Dapper's MCP
   tools), writes pages that match the schemas, and runs `dapper check`.
4. `dapper serve` shows the site; the browser reloads as the assistant
   edits.
5. `dapper deploy` publishes only what changed, to S3, GitHub Pages or any
   host.
6. Months later: "Post Saturday's event recap with these photos." The
   assistant knows how, because the project explains itself.

## Where 1.0 stands

Done in 1.0: safe content, front matter schemas, data files, pagination,
category and tag pages, a sitemap, an Atom feed, SEO and structured data
tags, Markdown copies and `llms.txt`, Pagefind search, `dapper check
--json`, the MCP server, clean output, live reload, the blog starter, and
installs as a single file, a Docker image and a Homebrew formula.

The biggest gaps for real users are **design** (only one theme),
**publishing** (deploying is left to the user), **images** (no resizing or
alt text checks), and **guidance for assistants** (they have to discover
Dapper's conventions on their own).

## Releases

### 1.1: Assistants, themes and deploy

Make assistants good at Dapper from the first minute, give people good
looking starting points, and make publishing one command.

- **AGENTS.md in every project.** `dapper init` writes an `AGENTS.md` that
  explains the project to coding agents: where pages, layouts and data live,
  the schemas, safe content, and the edit, check, build loop. A `CLAUDE.md`
  points Claude Code at it. `dapper agents` regenerates it for existing
  sites.
- **MCP prompts and resources.** Prompts for the common jobs (start a new
  site, write a post, audit the site) and resources an assistant can read
  (the Dapper guide, the project file, the schemas).
- **More MCP tools.** `rename_page` (moves a page and adds a redirect from
  its old URL), `read_layout` and `write_layout` (a layout is checked before
  it is saved).
- **Redirects.** `redirects` in `_config.yml` or `_data/redirects.yml` map
  old URLs to new ones; Dapper writes a small redirect page at each old URL,
  and `check` makes sure each target exists.
- **Themes.** Three more starters alongside `blog`: `portfolio`,
  `business` (hours, services and contact details from data files) and
  `docs` (a sidebar from a data file). Each is responsive, accessible, has a
  dark mode, and ships with a schema and an `AGENTS.md` that explains how to
  fill it in.
- **Themes from anywhere.** `dapper init --template` takes a built-in name,
  a local directory or a git URL, so anyone can publish a theme.
- **`dapper deploy`.** Publishes the output directory after a successful
  build and check:
  - **Amazon S3**, through the AWS CLI (`aws s3 sync --delete`), with an
    optional CloudFront invalidation.
  - **GitHub Pages**: commits the output to a branch (with `.nojekyll`
    and an optional `CNAME`) and pushes it, keeping the branch's history.
  - **Any command**, such as `rsync` to a server.
  - `--dry-run` shows what would happen; credentials always come from the
    standard tools' own configuration, never from `_config.yml`.

### 1.2: Rich content, safely

- **Components for content.** A safe way to add callouts, YouTube and
  Vimeo embeds, image galleries, buttons, maps and notices to Markdown
  without template code, for example `::: callout` blocks. Themes can add
  their own components.
- **Images.** Resize photos into responsive sizes, add width and height,
  optionally convert to WebP, and require alt text (enforced by `check`).
  Uses ImageMagick or libvips when installed, and does nothing when not.
- **Drafts and scheduling.** `draft: true` pages are built by `dapper
  serve` but never by `build` or `deploy`; `publish_date` holds a page until
  its time.
- **More MCP tools:** add an image (copied, resized, with alt text), delete a
  page (with a redirect), start a preview and return its URL, and undo the
  last change through git.

### 1.3: Quality and migration

- **Accessibility checks:** missing alt text, skipped heading levels, the
  page language, empty or vague link text ("click here").
- **SEO checks:** missing or duplicate titles and descriptions, titles that
  are too long, pages missing from the sitemap.
- **Weight checks:** oversized images and heavy pages.
- **External link checks:** `dapper check --external` follows links to
  other sites and reports the dead ones.
- **Importers:** `dapper import` from a WordPress export, a Jekyll or Hugo
  site, and Medium, so people can bring their existing writing.
- **Pages from data:** a page per entry in a data file (a team member, a
  product, an event), with a layout.

### Later

- **Forms, comments and analytics as settings:** contact forms through
  services such as Formspree or Basin, comments through giscus, and
  privacy-friendly analytics (Plausible, GoatCounter), each a few lines of
  `_config.yml`.
- **More deploy targets:** Cloudflare Pages, Netlify, and SFTP.
- **Multiple languages:** a page per language with links between them.
- **Incremental builds** for large sites.
- **A docs site built with Dapper,** with its own `llms.txt`, so assistants
  learn Dapper accurately.
- **`dapper doctor`:** checks the setup (Perl, optional tools like
  Pagefind and the AWS CLI) and says how to fix what's missing.
- **Windows support** for the single file.

## Not planned

- **An AI inside Dapper.** Dapper stays model-neutral and free; the
  assistant is the user's own.
- **A hosted service.** Deploying to the user's own hosting is the point.
- **A JavaScript framework** or server rendering. Dapper makes plain HTML.

## How releases are made

Each release keeps the 1.0 bar: every feature has tests that fail without
it, the retired markbenson.io site still builds the same, `dapper check`
passes on every starter, the README is updated and its examples are
built before they're documented, and CI passes on Perl 5.10 to 5.40, the
single file and the Docker image.
