# Changelog

All notable changes to this template. Instances pin a tag and pull improvements through an `upstream` remote when they choose.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added

- `install.sh` — the one-liner behind `https://claude-computer.com/install.sh`. It does what the README's four commands do (Xcode Command Line Tools, Homebrew, `gh` and its login, the Claude Code cask) and then creates your private copy of the template, checking each component first so it is safe to re-run. `--dry-run`, `--yes`, `--dir`, `--name`, `--public-clone`; `CC_INSTALL_TEMPLATE` for forks. It is self-contained — it runs before the repo exists on the machine, so it cannot source `lib/common.sh`. Documented in [`docs/INSTALL.md`](docs/INSTALL.md).
- `tests/install-dry-run.sh` — thirteen simulated machines through `install.sh`, on a temporary `PATH` of logging stubs. The load-bearing assertions are that no mutating command appears in the stub log during a dry run, and that no `/usr/bin` Xcode shim is invoked before the Command Line Tools are installed. In CI, in the `shell` job.

### Fixed

- `install.sh` no longer invokes `/usr/bin/git` before the Command Line Tools are installed. On a Mac without them, `/usr/bin/git`, `/usr/bin/clang` and `/usr/bin/python3` are one shim binary that opens the "install developer tools" GUI dialog when run, so the preflight's git-identity check popped that dialog on a genuinely fresh Mac — under `--dry-run` too, which promises to change nothing and ask nothing. Presence is now decided from the developer directory on disk, and git and clang are executed only once the real binaries are there.
- `install.sh` waits for GitHub to finish copying the template. `gh repo create --template` returns before the new repo is populated, so the `gh repo clone` straight after it could produce an empty clone and then die with a misleading "not a copy of the template". It now polls for up to 60 seconds, and a clone of your own repo with no `CLAUDE.md` in it is recognised as resumable rather than refused with exit 4.
- `install.sh` qualifies `gh repo view` and `gh repo clone` with the account once it is known: a bare repo name can resolve against the current directory's git remote instead of the logged-in user.

## [0.2.1] — 2026-09-19

### Fixed

- `bin/camera-ingest`: the argument check is an `if`, not `A && B || C` — Ubuntu's shellcheck reports SC2015 on that form, which failed the first CI run.
- `.prettierignore` keeps Prettier out of `templates/`, where it rewrote the literal `__NAME__` scaffold placeholder to `**NAME**`.

## [0.2.0] — 2026-09-19

Pre-launch hardening pass.

### Changed

