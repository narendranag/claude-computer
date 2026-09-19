# Contributing

This repo is a template, not a library. Most people should fork it, change it and never look back — that is the intended use, and nothing here asks you to contribute. But the parts that are genuinely general get better with other people's machines behind them, so pull requests are welcome.

## Setting up

```bash
git clone <your fork> && cd <the clone>
git config core.hooksPath .githooks   # gitleaks scans every commit; commits fail without it
brew install gitleaks shellcheck jq   # the three the checks need
```

Before opening a pull request, run what CI runs:

```bash
shellcheck bin/* lib/*.sh *.sh tests/*.sh .githooks/* claude-global/hooks/*.sh
bash -n <each of those>
./tests/install-dry-run.sh          # install.sh through twenty-two simulated machines, on stubs
./tests/vault-setup.sh              # vault-setup through eight, on stubbed curl and gh
jq -e . claude-global/settings.json
ruff check lib docs/diagrams
```

CI (`.github/workflows/ci.yml`) does exactly this on every push. Some `bin/` scripts are Python behind a `uv run --script` shebang rather than bash; the workflow sorts them out by shebang, so a new script needs no wiring.

## The rules the code follows

**Scripts over prose.** If a step is deterministic, it belongs in `bin/` as a script with a `--help` block and an exit code — not in a slash command, a `CLAUDE.md` paragraph, or a README instruction. Slash commands orchestrate scripts; they never reimplement them. A PR that adds a paragraph telling Claude to do something deterministic will get asked to add a script instead.

**bash 3.2.** macOS ships bash 3.2 and a new machine has nothing newer when setup starts. No associative arrays, no `mapfile`, no `${x^^}`. Process substitution and `[[ ]]` are fine. Anything that wants more should be Python with a `uv run --script` header.

**`lib/common.sh`.** Source it; use `cc_die`, `cc_need`, `cc_info`, `cc_confirm`, `cc_secret`, `cc_curl` and the `EX_*` exit codes rather than rolling your own. Consistent exit codes are what lets slash commands and hooks react to failures.

**No secret on a command line, ever.** Not in `curl`, not in `security`, not in a URL. `ps` is readable by every process on the machine. `cc_curl` and `cc_session_store` show the pattern.

**No personal data.** No real hostnames, usernames, email addresses, IP addresses, Tailscale names or chat IDs — in code, in docs, in examples, in test fixtures. Use `example-laptop`, `<person>`, `you@example.com`. `gitleaks` catches keys; it does not catch your home address.

**Markdown is Prettier-formatted.** `npx prettier --write <file>`.

## Testing a change to `/setup`

`/setup` is the hardest thing here to test, because it is the one thing that changes a machine. Do it in this order:

1. Read it end to end as a stranger who has just cloned the repo. Most bugs in it are ordering bugs — something used before the phase that installs it.
2. `/setup --dry-run` in a Claude Code session. It does every read and check and changes nothing, printing each command it would run and each file it would write.
3. `./setup-tools.sh --dry-run`, `./macos-defaults.sh --dry-run`, `./bin/new-app --dry-run <type> <name>` for the pieces it calls.
4. A spare Mac or a fresh user account if you have one. Say in the PR which of these you actually did — "read it and dry-ran it" is a fine and honest answer.

## How `/upstream` works

Instances of this template are private and full of one person's machines, so nothing is ever pushed from an instance to here. `/upstream` clones the template fresh into a temp directory, re-implements the lesson generically in that clone, runs `gitleaks` and a grep for anything personal, and opens a PR from there. If you are working from your own instance, use it — it exists so a good idea can travel without a machine map following it.

## What's wanted

- **Other cameras.** `bin/camera-ingest` now reads `CC_CAMERA_EXTS`, but the date and frame-number parsing has only met a handful of bodies. Sidecars, dual-card setups and cameras that name files differently are all open.
- **Linux.** `lib/common.sh` already branches for it and `bin/schedule` refuses outright. Systemd user timers in place of launchd, and an honest account of what does not translate, would make headless boxes first-class.
- **Other tools' equivalents.** Not everyone uses Bitwarden, Tailscale, R2, Obsidian or Ghostty. A clean second implementation behind the same script interface — 1Password instead of `bw`, S3 instead of R2 — is more useful than an argument about which is better.
- **Slash commands and scheduled jobs** you found you needed and the template does not have.
- **Corrections.** Anywhere the README claims more safety than the code delivers, say so. The "What this does not protect against" paragraph exists because of exactly that kind of note.

## What's not

Renaming things, restructuring the folder layout, or swapping a default because you prefer another one. The defaults are opinionated on purpose and the reasoning is in [`docs/TEMPLATE-DECISIONS.md`](docs/TEMPLATE-DECISIONS.md) — if a decision is wrong, argue with the reason recorded there. In your own instance, change whatever you like and record why in your `docs/DECISIONS.md`.

## Pull requests

One change per PR. Conventional commit subjects (`fix:`, `feat:`, `docs:`, `ci:`). Add a line under `## [Unreleased]` in `CHANGELOG.md`. Say what you tested and what you only reasoned about — this repo runs commands on people's machines, and a guess presented as a test is worse than an untested patch.

Security problems do not go in a pull request: see [`SECURITY.md`](SECURITY.md).
