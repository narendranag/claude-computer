---
description: Start a new project — decide the target, scaffold it, write its brain
argument-hint: "[short description of the idea]"
---

The idea: $ARGUMENTS

1. **Ask, in one message** (skip what the idea already answers): what it does in one sentence, who it is for (me / family / public), and which target — **web**, **mobile**, **cli** or **desktop** — per `~/claude-computer/docs/DEV-GUIDELINES.md`. Propose the target you think fits and why. Propose a lowercase-dash name.
2. **Scaffold** with `~/claude-computer/bin/new-app <type> <name> --dry-run`, show me the steps, then run it for real. It creates a **private** GitHub repo; say so before running.
3. **Write the brain** in the new repo, replacing the template stubs:
   - `CLAUDE.md`: what and for whom, the stack chosen and any deviation from DEV-GUIDELINES with the reason, how to run/test/deploy, pointer to `~/claude-computer/docs/`.
   - `TASKS.md`: a first `## Now` of three to five concrete tasks to reach something runnable.
   - `DECISIONS.md`: the target choice and why.
4. If it needs analytics/errors, note the PostHog key item to create in Bitwarden (`claude-computer/posthog-<name>`) — I create it.
5. Run `~/claude-computer/bin/tasks-sync` so the vault hub appears. Commit, push, and tell me the path and repo URL.
