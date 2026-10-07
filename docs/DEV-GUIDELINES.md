# Dev guidelines

Prescriptive. Every project `CLAUDE.md` points here. Deviate in a project only by writing down why in that project's `CLAUDE.md`.

## The two-language rule

Python and TypeScript. Nothing else unless a platform forces it (Swift for a Mac-only app that needs deep OS hooks). Every target below stays inside the two.

## Per language

| Concern         | Python                                          | TypeScript                                                                         |
| --------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------- |
| Version manager | `mise`                                          | `mise`                                                                             |
| Package manager | `uv` — no pip, no poetry                        | `pnpm` — no npm, no yarn                                                           |
| Lint + format   | `ruff check` + `ruff format`                    | `biome`                                                                            |
| Types           | type hints + `pyright`                          | `strict: true`                                                                     |
| Tests           | `pytest`                                        | `vitest` for units; **Playwright** (`@playwright/test`) for end-to-end on web apps |
| Layout          | `pyproject.toml`, `src/`                        | `package.json`, `src/`                                                             |
| One-off scripts | `uv run` with an inline script header (PEP 723) | `pnpm dlx` / `tsx`                                                                 |

## Every repo has

- `CLAUDE.md` — what this project is, who it is for, how to run it, and a pointer to `~/claude-computer/docs/`
- `TASKS.md` — `## Now / ## Next / ## Later / ## Done`
- `README.md`, `.editorconfig`, `.gitignore`
- `docs/` in the documentation standard below, started by `docs-build --init`
- a `justfile` (or `Makefile`) with `setup`, `test`, `lint`, `run`
- a pre-commit secret scan (`gitleaks`)

## Secrets

