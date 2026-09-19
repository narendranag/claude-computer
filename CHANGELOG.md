# Changelog

All notable changes to this template. Instances pin a tag and pull improvements through an `upstream` remote when they choose.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added

- `install.sh` — the one-liner behind `https://claude-computer.com/install.sh`. It does what the README's four commands do (Xcode Command Line Tools, Homebrew, `gh` and its login, the Claude Code cask) and then creates your private copy of the template, checking each component first so it is safe to re-run. `--dry-run`, `--yes`, `--dir`, `--name`, `--public-clone`; `CC_INSTALL_TEMPLATE` for forks. It is self-contained — it runs before the repo exists on the machine, so it cannot source `lib/common.sh`. Documented in [`docs/INSTALL.md`](docs/INSTALL.md).
- `tests/install-dry-run.sh` — twenty-two simulated machines through `install.sh`, on a temporary `PATH` of logging stubs. The load-bearing assertions are that no mutating command appears in the stub log during a dry run, and that no `/usr/bin` Xcode shim is invoked before the Command Line Tools are installed. In CI, in the `shell` job.

### Changed

- The README is repositioned to match the site: it is a GitHub template that sets up a Mac for a solo developer who works terminal-first in Claude Code — part stack, part organization, part process. The pitch now sits above the Quick start, with a byline and a link to [What's inside](https://claude-computer.com/whats-inside/), and a "Who's behind this" section near the end. The "IT help desk" framing is gone: a solo dev has no help desk, so the afternoons a solo dev loses go to Claude instead. The fleet it describes is the five machines it actually is.
- **A Claude Max subscription is the stated requirement**, not "Pro or Max". All-day sessions in auto mode are the whole point, and they outrun anything smaller. Changed in the README's Quick start, its Phase 0 and its Get started checklist. The `IMPORTANT` callout's statement about where auto mode is available is unchanged — it is a fact about Claude Code, not a requirement of this template.
- The README's Quick start leads with the one-line installer, `/bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)"`, and says how to read it first and how to dry-run it. The four commands stay in [The build](README.md#the-build) as the by-hand path, with the `--template` fallback.
- The hero and build diagrams follow the Quick start. The hero terminal shows the installer one-liner as what a human types — broken after `-c` with a shell continuation, in a terminal card widened to fit the URL — then the handover, `cd ~/claude-computer && claude` and the prompt paste; its headline is "Paste one command.", with "or type the four by hand" below it. The build diagram's phase 1 is "One command", counted as "4 steps · or by hand": the four commands are still steps 10–13, because the installer performs them, so the 38 steps, the step 14 pivot and the fifteen rebuild steps are unchanged. Both SVGs' `<title>`/`<desc>` and both README `alt` texts describe the new images. The other three diagrams are byte-identical. The hero's eyebrow now reads `CLAUDE-COMPUTER`; it was still `AI-FIRST MACHINE SETUP`, the project's pre-0.2.0 name, because it is prose inside `render.py` and the rename never reached it. The build diagram's canvas widens to 1480px so every step label clears its pill by the padding it has on the left — `Create or clone`, `Google consent`, `Headless boxes` and `Link ~/.claude` were touching or crossing the border — and `render.py` now estimates each label's width at render time and exits 1 listing any that would not fit, so this cannot come back silently.
- The README stops making the same point three times near the top. The `> [!NOTE]` under the Quick start no longer repeats the pitch's "opinionated on purpose" and "change what doesn't fit"; it keeps only where the reasons live (`docs/TEMPLATE-DECISIONS.md`) and where to record your own (`docs/DECISIONS.md`). The long personal paragraph, which opened the same way as the pitch two paragraphs above it, moves into "Who's behind this", where it reads as biography.
- `orbstack` is in `Brewfile.dev` and `Brewfile.server` on purpose — a machine installs `Brewfile` plus exactly one role layer, so a headless Mac that is not a dev machine still needs containers. Each line now says so.
- `docs/SECRETS.md` calls the analytics item `claude-computer/posthog-<name>`, which is what `/new-app`, `bin/new-app` and every `templates/*/.envrc` actually use. It said `posthog-<app>`.
- The README's "What's in the box" gains `install.sh`, `lib/`, `tests/` and `vscode-extensions.txt`; `CLAUDE.md`'s "Where things are" gains the extension list, so the two tables agree.

### Fixed

- `bin/schedule list` diffs the job table in the script's header against `JOBS` and exits 1 naming both when they disagree. The list lived twice — the table `--help` prints, and the variable the script runs on — and two copies drift.
- `install.sh` runs the repo suitability check before it prints "the half-filled clone at … finished off" on the resume path, the same way it already does before "already exists on GitHub — cloning it instead". A remote that fails the gate gets a `!` line naming the problem and then the refusal (exit 6), instead of a promise the script breaks one line later.
- `install.sh` runs the repo suitability check before it prints the "already exists on GitHub — cloning it instead of creating it" line. A repo that fails the gate now gets a `!` line naming the problem and then the refusal (exit 6), instead of a promise the script breaks one line later.
- `tests/install-dry-run.sh` builds each case's `PATH` from a hermetic directory of symlinks to a named list of system tools, instead of ending it in `/usr/bin:/bin`. Ubuntu runners ship a real `gh` at `/usr/bin/gh`, so the case that simulates a machine with nothing installed was handed one; it passed on macOS only because `gh` is in `/opt/homebrew/bin` there. `gh`, `git`, `brew`, `claude`, `pbcopy`, `xcode-select`, `clang`, `python3`, `make`, `sw_vers` and `security` are stubbed per case or absent on purpose, and `curl` is stubbed for every case so nothing reaches the network.
- `install.sh` no longer invokes `/usr/bin/git` before the Command Line Tools are installed. On a Mac without them, `/usr/bin/git`, `/usr/bin/clang` and `/usr/bin/python3` are one shim binary that opens the "install developer tools" GUI dialog when run, so the preflight's git-identity check popped that dialog on a genuinely fresh Mac — under `--dry-run` too, which promises to change nothing and ask nothing. Presence is now decided from the developer directory on disk, and git and clang are executed only once the real binaries are there.
- `install.sh` waits for GitHub to finish copying the template. `gh repo create --template` returns before the new repo is populated, so the `gh repo clone` straight after it could produce an empty clone and then die with a misleading "not a copy of the template". It now polls for up to 60 seconds, and a clone of your own repo with no `CLAUDE.md` in it is recognised as resumable rather than refused with exit 4.
- `install.sh` qualifies `gh repo view` and `gh repo clone` with the account once it is known: a bare repo name can resolve against the current directory's git remote instead of the logged-in user.
- `install.sh` no longer takes the "already exists → clone" path on the name alone. On the template owner's account `claude-computer` _is_ the template, and on a contributor's it is most likely a public fork — either way the installer would have cloned a public repo as the user's private fleet brain, which holds a map of their machines. It now asks `gh` whether the repo is private and not a template, and stops with the new exit code **6** if it is not, before anything on the machine has changed. A private fork is allowed and said out loud. The same check covers the resume-from-empty-clone path, and a freshly created repo is confirmed private before it is cloned; an existing local clone with a public origin is warned about loudly rather than blocked, because `/setup` and the Stop hook have their own guard.
- `install.sh --dry-run` no longer needs a terminal. It changes nothing and asks nothing, so it works down a pipe (`curl … | bash -s -- --dry-run`) and says once that a real run needs a terminal. Real runs are still refused without one, with exit 2.

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