- Renamed the project to `claude-computer`. It was formerly `ai-first-machine-setup` (this template's repo) and `system-manager` (the name every private instance cloned it under). The instance clone path, the Bitwarden item prefix, the Keychain service, the launchd label prefix and log directory, the `/etc` backstop path, and every `sm_*`/`SM_*` identifier in `lib/common.sh` and `lib/sm.py` (now `lib/cc.py`) all follow: `~/system-manager` → `~/claude-computer`, `system-manager/<item>` → `claude-computer/<item>`, `sm_*` → `cc_*`, `SM_*` → `CC_*`. There is no installed base yet, so this ships with no migration path — instances created before this release must re-home themselves by hand.

### Security

- The Bitwarden session token no longer reaches a command line when it is stored: the macOS Keychain write goes through `security -i` (commands on stdin) instead of `security add-generic-password -w "$token"`, whose argument any process can read with `ps`.
- Deny rules for the direct routes to that token — `security find-generic-password`, `dump-keychain`, `security export`, reads of `~/Library/Keychains`, `bw unlock`, `secrets-unlock --export`.
- The unattended `daily-note` job is constrained rather than trusted: `--allowedTools` limits it to `Read,Edit,Write,Glob,Grep` plus `git status`/`add`/`commit`, and `~/vault` is its working directory. It is the only job that runs Claude with nobody watching.
- `archive-push --delete-local` asks before each `rm -rf`, through `cc_confirm`, which answers no when there is no terminal. `--yes` carries an answer already given; `/archive` passes it only after the user has.
- The `map-check` job writes its report to a `mktemp` file instead of a fixed `/tmp/cc-map-check.txt`.

### Fixed

- `setup-tools.sh` and `new-app` set `fail=1` inside loops on the right of a pipe, where the subshell threw it away and both scripts exited 0 after a failed step. They read from process substitutions now.
- `new-app` ran the Tauri scaffolder in the caller's directory rather than the parent it was asked for, and a trailing `[ -d … ] && …` under `set -e` could exit 1 with no message.
- `setup-tools.sh` matched comment lines with `\s`, which BSD grep does not support.
- `/setup` installs `jq` in phase 4, before linking the hooks — every hook parses its stdin with `jq`, and `brew bundle` is two phases later.
- Scaffold placeholders are `__NAME__`, not `{{name}}`, which collided with just's own `{{…}}` interpolation in `templates/cli/justfile`.
- Three dead locals and an f-string with no placeholders in `docs/diagrams/render.py`; the rendered SVGs are unchanged.

### Added

- `camera-ingest` reads `CC_CAMERA_EXTS`, defaulting to RAF CR2 CR3 NEF ARW DNG ORF RW2 MOV MP4, instead of hard-coding one body's `RAF`/`MOV`.
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `SECURITY.md`, issue forms for bugs and for `/setup`, a pull request template, and `.github/workflows/ci.yml` — shellcheck, `bash -n`, `--help`, JSON and YAML validation, and ruff. `ruff.toml` records which style rules this codebase breaks on purpose.
- README: honest prerequisites (a recent macOS, Apple silicon versus Intel, running the `brew shellenv` lines the Homebrew installer prints, a fallback for `gh` without `--template`), and a "What this does not protect against" paragraph under Trust.
- The missing rows in the `CLAUDE.md` "Where things are" table: `lib/`, `setup-tools.sh`, `.githooks/`, `docs/SECRETS.md`, `docs/TEMPLATE-DECISIONS.md`, `CHANGELOG.md`, `UPSTREAM`.

## [0.1.0] — 2026-09-16

First public release.

### Added

- Repo layout: root brain (`CLAUDE.md`), `TASKS.md`, `claude-global/`, layered Brewfiles, dotfiles, `macos-defaults.sh`, `templates/`, `docs/`.
- Tier 1 scripts: `secrets-unlock`, `tg-send`, `tasks-sync`, `map-check`, `security-check`, `wt`.
- Service wrappers: `tavily`, `firecrawl`, `jina`, `exa`; Google wrappers `gcal`, `gmail`, `gdrive`.
- `browse`: headless Chromium via Playwright — markdown, screenshot or PDF; persistent profiles for logged-in pages. `setup-tools.sh` installs Playwright and its Chromium.
- Pipelines: `new-app` (web scaffold with Playwright e2e), `feeds-sync` (falls back to `browse` for dynamic pages), `archive-push`, `archive-pull`, `camera-ingest`, `resources-sync`.
- Voice pipeline: `macparakeet` cask, `transcripts-sync` (MacParakeet database → `vault/inbox/transcripts/`, cursor + id idempotency, launchd WatchPaths agent), `/transcripts` job; `## Unassigned` overflow in `tasks-sync` and `/review`.
- Slash commands: `/setup`, `/new-app`, `/archive`, `/retrieve`, `/inbox`, `/transcripts`, `/today`, `/review`, `/graduate`, `/upstream`, `/rotate`.
- Hooks: SessionStart (pull, unlock prompt, tasks-sync), Stop (push `docs/`), Notification (`tg-send`).
- Pre-commit secret scan (gitleaks); template guard against committing machine files.
- README with hand-drawn light/dark diagrams generated by `docs/diagrams/render.py`.
- Permission mode: auto, with explicit ask and deny rules.

[Unreleased]: https://github.com/narendranag/claude-computer/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/narendranag/claude-computer/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/narendranag/claude-computer/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/narendranag/claude-computer/releases/tag/v0.1.0
