---
description: Process new transcripts in the vault — summary note, people, tasks routed, raw transcript filed
argument-hint: "[file in inbox/transcripts, or blank for all unprocessed]"
---

Work in `~/vault` and follow its `CLAUDE.md` → **Process transcripts**.

1. `~/claude-computer/bin/transcripts-sync` first, so any meeting that finished since the last sync is in the inbox.
2. Take `$ARGUMENTS` if given; otherwise every note in `inbox/transcripts/` with `status: unprocessed`, oldest `date` first.
3. For each one:
   - **Summary** → `notes/<what was discussed>.md` from `_templates/transcript-summary.md`: exactly five summary lines, **Decisions**, **Open questions**; `source` links the transcript. Project decisions also go to that project's `DECISIONS.md`.
   - **People** → `[[people/<name>]]` links; create missing person notes.
   - **Action items** → owning brain's `TASKS.md` under `## Next`, ending `← [[notes/<summary>]]`. No clear owner → `~/vault/TASKS.md` under `## Unassigned` with the same backlink. When the owner is genuinely ambiguous between two brains, pick Unassigned rather than guess.
   - **File the transcript** → move to `sources/transcripts/`, `status: processed`, add `summary: "[[notes/<summary>]]"`. Don't touch the transcript text.
4. `~/claude-computer/bin/tasks-sync`, commit the vault and every brain whose `TASKS.md` changed (`transcripts: <n> tasks from <summary>`).
5. Report one line per transcript — summary title · tasks routed (brain: count) · unassigned — and the total now in `## Unassigned`.

Long transcripts: read the whole thing before summarising; don't summarise from the first page. If a transcript is empty or clearly a false start, file it with `status: processed` and `summary: none`, and say so.
