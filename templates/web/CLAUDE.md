# __NAME__

<!-- /new-app replaces this stub. Keep it short: what, for whom, how to run it. -->

**What:** _one sentence_
**For:** _me / family / public_
**Target:** web

## Context

- System and fleet: `~/system-manager/docs/` (start with `FLEET.md`).
- How every project is built: `~/system-manager/docs/DEV-GUIDELINES.md`. Deviations are listed below with the reason.
- Tasks: `TASKS.md` in this folder. Decisions: `DECISIONS.md`.

## Stack

Next.js + Tailwind + shadcn/ui (TypeScript). API in route handlers; Hono on Workers if API-only; FastAPI if the backend is Python.

Deviations from DEV-GUIDELINES: _none_

## Run

`just setup` · `just run` · `just test` (vitest) · `just e2e` (Playwright, bundled Chromium) · `just lint`

## Deploy

Cloudflare via `wrangler` (Vercel as the alternative).

Secrets come from Bitwarden (`system-manager/<name>-*` items) through `.envrc` + direnv, and into deploy targets with the platform's secret command. Never committed.

## Analytics and errors

PostHog (key: Bitwarden `system-manager/posthog-__NAME__`), unless this project is private/zero-cost, in which case Bugsink on the fleet.
