# vault — the second brain

Two layers in one Obsidian vault. **Structure is Claude's job; thinking is the owner's.**

- **`notes/` and `daily/` are the owner's layer** — ideas and days in their own words. Claude adds links and properties around them, never rewrites them.
- **`memory/` is Claude's layer** — a graph of entities (people, orgs, meetings, decisions, commitments, topics, projects), built only from evidence in `sources/`, every fact cited. It exists so Claude can answer "what did I promise Sam?" with a query and a citation, and so the owner's views (Home, maps) can be generated from it.

System context: `~/claude-computer/docs/`. Tasks are not kept here (Rule 2).

## Shape

| Folder | What goes in | Who writes |
| --- | --- | --- |
| `inbox/` | everything lands here: web clips, `quick.md` dictation, stray files | anyone; Claude empties it |
| `inbox/transcripts/` | raw recordings (`type: transcript`, `status: unprocessed`) | `transcripts-sync`, `macparakeet-cli` |
| `daily/` | `YYYY-MM-DD.md`; drafted at 06:30, then the owner's | scheduled draft; the owner; Claude appends `## Extracted` links only |
| `notes/` | **flat.** the owner's evergreen ideas, one idea each, titled as a claim | the owner; Claude files captures here when they are the owner's thinking |
| `memory/people/` | one note per person | Claude |
| `memory/orgs/` | companies, clients, investors, communities | Claude |
| `memory/meetings/YYYY/` | one note per meeting or call | Claude, from a transcript |
| `memory/decisions/` | one note per decision that matters beyond the meeting | Claude |
| `memory/commitments/` | promises made or received, with a due date | Claude |
| `memory/topics/` | subjects that recur (≥ 3 linked notes) | Claude |
| `memory/projects/` | one hub per project, **whether or not it is checked out** | Claude; `tasks-sync` owns the Tasks block; `project-import` owns `_catalogue.md` |
| `sources/` | evidence, read-only once filed: `transcripts/`, `repos/`, `feeds/`, and flat clips, reports, papers | Claude, `transcripts-sync`, `project-import`, `feeds-sync` |
| `maps/` | views: `tasks.md` (generated), weekly reviews, topic maps | Claude, `tasks-sync` |
| `attachments/` | images and PDFs referenced by notes | Obsidian |
| `_templates/` | Templater templates, one per type | rarely changed |
| `.index/` | generated, git-ignored: SQLite + embeddings over the vault | `vault-index` (later) |

`Home.md` at the root is the owner's dashboard.

## Properties

Every note has `type` and `created`. Lists of links are YAML lists of quoted wikilinks: `people: ["[[memory/people/sam-rivera]]"]`. Dates are `YYYY-MM-DD`. Unknown values are left out, never guessed.

