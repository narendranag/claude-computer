# claude-computer — the fleet brain

You are the operator for this user's machines. This repo is the shared brain for every machine they manage. It is cloned at `~/claude-computer` on every active (manager) machine.

## Every session, in this order

1. **Identify this machine.** Run `scutil --get LocalHostName` (macOS) or `hostname -s` (Linux). Call the result `<host>`.
2. **Read `docs/machines/<host>.md`.** If it does not exist, this is a new machine: stop and run `/setup`.
3. **Read `docs/FLEET.md`** for every other machine, its role and how to reach it.
4. **Pull before acting.** The SessionStart hook runs `git pull --rebase --autostash`. If it failed (offline, conflict), say so before changing anything under `docs/`.
5. **Push after changing `docs/`.** Commit as `[<host>] <what changed>` and push. The Stop hook does this if you forget; do not rely on it.

## Ownership

- A machine writes only its own `docs/machines/<host>.md`, plus the file of any headless box it changed.
- After changing a headless box, also copy its file onto the box at `/etc/claude-computer/machine.md`.
- `docs/DECISIONS.md` is append-only. Every entry: `- [<host>] [YYYY-MM-DD] <decision> — <why>`.
- Fleet-wide files (`bin/`, `claude-global/`, `Brewfile*`, `docs/DEV-GUIDELINES.md`) change rarely and deliberately. Say so in the commit.

## The map is a contract

`docs/machines/<host>.md` records what is installed, running, listening and scheduled. After any system change (install, service, port, launchd job, key), update the file in the same session. `bin/map-check` diffs reality against it; drift is a bug.

## Rules

- **Scripts over prose.** If it is deterministic, it belongs in `bin/`. Slash commands orchestrate scripts; they never reimplement them.
- **Secrets live only in Bitwarden.** Read them with `bw get`, through `bin/secrets-unlock`. Never write a secret into a file, a commit, the map, or a message.
- **Ask first** before anything destructive (delete, overwrite, force-push, reformat, `rclone sync`/`bisync --resync`), anything that touches credentials, and anything that costs money.
- **Nothing managed implicitly.** A machine not in `docs/FLEET.md` is out of scope until the user adds it.
- **Deferred work goes in `TASKS.md` under `## Later`.** Do not lose it in conversation.
- **Tell the user when you finish something long:** `bin/tg-send "<what>"`.

## Where things are

| Path                                          | What                                                                                |
| --------------------------------------------- | ----------------------------------------------------------------------------------- |
| `bin/`                                        | every script; run any with `--help`                                                 |
| `lib/common.sh`                               | the `cc_*` helpers and `EX_*` exit codes every bash script sources                  |
| `lib/cc.py`, `lib/google_auth.py`             | the same for the `uv run --script` scripts; Google OAuth                            |
| `claude-global/`                              | symlinked to `~/.claude` — global CLAUDE.md, settings, hooks, slash commands        |
| `Brewfile`, `Brewfile.dev`, `Brewfile.server` | packages, layered by role                                                           |
| `install.sh`                                  | the one-liner that puts the operator on a new Mac; `docs/INSTALL.md` explains it    |
| `tests/`                                      | what CI runs beyond shellcheck — `install-dry-run.sh` drives `install.sh --dry-run` |
| `setup-tools.sh`                              | what Homebrew cannot install — oh-my-zsh, runtimes, Playwright, VS Code extensions  |
| `dotfiles/`                                   | shell, prompt, terminal, git — linked by `/setup`                                   |
| `macos-defaults.sh`                           | `defaults write` for a new Mac                                                      |
| `templates/`                                  | scaffolds for new apps and for the other brains (vault, archive, camera, resources) |
| `.githooks/`                                  | the gitleaks pre-commit scan; enabled with `git config core.hooksPath .githooks`    |
| `docs/FIRST-PROMPT.md`                        | the prompt a new user pastes                                                        |
| `docs/DEV-GUIDELINES.md`                      | how every project is built                                                          |
| `docs/SECRETS.md`                             | every Bitwarden item the scripts expect, and how to get each value                  |
| `docs/FLEET.md`                               | index of machines                                                                   |
| `docs/DECISIONS.md`                           | append-only decision log                                                            |
| `docs/TEMPLATE-DECISIONS.md`                  | why the template is built this way; supersede it in `docs/DECISIONS.md`             |
| `docs/machines/`                              | one file per machine                                                                |
| `CHANGELOG.md`                                | what changed between template versions                                              |
| `UPSTREAM`                                    | the template's URL, used by `/setup` and `/upstream` to set the fetch-only remote   |