- Values live in the instance's sops store (`docs/SECRETS.md`). Locally, run with `secrets exec --only NAME,… -- <cmd>`, or let `.envrc` (direnv) `eval "$(secrets env --only NAME,…)"`; `.env` files are git-ignored.
- No secret in any `.env` file. `.env.local` holds local, non-secret values only — a local database file, URLs, test-mode keys. A dev server or tool that needs a real key starts under `secrets exec` (a `just run` that does it for you), or gets it from `.envrc`, which loads each key on its own so one not stored yet is reported and skipped (the templates' `.envrc`).
- In deploys: `wrangler secret put`, EAS secrets, GitHub Actions secrets — set from the store under `secrets exec`, never pasted, never committed.

## Commits

Conventional commits (`feat:`, `fix:`, `chore:`…), small, one concern each. Never commit a secret; the pre-commit scan is the backstop, not the plan.

## Parallel work

One Claude session per git worktree. Never two sessions in one working tree. `bin/wt <branch>` creates the worktree and opens a session in it.

## Build targets

| Target          | Stack                                                                                                      | Deploy                                                                                                                                                                                                                                             |
| --------------- | ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Web app**     | Next.js + Tailwind + shadcn/ui. API-only: Hono on Cloudflare Workers. Python backend: FastAPI.             | Next.js on Cloudflare Workers through OpenNext (`@opennextjs/cloudflare`; `just deploy` = `pnpm run deploy`) — plain `wrangler deploy` can't run Next.js; Hono with `wrangler deploy`; Vercel as the alternative. Python APIs → Fly.io or Railway. |
| **Mobile app**  | Expo (React Native) + Expo Router + NativeWind                                                             | EAS Build + EAS Submit                                                                                                                                                                                                                             |
| **CLI / TUI**   | Python: Typer + Rich, Textual for TUIs. TS (`commander`, `ink`) only inside a JS project.                  | `uv tool install`; PyPI or a private brew tap                                                                                                                                                                                                      |
| **Desktop app** | Tauri v2 (TS front end; no hand-written Rust). Swift/SwiftUI only for Mac-only apps needing deep OS hooks. | `tauri build` → signed, notarized `.dmg` from GitHub Actions                                                                                                                                                                                       |

## Cross-cutting

| Concern                                  | Decision                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Database                                 | **SQLite everywhere, in three forms:** a plain file (CLI, Tauri, `expo-sqlite`); **Cloudflare D1** on Workers by default; **Turso** (libSQL) off Cloudflare, for embedded replicas, or on Workers over Turso's HTTP API when each product needs its own database and a local file in development (a portfolio of products made from one template). Same schema and ORM across all three — `drizzle` (TS), `SQLModel` / `sqlite-utils` (Python) — so moving is a connection string. Postgres only if a project outgrows SQLite: Supabase. |
| Auth                                     | `better-auth`, on the same database. Never hand-rolled.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Product analytics, errors, replay, flags | **PostHog Cloud**, wired into every `new-app` scaffold: one project per app (`posthog.<app>`), or, for a portfolio of small products, one shared project with a property naming the product on every event. For fully private or zero-cost projects: **Bugsink**, self-hosted on a fleet box — one `bugsink/bugsink` container, Sentry SDKs work unmodified. Its default SQLite is fine to try; for data you keep, point `DATABASE_URL` at Postgres (Bugsink advises against SQLite on a Docker volume).                                 |
| Marketing analytics, tags                | **GA4 + Google Tag Manager** on every public site, for acquisition and marketing: traffic, campaigns, conversions, ad attribution. Set up and kept in `analytics.yaml` by `bin/analytics` — see "Analytics" below. PostHog stays the product analytics.                                                                                                                                                                                                                                                                                  |
| Domains, DNS                             | Cloudflare, managed with `wrangler` / the API                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Transactional email                      | Resend                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Monorepo                                 | `pnpm` workspaces + Turborepo only when web and mobile share code; otherwise one repo per app                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Containers                               | Docker only for Python services and self-hosted things on a headless box. Not for Workers, Expo or Tauri.                                                                                                                                                                                                                                                                                                                                                                                                                                |
| CI                                       | GitHub Actions checks every push: lint → test → build. Deploys: by hand with `just deploy` in any repo with migrations (migrate first); on push to `main` for sites without migrations; on a tag only where the project ships releases.                                                                                                                                                                                                                                                                                                  |
| Health check                             | Every deployed web app answers `GET /api/health`: ok, version, the names of missing environment variables, the database's state. A deploy is checked against it.                                                                                                                                                                                                                                                                                                                                                                         |
| HTTPS                                    | Every public domain sends `http://` to `https://` with a 301 and serves nothing over plain HTTP. On Cloudflare that is the zone's "Always Use HTTPS"; `https-check <domain>…` checks it and `--fix` turns it on. Checked at launch and by `/graduate`. HSTS is a separate, deliberate decision.                                                                                                                                                                                                                                          |
| Reading secrets                          | Nothing reads a secret at import time: read it where it's used, so builds, tests and type checks run without keys.                                                                                                                                                                                                                                                                                                                                                                                                                       |

## Analytics

Two tools, two jobs. **PostHog** is product analytics: what people do inside the app — features, retention, sessions, flags. **GA4, through Google Tag Manager**, is marketing analytics: where visitors come from, which campaigns and pages bring them, and which of them convert — the numbers ad platforms and marketing reports use. An event belongs in one of them, not both: in-app behaviour goes to PostHog; GA gets the marketing events below.

**`analytics.yaml` in the project root is the source of truth**, and `analytics` (in `~/claude-computer/bin`) applies it. The IDs it creates are written back into the file, so it is committed with the project.

1. **Set up** (once per site): `analytics init --project "<Name>" --domain <domain>`, then `analytics setup`. It creates — or finds by name and reuses — the GA4 property and web data stream, and a GTM web container with the Google tag on all pages. Accounts default from `~/claude-computer/analytics.defaults.yaml` — copy `analytics.defaults.example.yaml` to that name and fill in your IDs (`analytics accounts` lists them); the file is optional, and an instance commits it. Then add the container to the site: `analytics snippet` prints the tag, or the `@next/third-parties` one-liner for Next.js. **GA loads only through GTM**: if the site has its own `gtag.js` snippet, remove it, or every page view counts twice.
2. **Define events** in `analytics.yaml`. Use GA4's recommended names where one fits (`sign_up`, `login`, `generate_lead`, `begin_checkout`, `purchase`, `share`, `search`); otherwise `verb_object` in snake_case, at most 40 characters. List each event's parameters, and mark the ones that are conversions `key_event: true`. Parameters you want to break reports down by go under `custom_dimensions`. The site sends each event with `window.dataLayer.push({event: '<name>', <param>: …})` at the moment it happens — never from a page load that merely shows a form.
3. **Sync**: `analytics sync` creates what is missing — GA custom dimensions and key events; a data-layer variable per parameter, a trigger and a GA4 event tag per event in GTM — and saves a new container version. **It never publishes.** Check it in GTM's Preview mode against the running site.
4. **Publish**: `analytics publish` makes that version live. It changes what a public site sends to Google, so Claude asks before running it, every time.
5. **Funnels**: name them in `analytics.yaml` as ordered steps (`signup: {steps: [page_view, sign_up]}`; `open: true` for funnels people can enter mid-way). `analytics funnel <name> [--days N]` runs one against GA's Data API. GA's API cannot save a funnel into Explore, so the file is where funnels live — reviewed and versioned like code.
6. **Reports**: likewise, `reports:` in `analytics.yaml` names a set of dimensions and metrics (GA4 Data API names: `sessionDefaultChannelGroup`, `landingPage`, `sessions`, `keyEvents` …), and `analytics report <name> [--days N]` prints it as a table. Every site keeps at least `acquisition` (channel and source → sessions, users, key events) and `landing-pages`.

Consent: every public site gets a cookie banner and GTM's Consent Mode before any of this goes live — denied by default, for every visitor, until they press Allow; Decline keeps it that way, and a "Cookie settings" link in the footer asks again. Before Allow, GA still receives cookieless pings, so a privacy page must not say nothing is sent. PostHog sets device storage too: the same banner gates it (opted out, persistence off, until Allow), or the project uses PostHog's cookieless mode (a project setting).

## Headless browsing

Playwright with its bundled Chromium — for e2e tests, scraping dynamic pages and screenshots. Never `chrome --headless`: Google Chrome is the human's browser (and Claude in Chrome's). From a terminal or a script, use `bin/browse`; in a web app, `@playwright/test`.