| `type` | Folder | Required | Optional |
| --- | --- | --- | --- |
| `note` | `notes/` | `created` | `topics`, `people`, `projects`, `sources` |
| `daily` | `daily/` | `created` | — |
| `person` | `memory/people/` | `created`, `name` (the owner's own note is named after `git config user.name` as a slug, carries `me: true`, and needs no sources) | `aliases`, `orgs`, `role`, `relationship` (client · colleague · partner · advisee · advisor · investor · vendor · friend · family · other: what they are to the owner now), `ties`, `last_contact`, `sources` |
| `org` | `memory/orgs/` | `created`, `name` | `aliases`, `kind` (client · company · investor · vendor · community · other), `website`, `people`, `projects`, `sources` |
| `meeting` | `memory/meetings/YYYY/` | `created`, `date`, `attendees`, `transcript` | `calendar` (the matched event), `time`, `duration`, `orgs`, `projects`, `topics`, `decisions`, `commitments` |
| `decision` | `memory/decisions/` | `created`, `date`, `status` (made · superseded · reversed), `sources` | `decided_by`, `made_in`, `projects`, `topics`, `supersedes`, `superseded_by` |
| `commitment` | `memory/commitments/` | `created`, `from`, `to`, `status` (open · done · dropped), `made_in` | `due`, `done_on`, `task` (the `TASKS.md` that tracks it), `projects` |
| `topic` | `memory/topics/` | `created`, `name` | `aliases`, `broader`, `related` |
| `project` | `memory/projects/` | `created`, `status` (idea · active · paused · done · archived · abandoned), `repo` | `local`, `cold`, `started`, `ended`, `stack`, `orgs`, `people`, `topics`, `snapshot` |
| `source` | `sources/` | `created`, `kind` (transcript · clip · report · repo · email · feed · book · paper · confirmation — the owner confirming a fact directly) | `url`, `author`, `date`, `as_of`, `summary`, `repo_topics` (GitHub's own), `topics`, `projects`, `status` |
| `transcript` | `inbox/transcripts/`, `sources/transcripts/` | as `transcripts-sync` writes it (`date`, not `created`) | `summary` / `meeting` once processed |
| `map` | `maps/` | `created` | `generated` |

**Ties.** A person can matter to the owner in more than one way over time: a colleague at one company, later a partner or client at another. `relationship` says what they are now, and is left out when every tie has ended (a former colleague has none); `ties` records each way, one entry per role, never overwritten — a tie that ends gets `until`, a new one is added:

```yaml
relationship: partner
ties:
  - relationship: colleague          # same values as `relationship`
    org: "[[memory/orgs/acme-corp]]" # the org the tie runs through, theirs or the owner's; left out if none
    until: 2026-08-15                # since / until: YYYY-MM-DD, left out when unknown (not from/to: Dataview keywords)
    source: "[[memory/meetings/2026/2026-09-17-sam-rivera-catch-up]]"   # one link, or a list
```

File names: kebab-case slugs, except where a script names the file: transcripts keep `transcripts-sync`'s `YYYY-MM-DD_<slug>`, and project hubs and repo snapshots use the folder or repo name as it is. Generated indexes inside `memory/` start with `_` (`memory/projects/_catalogue.md`). People `first-last`; meetings `YYYY-MM-DD-<slug>`; commitments `<due or date>-<slug>`; projects = the brain's folder name when it has a checkout (as `tasks-sync` names it, e.g. `Acme` for `client-acme`), otherwise the repo name; `repo:` always holds `owner/repo`.

## Rules

1. **Generated vs authored is a hard line.** A note with `generated:` in its properties, or text between `<!-- <script>:start -->` and `<!-- <script>:end -->` markers, belongs to that script. Never hand-edit it; change the source and rerun.
2. **Tasks live in the owning brain's `TASKS.md`.** A commitment that is also a task records where with `task:`. Nothing obvious owns it → `~/vault/TASKS.md` `## Unassigned`, with a backlink. `/review` empties it.
3. **Every fact in `memory/` cites evidence.** Properties list it in `sources` (or `transcript`, `made_in`); each `## Log` bullet ends with its source link. No source, no fact. Facts about a repo cite its snapshot, which is pinned to a commit.
4. **Time is explicit.** A changed fact gets a new dated log bullet; a changed decision gets a new decision note with `supersedes`. Nothing true-at-the-time is overwritten.
5. **The owner's words are never rewritten.** In `notes/` and `daily/`, Claude may add properties, links and a `## Extracted` section; the body text stays. If the owner edits a `memory/` note, that edit wins over Claude's next pass.
6. **Create entities sparingly.** A person: an attendee, a decision-maker, a commitment party, or a second mention anywhere. An org: tied to a meeting or project. A topic: three or more notes would link it. A decision: it outlives the meeting. Everything else stays a link-less mention in the source.
7. **One identity per entity.** Search names and `aliases` before creating; add an alias rather than a duplicate.
8. **`vault-lint` must pass** before a commit that touches `memory/`: required properties, allowed values, links that resolve.
9. **Never delete authored content.** Split, move, merge — the words survive.
10. Commit after each job: `transcripts: processed 3`, `projects: imported passages`, `inbox: filed 6`.

## Each entity note

```markdown
---
(properties)
---
# <Name>

<Summary: 2–5 lines, current as of the last log entry. Claude keeps it current.>

## Log
- 2026-10-02 — Agreed a fixed-fee pilot for Q4. ([[memory/meetings/2026/2026-10-02-acme-pricing]])
```

Projects add `## What it was`, `## Outcome`, `## Lessons`, `## Decisions` above the log, and the `tasks-sync` block while active.

## Jobs

**Unattended.** `vault-nightly` (04:30, on the vault's home machine) runs jobs 1 and 2 as `/inbox nightly` with no one present, in a git worktree of the vault, never in the vault itself. Tasks for other brains go to `.nightly/tasks.jsonl`; the job writes them into each brain's `TASKS.md` `## Next` and commits there (`tasks: from vault <note>`). Nothing lands unless the gate passes: `vault-lint` clean, nothing deleted outside `inbox/`, nothing left uncommitted — otherwise the vault and its inbox stay as they were and the owner gets a Telegram line. Everything it did is listed in that day's daily note under `## Overnight`, each item linked, each commit revertible.

1. **Transcripts** (`/transcripts`), each unprocessed note in `inbox/transcripts/`:
   1. Meeting note in `memory/meetings/YYYY/`: match the calendar event at that time (`gcal`) for the title and attendees; properties, a five-line summary, `## Discussed`, `## Decisions`, `## Open questions`, `## Commitments`.
   2. People and orgs: link existing, create per Rule 6, add a dated log bullet and update `last_contact`; a new way of engaging adds a tie, one that ended gets its `until`.
   3. Decisions and commitments that qualify → their own notes, linked both ways. Project decisions also go to that project's `DECISIONS.md`.
   4. Action items → the owning brain's `TASKS.md` `## Next`, ending `← [[<meeting>]]`; record `task:` on the commitment.
   5. Move the raw transcript to `sources/transcripts/`, `status: processed`, `meeting: "[[…]]"`. Never edit its text.
   6. `vault-lint`, `tasks-sync`, commit; one line per transcript: meeting, people, decisions, commitments, tasks routed.
2. **Inbox** (`/inbox`): transcripts first; then each capture — the owner's thinking → `notes/`; material from elsewhere → `sources/` with `kind`; entities extracted per Rule 6.
3. **Projects** (`project-import <repo>` then a hub): see *Projects* below.
4. **Daily note**: drafted from `tasks-sync --json` plus open commitments due this week and people met yesterday. `/today` to review.
5. **Review** (`/review`, weekly): inbox count, unprocessed transcripts, open commitments past due, `vault-lint` errors, entities created this week, Unassigned emptied.
6. **Answer questions**: properties first (Dataview, or `rg` over front matter), then `rg` over text; cite the notes used.

## Projects

A project's identity is its repo, not a folder on this machine. `memory/projects/<repo>.md` exists for every project worth remembering, checked out or not.

- **Import**: `project-import <owner/repo>` writes `sources/repos/<repo>.md` (generated, `as_of: <sha>`): GitHub metadata, languages, commit history in brief, the file tree, and README / CLAUDE.md / DECISIONS.md. No clone needed. Claude then writes the hub from that snapshot, cloning shallowly to a temporary directory only when the code is needed.
- **Tiers**: a full hub for real projects; one row in `memory/projects/_catalogue.md` (generated by `project-import --catalogue`) for experiments, tutorials and stubs; nothing for forks without the owner's commits.
- **Lifecycle**: active → `tasks-sync` keeps the Tasks block live. Done or archived → `/archive` or `/graduate` sets `status` and `ended`, refreshes the snapshot, and freezes the Tasks block as "Open at close (<sha>)". The hub stays forever; the checkout can go. A deleted repo's hub records `cold:` (its R2 path).

## Capture

- Meetings: MacParakeet → `transcripts-sync` → `inbox/transcripts/`.
- Files, URLs, podcasts: `macparakeet-cli transcribe <input> --no-history --output-dir ~/vault/inbox/transcripts --format transcript`.
- Dictation: `inbox/quick.md`.
- Web: Obsidian Web Clipper → `inbox/`, properties `type: source`, `kind: clip`.
- Phone: a message, photo or voice note to the owner's Telegram bot → `inbox/` (`capture`, every 5 minutes on one machine; voice is transcribed there).
- Email: a Gmail label (`vault`) → `inbox/`, one note per email, `kind: email`.

## Maintaining the vault

Work on the vault itself (its schema, jobs and tools) happens in a session started here; read the latest `maps/handover-*.md` first. The vault holds data and this file; the code that serves it lives in the fleet brain, `~/claude-computer`:

| What | Where |
| --- | --- |
| scripts | `~/claude-computer/bin/`: `vault-nightly`, `vault-lint`, `tasks-sync`, `project-import`, `commitments`, `capture`, `transcripts-sync`, `feeds-sync`, `gcal` (each answers `--help`) |
| tests | `~/claude-computer/tests/<script>.sh`; CI runs them on every push |
| slash commands | `~/claude-computer/claude-global/commands/` (`inbox`, `transcripts`, `today`, `review`, `archive`, `graduate`) |
| this file's template | `~/claude-computer/templates/vault/CLAUDE.md`: keep the two identical |
| scheduled jobs | on the vault's home machine (`~/claude-computer/docs/machines/<host>.md`, launchd jobs); logs in `~/Library/Logs/claude-computer/<job>.log` |
| night-shift runs | `~/.cache/claude-computer/vault-nightly/<stamp>/` (Claude's JSON output; a failed run's worktree) |
| decisions | system ones in `~/claude-computer/docs/DECISIONS.md`; the vault's own under its Rules here |

A change to a script or command is a commit in `~/claude-computer` (fleet-wide: say so; run its test). A change to a scheduled job also updates that machine's file. Vault content is committed here. Tasks for the vault and its tooling live in this `TASKS.md`, tagged `#vault`.

## Plugins

`vault-setup` installs Obsidian Git (commit-and-sync, pull on open), Dataview (`Home.md`'s views need it) and Templater (`_templates/`); add others as you like — Homepage, pointed at `Home.md`, opens it on start. Plugin code (`main.js`, `styles.css`) is git-ignored: each machine fetches it at the version in the committed `manifest.json`. Generated files (`maps/tasks.md`, hub blocks, the night shift's work) are written on one machine only, the vault's home machine.
