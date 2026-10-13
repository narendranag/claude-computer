---
description: Process new transcripts into the vault's memory graph — meeting, people, decisions, commitments, tasks routed, raw transcript filed
argument-hint: "[file in inbox/transcripts, or blank for all unprocessed] [nightly]"
---

Work in the vault (the current directory when the nightly job runs, else `~/vault`) and follow its `CLAUDE.md`: **Rules**, **Properties** and **Jobs → Transcripts** are the contract; this is the procedure.

**Nightly mode** (`$ARGUMENTS` contains `nightly`): nobody is watching, and `.nightly/run.md` in the vault says what this run may take on. Read it first. Then the differences from below: skip `transcripts-sync` (the job ran it); never write outside the vault — action items for other brains go to `.nightly/tasks.jsonl` instead of their `TASKS.md` (the job applies them after `vault-lint` passes); run `vault-lint --vault .`; skip `tasks-sync`; never ask, and when unsure of an owner, a person's identity or a date, take the cautious path (Unassigned, a link-less mention, leave it out) and say so in the report.

1. `~/claude-computer/bin/transcripts-sync` first, so any meeting that finished since the last sync is in the inbox.
2. Take the file in `$ARGUMENTS` if given; otherwise every note in `inbox/transcripts/` with `status: unprocessed`, oldest `date` first.
3. For each one, read the whole transcript before writing anything, then:
   1. **Meeting** → `memory/meetings/<YYYY>/<date>-<slug>.md` (`type: meeting`). Match the calendar event: `gcal at <date>T<time> --minutes <duration in minutes> --json` lists the events that overlap the recording, most overlap first — take the top one when it overlaps by at least a third of the recording, for the title, attendees and `calendar`. Nothing overlaps: `gcal day <date>` and `gcal search "<words>" --back <days> --json`; still nothing, title it from the content and say so. Five summary lines, then `## Discussed`, `## Decisions`, `## Open questions`, `## Commitments`. `transcript:` links the raw note.
   2. **People and orgs**: search names and `aliases` in `memory/people/` and `memory/orgs/` first (Rule 7). Link existing ones; create new ones only per Rule 6. Each gets a dated `## Log` bullet citing the meeting, and `last_contact`.
   3. **Decisions and commitments** that qualify → `memory/decisions/`, `memory/commitments/` (`from`, `to`, `status: open`, `made_in`, `due` only if said), linked both ways with the meeting. A project decision also goes to that project's `DECISIONS.md` (nightly: as a task line for that brain saying so).
   4. **Action items** for the owner → the owning brain's `TASKS.md` under `## Next`, ending `← [[<meeting path>]]`; record `task: <brain>` on the commitment. No clear owner, or ambiguous between two brains → `TASKS.md` `## Unassigned` in the vault, same backlink.
   5. **Project hubs**: a meeting about a project links its hub (`memory/projects/<name>`) and adds a dated log bullet there.
   6. **File the transcript** → `git mv` to `sources/transcripts/`, set `status: processed` and `meeting: "[[<meeting path>]]"`. Never edit its text.
4. `vault-lint` must pass; fix what it reports. Then `~/claude-computer/bin/tasks-sync`, and commit the vault (`transcripts: processed <n>`) and every brain whose `TASKS.md` changed (`tasks: from vault <meeting>`).
5. Report one line per transcript: meeting · people (new/linked) · decisions · commitments · tasks routed (brain: count) · anything unsure.

An empty transcript or a false start: file it with `status: processed` and `meeting: none`, and say so.

**`.nightly/tasks.jsonl`**, one JSON object per line: `{"brain": "<name from .nightly/run.md>", "task": "<one line, no newline, ≤ 300 chars>", "due": "YYYY-MM-DD" (optional), "source": "<vault path without .md>"}`. The job adds `- [ ] <task> 📅 <due> ← [[<source>]]` under that brain's `## Next` and commits it there.