Every Playwright on a machine shares one browser cache (`~/Library/Caches/ms-playwright` on macOS), one folder per browser build, and each Playwright version wants its own build. So a project pins `@playwright/test` (or `playwright`) **exactly** — `1.63.0`, not `^1.63.0` — to the fleet's version, the one in `setup-tools.sh` (`PLAYWRIGHT_VERSION`) and `bin/browse`, and then needs no download at all. When the fleet's version moves, every project moves with it; a different version costs about 200 MB per machine. Install browsers with `playwright install chromium`, never `--with-deps` (that is for Linux CI and wants sudo). A new build in the cache is recorded in the machine's file, like any install.

## Documentation

Every project documents itself the same way, so a person and an agent can both find what they need without reading everything.

- **The Markdown is the source of truth**, in `docs/`: `README.md` (the index: reading order and a "Terms used throughout" table) and one `NN-name.md` per topic. Each file starts with YAML front matter: `id`, `title`, `order`, `summary`, `status` (`design`, `provisional`, `stable`), `updated`, `audience`, `depends_on`, `related`, `defines`, `answers`. `answers` lists the questions a document answers, so an agent can decide whether to open it.
- **`docs/AGENTS.md`** states the conventions: one term means one thing; text in backticks is literal; headings are anchors; tables are data (one fact per cell); diagrams are plain text; example code is included from real files (`<!-- include: path -->`), never retyped.
- **`docs-build` generates the rest**, and the generated files are committed so a reader needs no tools: `llms.txt` and `data/manifest.json` and `data/glossary.json` for agents, and `index.html` for people — every document in one offline page with search, contents, dark mode and print styles. It validates as it builds: front matter, `depends_on`/`related`, every link and `#anchor`, stale includes. `docs-build --check` is part of `just lint`.
- **Project-specific checks and data** go in `docs/docs_ext.py` (`SITE`, `validate(ctx)`, `data(ctx)`; see `docs-build --help`) — for example, validating example config files against each other, or extracting a catalogue table into JSON.
- **Client repos** carry a vendored copy (`docs-build --vendor docs` writes `docs/build.py`), because the people who build them don't have `~/claude-computer`.
- **Start one** with `docs-build --init docs --title "<project>"`; `new-app` and `new-client` do it for you.

A file another tool reads by path keeps its name and format — no number, no front matter — and is linked from the index as it is.

`claude-computer` itself keeps its operational formats (machine files, `FLEET.md`, `DECISIONS.md`); `docs-build --view` renders any Markdown tree, front matter or not, into the same kind of page for reading. The session-start hook keeps one for this repo at `~/claude-computer/.docs-view/index.html`.

## Documents as build output

Generate `.docx`, `.xlsx`, `.pptx` and PDFs from code; use LibreOffice headless (`soffice --headless --convert-to pdf`) to convert and check them. Nobody hand-edits a generated document.
