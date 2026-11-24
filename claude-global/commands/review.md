---
description: Weekly review across every brain — what changed, what's stuck, where the map drifted
---

A weekly review. Produce `~/vault/maps/review-<YYYY>-W<ww>.md` and a short summary for me.

Gather (run in parallel where you can):

0. **Unassigned — this step is not optional.** Every item under `## Unassigned` in `~/vault/TASKS.md` leaves the review with an owner: move it to that brain's `TASKS.md` (keep its backlink) or to `## Later` in the vault. Propose an owner for each in one table; apply after I confirm. The review is not done while `## Unassigned` has items.
1. **Google Tasks — the high-level list.** `gtasks list`: every open task without a `→ <brain>` line in its notes is new. Propose a brain for each (one table, my answer before writing), add it to that brain's `TASKS.md` tagged `#gtasks` as the starter for its workplan, then `gtasks handoff <id> --list <list> --to <brain>`. The Google task stays open as the top-level item; `gtasks done` it only once the brain's work is finished — list any whose brain shows that work done.
2. **Tasks** — `~/claude-computer/bin/tasks-sync --json`: overdue, `## Now` items older than two weeks (from git blame on each `TASKS.md`), brains with nothing in `## Now`. `~/vault/maps/tasks.md` → **Hubs to close**: each hub whose brain has gone; propose its `status` (done · archived · abandoned) and `ended`, and set them after I confirm.
3. **Activity** — for each repo under `~/claude-computer`, `~/clients/*`, `~/projects/*`, `~/products/*`, `~/personal/*`, `~/vault`: commits in the last 7 days (`git log --since=7.days --oneline`); unpushed commits; uncommitted changes; repos with no commits in 30 days (stale — ask whether to archive or graduate).
4. **Fleet** — `map-check` on this machine; `docs/FLEET.md` rows whose machine file hasn't changed in 30 days; `DECISIONS.md` entries this week; `https-check` on every live domain (from the `## Production` sections and `CLAUDE.md` of `~/products/*`) — report fails, fix only after I confirm.
5. **Vault** — notes left in `inbox/`; transcripts still `status: unprocessed`; `sources/feeds/` digests with nothing saved. **Commitments past due** — `~/claude-computer/bin/commitments list --overdue --json`, plus `list --due-within 7 --json` for the week ahead: one table, mine (`mine: true`) first, each linked `[[memory/commitments/<id>|<title>]]` with whom, due date and its `task:`. Propose for each: done, dropped, a new `due`, or a nudge to the other side; apply after I confirm, done and dropped only through `commitments set <id> done|dropped --via review` (it writes the log bullet and the evidence). A new `due` is a dated `## Log` bullet citing the review note, then `vault-lint`. Open commitments with no `due` and older than 30 days (`list --json`, by `meeting_date`) go in the same table: propose a due date or dropping.
6. **Housekeeping** — `~/projects/_scratch` items older than 30 days (propose sweeping to `~/archive`); `~/resources/*/INDEX.md` expiry dates in the next 90 days (route "renew" tasks to `~/resources/TASKS.md`).

Write the review note with those six sections, then tell me in under ten lines: what moved, what's stuck, and the three things you'd do next. Ask before acting on any proposal.
