# archive — cold storage brain

`~/archive` is a **staging area, not storage.** Things come here to be pushed to R2; once pushed and verified, R2 holds the only copy. This folder keeps just this file, `TASKS.md`, and `INDEX.md` — which is regenerated from R2 and never edited.

System context: `~/claude-computer/docs/`.

## Jobs

1. **Archive** (`/archive`): stage under `~/archive/<YYYY>/<name>`, show size and risks, `archive-push <paths> --dry-run`, then with my OK `archive-push <paths> --delete-local`. The script verifies with `rclone check` before deleting.
2. **Retrieve** (`/retrieve`): `archive-pull --search`, confirm, `archive-pull <path> [dest]`. Never overwrites.
3. **Index**: `archive-push --index-only` rebuilds `INDEX.md` from `rclone lsjson`, so every machine sees the same catalogue with nothing to sync.
4. **Sweep scratch** (monthly, from `/review`): propose moving `~/projects/_scratch/*` older than 30 days here.

## Rules

- Ask before every push that deletes locally. Never delete from R2 unless I ask for that specific path.
- Don't archive: git repos with unpushed commits, anything with secrets in it, `~/resources` (it has its own encrypted sync).
- Remote: `r2:<bucket>/archive/`. Keys come from Bitwarden; there is no `rclone.conf` with keys.
