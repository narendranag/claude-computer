---
description: Archive folders to R2 cold storage and remove the local copy
argument-hint: "<path or description of what to archive>"
---

Archive: $ARGUMENTS

`~/archive` is a staging area. Once something is pushed and verified, R2 holds the **only** copy.

1. Resolve what I mean into concrete paths. If they are outside `~/archive`, propose a destination inside it (`~/archive/<YYYY>/<name>` unless a better grouping is obvious) and move them there after I agree.
2. Show me: each path, file count, total size (`du -sh`), and anything that looks like it should not be archived (a git repo with unpushed commits, secrets, a live project with a recent change).
3. Run `~/claude-computer/bin/archive-push <paths> --dry-run`, then — **after I say yes** — `archive-push <paths> --delete-local --yes`. The script asks before each deletion and answers itself no when there is no terminal, so `--yes` is what carries my answer through; never pass it before I have given it.
4. The script verifies with `rclone check` before deleting and rebuilds `~/archive/INDEX.md`. Report what moved and the new totals.
5. If a project repo was archived, remove it from `~/claude-computer/docs/FLEET.md`/maps if listed. Then close its hub, `~/vault/memory/projects/<name>.md` (the vault's `CLAUDE.md`, _Projects → Lifecycle_), **before** `tasks-sync` runs again, since the checkout is gone and nothing refreshes the block after that:
   - `project-import <owner/repo> --vault ~/vault` refreshes the snapshot (`as_of` = the last sha).
   - Set `status: archived` (or `done` / `abandoned` if I say so), `ended: <today>`, `cold: "R2 <path>"`, and drop `local`.
   - Rename the Tasks block heading to `## Open at close (<short sha>)` and remove its two `tasks-sync` markers, so it is frozen. Add a dated `## Log` bullet citing the snapshot.
   - Add `## What it was`, `## Outcome`, `## Lessons` from the snapshot and the repo's `DECISIONS.md` if the hub has none. Then `vault-lint` and commit the vault.
