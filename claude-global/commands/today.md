---
description: Open or draft today's daily note from tasks across every brain
---

Work in `~/vault`, following its `CLAUDE.md`.

1. `~/claude-computer/bin/tasks-sync --json` for the task picture, then `tasks-sync` to refresh the vault copies. `~/claude-computer/bin/commitments brief --json` for the memory picture: open commitments overdue and due in the next 7 days, and the people met yesterday. The script does the selecting; don't redo it by reading `memory/`.
2. Open `daily/<YYYY-MM-DD>.md`. If the scheduled job already drafted it, review it; otherwise create it from `_templates/daily.md`. `## Overnight` (what `vault-nightly` did, between its markers) belongs to that job: keep it as it is, first after the title. Then:
   - **Now** — open `## Now` tasks across all brains, grouped by brain, overdue first (⚠️).
   - **Due this week** — anything with `📅` in the next 7 days.
   - **Commitments** — from `brief`: `overdue` first (⚠️), then `due_soon`, each as `[[memory/commitments/<id>|<title>]]` with who owes whom and the due date. Mine (`mine: true`) before those owed to me. None → leave the heading with "None due."
   - **Met yesterday** — from `brief`'s `met.people`: `[[<id>|<name>]]` and the meetings they were in, linked (`[[<meeting id>|<title>]]`). None → drop the heading.
   - **Closed yesterday** — tasks with `✅ <yesterday>`.
   - **Reading** — link to `sources/feeds/<today>.md` if it exists.
   - **Notes** — empty, for me.
3. Show me the note in five to ten lines and ask what to add. Anything I say that is a task goes to the owning brain's `TASKS.md` (not the daily note); anything else goes under **Notes**.
4. Commit the vault.

The daily note is drafted from tasks and `memory/` (through `commitments brief`), not the calendar. Link hubs as `[[memory/projects/<brain>|<brain>]]` (`tasks-sync` keeps each one's Tasks block); don't copy task text that tasks-sync already renders.
