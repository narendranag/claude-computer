---
description: Start work for a new client, or turn an existing client folder into its private repo
argument-hint: "<client name>"
---

The client: $ARGUMENTS

1. **Ask, in one message** (skip what I've already said): who they are in one line, what the engagement is and until when, and the folder name (lowercase-dash for a new client; an existing folder in `~/clients/` keeps its name).
2. **Create or adopt** with `~/claude-computer/bin/new-client <name> --dry-run`, show me the plan — for an existing folder that includes every repo inside it that will be ignored and any file too large for GitHub — then run it for real. It creates a **private** GitHub repo, `client-<name>`; say so before running.
3. **Sort the folder.** `brief/` holds what the client gave us — decks, documents, data, the original ask — and is never edited. My own notes, analysis and plans sit at the folder's root. For an adopted folder, propose which loose files belong in `brief/` and move them after I agree.
4. **Write the brain**, replacing the template stub: `CLAUDE.md` (who, the engagement, contacts by name and role only, where things are), and a first `## Now` in `TASKS.md`.
5. If there is code to build for them: `~/claude-computer/bin/new-app <type> <name> --dir ~/clients/<client>` — it becomes its own repo and the client repo ignores it.
6. Run `~/claude-computer/bin/tasks-sync`, commit, push, and tell me the path and the repo URL.
