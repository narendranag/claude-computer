---
description: Empty the vault inbox — transcripts first, then captures into notes/ or sources/, entities extracted, tasks routed
argument-hint: "[nightly]"
---

Work in the vault (the current directory when the nightly job runs, else `~/vault`) and follow its `CLAUDE.md`: **Rules**, **Properties** and **Jobs → Inbox** are the contract; this is the procedure.

**Nightly mode** (`$ARGUMENTS` contains `nightly`): the same differences as `/transcripts` nightly — read `.nightly/run.md` first and take on only the files it lists, tasks for other brains go to `.nightly/tasks.jsonl`, never write outside the vault, `vault-lint --vault .`, no `tasks-sync`, never ask, cautious when unsure. A capture you can't classify stays in `inbox/` and goes in the report.

**First, transcripts**: run the `/transcripts` job (with `nightly` in nightly mode) for everything in `inbox/transcripts/` with `status: unprocessed`.

**Then `inbox/quick.md`** (short dictation): split it into atomic notes and route any tasks as below, then reset it to its empty template. Never drop a line without filing it.

**Then each other capture in `inbox/`**, oldest first:

1. **Read and classify.**
   - The owner's own thinking (an idea, a plan, a reflection, dictation) → `notes/<claim-as-title>.md`, `type: note`. Atomic: split a note that holds two ideas. Keep the owner's words (Rule 5): fix punctuation and obvious mis-hearings only.
   - Material from elsewhere (a clip, an article, a report, a generated brief, a spec someone sent, an email) → `sources/<slug>.md`, `type: source`, with `kind` and whatever of `url`, `author`, `date`, `summary` is known. The body stays as captured.
   - A transcript dropped in the wrong place → `inbox/transcripts/` and the transcripts job.
2. **Properties** per the vault's Properties table; unknown values left out, never guessed.
3. **Extract** per Rule 6 and 7: people, orgs, decisions, commitments into `memory/`, each fact citing the filed note. Link the project hub (`memory/projects/<name>`) and up to three genuinely related notes (`rg` the vault).
4. **Route tasks**: an action item goes to the owning brain's `TASKS.md` under `## Next` (nightly: `.nightly/tasks.jsonl`), with a due date if one was said and a backlink to the filed note; leave `→ task added to <brain>` in the note. No brain owns it → the vault's `TASKS.md` `## Unassigned`, with the backlink.
5. **Project decisions** also go to that project's `DECISIONS.md` (nightly: a task line for that brain saying so).

**Then, nightly only, the hubs** `.nightly/run.md` lists under _Projects_, as it says there (the vault's `CLAUDE.md` → _Projects_).

Then `vault-lint` must pass; `~/claude-computer/bin/tasks-sync`; commit the vault (`inbox: filed <n>`) and every brain whose `TASKS.md` changed. Report in five lines: what was filed where, entities created, tasks routed, anything unsure or left in the inbox.

Never delete a capture's content: filing moves it (`git mv`) or splits it; the words survive (Rule 9).
