# __NAME__

<!-- /new-app replaces this stub. Keep it short: what, for whom, how to run it. -->

**What:** _one sentence_
**For:** _me / family / public_
**Target:** desktop

## Context

- System and fleet: `~/claude-computer/docs/` (start with `FLEET.md`).
- How every project is built: `~/claude-computer/docs/DEV-GUIDELINES.md`. Deviations are listed below with the reason.
- Tasks: `TASKS.md` in this folder. Decisions: `DECISIONS.md`.

## Stack

Tauri v2 with a React + TypeScript front end. No hand-written Rust unless unavoidable.

Deviations from DEV-GUIDELINES: _none_

## Run

`just setup` · `just run` · `just test` · `just lint`

## Deploy

`tauri build` → signed, notarized `.dmg` from GitHub Actions on tag.

Secrets come from Bitwarden (`claude-computer/<name>-*` items) through `.envrc` + direnv, and into deploy targets with the platform's secret command. Never committed.

## Analytics and errors

PostHog (key: Bitwarden `claude-computer/posthog-__NAME__`), unless this project is private/zero-cost, in which case Bugsink on the fleet.
