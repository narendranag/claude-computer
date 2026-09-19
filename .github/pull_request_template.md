<!--
One change per PR. Conventional commit subject: fix: / feat: / docs: / ci: / chore:
Security problems do not belong here — use a private advisory (SECURITY.md).
-->

## What and why

<!-- What changes, and what goes wrong without it. Two or three sentences. -->

## What I tested

<!--
Be exact about tested versus reasoned. This repo runs commands on other people's
machines, and "I read it carefully" is a fine answer — a guess presented as a test
is not. Delete what doesn't apply.
-->

- [ ] `shellcheck` on the files I touched
- [ ] `bash -n` on the files I touched
- [ ] Ran the script with `--help` and with `--dry-run`
- [ ] Ran it for real, on: <!-- macOS version + chip -->
- [ ] `/setup --dry-run` in a Claude Code session
- [ ] Only reasoned about, not run: <!-- which parts, and why -->

## Checks

- [ ] bash 3.2 compatible (no associative arrays, no `mapfile`, no `${x^^}`)
- [ ] Uses the `sm_*` helpers and `EX_*` exit codes from `lib/common.sh`
- [ ] No secret reaches a command line, a file, a log or a message
- [ ] No real hostnames, usernames, email addresses, IPs, Tailscale names or chat IDs anywhere in the diff
- [ ] `--help` text updated if behaviour or flags changed
- [ ] The map contract holds: anything that changes a machine is recorded where `bin/map-check` will look
- [ ] Markdown run through Prettier
- [ ] A line added under `## [Unreleased]` in `CHANGELOG.md`
- [ ] A line added to `docs/TEMPLATE-DECISIONS.md` if this changes a default, with the reason
