---
description: Weekly review across every brain — what changed, what's stuck, where the map drifted
---

A weekly review. Produce `~/vault/maps/review-<YYYY>-W<ww>.md` and a short summary for me.

Gather (run in parallel where you can):

0. **Unassigned — this step is not optional.** Every item under `## Unassigned` in `~/vault/TASKS.md` leaves the review with an owner: move it to that brain's `TASKS.md` (keep its backlink) or to `## Later` in the vault. Propose an owner for each in one table; apply after I confirm. The review is not done while `## Unassigned` has items.
1. **Tasks** — `~/claude-computer/bin/tasks-sync --json`: overdue, `## Now` items older than two weeks (from git blame on each `TASKS.md`), brains with nothing in `## Now`.
2. **Activity** — for each repo under `~/claude-computer`, `~/projects/*`, `~/products/*`, `~/vault`: commits in the last 7 days (`git log --since=7.days --oneline`); unpushed commits; uncommitted changes; repos with no commits in 30 days (stale — ask whether to archive or graduate).
3. **Fleet** — `map-check` on this machine; `docs/FLEET.md` rows whose machine file hasn't changed in 30 days; `DECISIONS.md` entries this week.
4. **Vault** — notes left in `inbox/`; transcripts still `status: unprocessed`; `sources/feeds/` digests with nothing saved.
5. **Housekeeping** — `~/projects/_scratch` items older than 30 days (propose sweeping to `~/archive`); `~/resources/*/INDEX.md` expiry dates in the next 90 days (route "renew" tasks to `~/resources/TASKS.md`).

Write the review note with those five sections, then tell me in under ten lines: what moved, what's stuck, and the three things you'd do next. Ask before acting on any proposal.
