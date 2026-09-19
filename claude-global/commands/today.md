---
description: Open or draft today's daily note from tasks across every brain
---

Work in `~/vault`, following its `CLAUDE.md`.

1. `~/claude-computer/bin/tasks-sync --json` for the task picture, then `tasks-sync` to refresh the vault copies.
2. Open `daily/<YYYY-MM-DD>.md`. If the scheduled job already drafted it, review it; otherwise create it from `_templates/daily.md`:
   - **Now** — open `## Now` tasks across all brains, grouped by brain, overdue first (⚠️).
   - **Due this week** — anything with `📅` in the next 7 days.
   - **Closed yesterday** — tasks with `✅ <yesterday>`.
   - **Reading** — link to `sources/feeds/<today>.md` if it exists.
   - **Notes** — empty, for me.
3. Show me the note in five to ten lines and ask what to add. Anything I say that is a task goes to the owning brain's `TASKS.md` (not the daily note); anything else goes under **Notes**.
4. Commit the vault.

The daily note is drafted from tasks, not the calendar. Link `[[projects/<brain>]]` hubs; don't copy task text that tasks-sync already renders.
