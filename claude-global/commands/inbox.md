---
description: Empty the vault inbox — clean, file, link, and route tasks to their brains
---

Work in `~/vault` and follow `~/vault/CLAUDE.md`.

**First, transcripts.** Run the `/transcripts` job for everything in `inbox/transcripts/` with `status: unprocessed` (it syncs from MacParakeet first).

**Then `inbox/quick.md`** (short dictation): split it into atomic notes and route any tasks exactly as below, then reset it to its empty template. Never delete a line without filing it.

Then, for each other note in `inbox/` (oldest first):

1. **Read and classify** as one `type`: `note` (idea, meeting, decision), `person`, `source` (article, clip, transcript), or `project` update. Dictation transcripts: fix punctuation and obvious mis-hearings; keep the wording.
2. **Frontmatter** — enforce the schema: `type`, `created`, `tags`, `status`, `people`, `project`, `source`. Infer; don't ask unless it truly matters.
3. **File it**: `notes/` (flat, atomic — split a note that holds two ideas), `people/`, `sources/`. Name files by what they are about, not the date.
4. **Link**: `[[people]]` mentioned (create a stub in `people/` for anyone who appears a second time), the `[[project]]` hub, and up to three genuinely related notes (`rg` the vault).
5. **Route tasks**: any action item goes into the `TASKS.md` of the brain that owns it (`~/projects/<x>/TASKS.md`, `~/claude-computer/TASKS.md`, `~/resources/TASKS.md`…), under `## Next` unless it's clearly urgent, with a due date if one was said and a backlink to the note. Leave a line in the note: `→ task added to <brain>`. No brain owns it → `~/vault/TASKS.md` under `## Unassigned`, with the backlink.
6. **Decisions** mentioned for a project go into that project's `DECISIONS.md` too.

Then: run `~/claude-computer/bin/tasks-sync`, commit the vault (`inbox: filed N notes`), and give me a five-line summary — what was filed where, tasks routed, anything you were unsure about.

Never delete a note's content. If something can't be classified, leave it in `inbox/` and tell me.
