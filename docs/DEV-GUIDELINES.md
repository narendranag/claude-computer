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
- In deploys: `wrangler secret put`, EAS secrets, GitHub Actions secrets — set from the store under `secrets exec`, never pasted, never committed.

## Commits

Conventional commits (`feat:`, `fix:`, `chore:`…), small, one concern each. Never commit a secret; the pre-commit scan is the backstop, not the plan.

## Parallel work

One Claude session per git worktree. Never two sessions in one working tree. `bin/wt <branch>` creates the worktree and opens a session in it.

## Build targets

| Target          | Stack                                                                                                      | Deploy                                                                                                   |
| --------------- | ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| **Web app**     | Next.js + Tailwind + shadcn/ui. API-only: Hono on Cloudflare Workers. Python backend: FastAPI.             | Cloudflare (Workers / Pages) via `wrangler`; Vercel as the alternative. Python APIs → Fly.io or Railway. |
| **Mobile app**  | Expo (React Native) + Expo Router + NativeWind                                                             | EAS Build + EAS Submit                                                                                   |
| **CLI / TUI**   | Python: Typer + Rich, Textual for TUIs. TS (`commander`, `ink`) only inside a JS project.                  | `uv tool install`; PyPI or a private brew tap                                                            |
| **Desktop app** | Tauri v2 (TS front end; no hand-written Rust). Swift/SwiftUI only for Mac-only apps needing deep OS hooks. | `tauri build` → signed, notarized `.dmg` from GitHub Actions                                             |

## Cross-cutting

| Concern                          | Decision                                                                                                                                                                                                                                                                                                                                                                   |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Database                         | **SQLite everywhere, in three forms:** a plain file (CLI, Tauri, `expo-sqlite`); **Cloudflare D1** on Workers; **Turso** (libSQL) off Cloudflare or when you need embedded replicas. Same schema and ORM across all three — `drizzle` (TS), `SQLModel` / `sqlite-utils` (Python) — so moving is a connection string. Postgres only if a project outgrows SQLite: Supabase. |
| Auth                             | `better-auth`, on the same database. Never hand-rolled.                                                                                                                                                                                                                                                                                                                    |
| Analytics, errors, replay, flags | **PostHog Cloud**, wired into every `new-app` scaffold. For fully private or zero-cost projects: **Bugsink**, self-hosted on a fleet box — one `bugsink/bugsink` container, Sentry SDKs work unmodified. Its default SQLite is fine to try; for data you keep, point `DATABASE_URL` at Postgres (Bugsink advises against SQLite on a Docker volume).                       |
| Domains, DNS                     | Cloudflare, managed with `wrangler` / the API                                                                                                                                                                                                                                                                                                                              |
| Transactional email              | Resend                                                                                                                                                                                                                                                                                                                                                                     |
| Monorepo                         | `pnpm` workspaces + Turborepo only when web and mobile share code; otherwise one repo per app                                                                                                                                                                                                                                                                              |
| Containers                       | Docker only for Python services and self-hosted things on a headless box. Not for Workers, Expo or Tauri.                                                                                                                                                                                                                                                                  |
| CI                               | GitHub Actions: lint → test → build → deploy on tag                                                                                                                                                                                                                                                                                                                        |

## Headless browsing

Playwright with its bundled Chromium — for e2e tests, scraping dynamic pages and screenshots. Never `chrome --headless`: Google Chrome is the human's browser (and Claude in Chrome's). From a terminal or a script, use `bin/browse`; in a web app, `@playwright/test`.

## Documentation

Every project documents itself the same way, so a person and an agent can both find what they need without reading everything.

- **The Markdown is the source of truth**, in `docs/`: `README.md` (the index: reading order and a "Terms used throughout" table) and one `NN-name.md` per topic. Each file starts with YAML front matter: `id`, `title`, `order`, `summary`, `status` (`design`, `provisional`, `stable`), `updated`, `audience`, `depends_on`, `related`, `defines`, `answers`. `answers` lists the questions a document answers, so an agent can decide whether to open it.
- **`docs/AGENTS.md`** states the conventions: one term means one thing; text in backticks is literal; headings are anchors; tables are data (one fact per cell); diagrams are plain text; example code is included from real files (`<!-- include: path -->`), never retyped.
- **`docs-build` generates the rest**, and the generated files are committed so a reader needs no tools: `llms.txt` and `data/manifest.json` and `data/glossary.json` for agents, and `index.html` for people — every document in one offline page with search, contents, dark mode and print styles. It validates as it builds: front matter, `depends_on`/`related`, every link and `#anchor`, stale includes. `docs-build --check` is part of `just lint`.
- **Project-specific checks and data** go in `docs/docs_ext.py` (`SITE`, `validate(ctx)`, `data(ctx)`; see `docs-build --help`) — for example, validating example config files against each other, or extracting a catalogue table into JSON.
- **Client repos** carry a vendored copy (`docs-build --vendor docs` writes `docs/build.py`), because the people who build them don't have `~/claude-computer`.
- **Start one** with `docs-build --init docs --title "<project>"`; `new-app` and `new-client` do it for you.

`claude-computer` itself keeps its operational formats (machine files, `FLEET.md`, `DECISIONS.md`); `docs-build --view` renders any Markdown tree, front matter or not, into the same kind of page for reading. The session-start hook keeps one for this repo at `~/claude-computer/.docs-view/index.html`.

## Documents as build output

Generate `.docx`, `.xlsx`, `.pptx` and PDFs from code; use LibreOffice headless (`soffice --headless --convert-to pdf`) to convert and check them. Nobody hand-edits a generated document.
