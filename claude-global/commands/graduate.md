---
description: Graduate a project from ~/projects to ~/products once it is in production
argument-hint: "<project name>"
---

Graduate `~/projects/$ARGUMENTS` to `~/products/$ARGUMENTS`.

1. Check: the repo is clean and pushed; it has a deploy (ask me where it runs); no other worktrees are open (`git worktree list`). Stop and tell me if not.
2. `mkdir -p ~/products && mv ~/projects/$ARGUMENTS ~/products/` — after I confirm.
3. Fix anything that pointed at the old path: `rg -l "projects/$ARGUMENTS"` across `~/claude-computer`, `~/vault`, and the project itself; any launchd plists that reference it (`rg -l` in `~/Library/LaunchAgents`); VS Code workspaces.
4. In the project's `CLAUDE.md`, add a **Production** section: where it runs, how to deploy, how to roll back, where errors and analytics go.
5. Update the vault hub (`status: production`), `docs/machines/<host>.md` if services run here, append a `DECISIONS.md` entry, run `tasks-sync`. Commit each repo touched.
