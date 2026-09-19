# vault — the second brain

An Obsidian vault that Claude manages. **Capture is free; filing, linking and retrieval are Claude's job.** Structure lives in properties (frontmatter), not folders.

System context: `~/claude-computer/docs/`. Tasks are **not** kept here — see Rules.

## Shape

| Folder               | What goes in                                                                                           | Who writes                                                                    |
| -------------------- | ------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| `inbox/`             | everything lands here: web clips, quick notes; `quick.md` for short dictation                          | anyone; Claude empties it (`/inbox`)                                          |
| `inbox/transcripts/` | one note per recording: meetings, files, URLs, podcasts (`type: transcript`, `status: unprocessed`)    | `transcripts-sync`, `macparakeet-cli`; Claude processes them (`/transcripts`) |
| `daily/`             | one note per day, `YYYY-MM-DD.md`, drafted from tasks                                                  | scheduled draft + `/today`; the human adds                                    |
| `notes/`             | **flat.** atomic ideas, meeting notes, decisions. No subfolders.                                       | Claude files, the human writes                                                |
| `people/`            | one note per person who keeps coming up                                                                | Claude                                                                        |
| `projects/`          | one hub note per brain (`<name>.md`)                                                                   | the human writes the top; `tasks-sync` owns the Tasks block                   |
| `sources/`           | articles, book notes; `sources/feeds/` daily digests; `sources/transcripts/` processed raw transcripts | Claude, `feeds-sync`                                                          |
| `maps/`              | maps of content, `tasks.md`, weekly reviews                                                            | Claude, `tasks-sync`                                                          |
| `_templates/`        | Templater templates                                                                                    | rarely changed                                                                |

## Frontmatter — every note

```yaml
type: note | person | project | source | transcript | daily | map
created: YYYY-MM-DD
tags: []
status: active | done | archived # when it applies
people: [] # [[links]]
project: "" # hub name
source: "" # url, book, "dictation", "clipper", "feeds-sync"
```

Enforce it when filing. Fix it when you see it wrong.

## Rules

1. **Generated vs authored is a hard line.** Anything between `<!-- tasks-sync:start … -->` and `<!-- tasks-sync:end -->`, and any note with `generated:` in its frontmatter, is written by a script. Never hand-edit it; change the source and rerun the script. Everything else is authored and is never overwritten by a script.
2. **Tasks live in the owning brain's `TASKS.md`**, not here. When a task shows up in the vault, move it to the right brain and leave `→ task added to <brain>`. Ticking a checkbox in `maps/tasks.md` does nothing. The one exception is this vault's own `TASKS.md` → `## Unassigned`: action items no brain owns yet, each with a backlink to where it came from. `/review` empties it.
3. **Never delete authored content.** Split, move, merge — but the words survive.
4. **Links over folders.** Link people, projects and related notes; don't create subfolders in `notes/`.
5. Commit after each job: `inbox: filed 6 notes`, `daily: 2026-10-01`, `review: 2026-W40`.

## Jobs

1. **Empty the inbox** — `/inbox`. It runs the transcript job below first, then files everything else.
2. **Process transcripts** — `/transcripts`, for every note in `inbox/transcripts/` with `status: unprocessed`:
   1. **Summary note** in `notes/`, named for what was discussed: frontmatter `type: note`, `source: "[[sources/transcripts/<file>]]"`, `people`, `project`; body = a **five-line summary**, **Decisions**, **Open questions**. Decisions that belong to a project also go into that project's `DECISIONS.md`.
   2. **People** mentioned by name → link `[[people/<name>]]`; create the person note if it doesn't exist.
   3. **Action items** → the owning brain's `TASKS.md` under `## Next`, each ending with a backlink: `← [[notes/<summary>]]`. Nothing obvious owns it → `~/vault/TASKS.md` under `## Unassigned`, same backlink. Never leave an action item only in the note.
   4. **File the raw transcript**: move it to `sources/transcripts/`, set `status: processed`, add `summary: "[[notes/<summary>]]"`. Summary ↔ source link both ways. Never edit the transcript text.
   5. Run `tasks-sync`, commit `transcripts: processed N`, and report in one line per transcript: summary title, tasks routed (and where), unassigned count.
3. **Daily note** — drafted from `tasks-sync --json` (Now, overdue, due this week, closed yesterday, today's reading digest). `/today` to review.
4. **Keep maps current** — a map per recurring theme once it has 5+ notes; the weekly review (`/review`).
5. **Answer questions** across the vault: `rg` over markdown first, then read the hits; cite the notes you used as `[[links]]`.

## Capture

- **Meetings** recorded in MacParakeet arrive by themselves: `transcripts-sync` watches its database and writes `inbox/transcripts/`.
- **Files, URLs, podcasts**: `macparakeet-cli transcribe <input> --no-history --output-dir ~/vault/inbox/transcripts --format transcript`.
- **Short dictation** goes into `inbox/quick.md`; `/inbox` splits it into atomic notes and routes any tasks.
- **Web clips**: Obsidian Web Clipper, saving to `inbox/`.

## Overflow

`## Unassigned` renders at the top of `maps/tasks.md`. Every `/review` must give each item an owner (move it to that brain's `TASKS.md`) or move it to `## Later` here. More than 10 unassigned → `tasks-sync` sends one alert a day.

## Plugins

Obsidian Git (sync), Dataview (queries over frontmatter), Templater. Everything else must earn its place.
