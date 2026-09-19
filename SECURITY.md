# Security policy

## Reporting a vulnerability

**Do not open a public issue.** Report it privately through GitHub security advisories: go to the **Security** tab of this repository, choose **Report a vulnerability**, and fill in the form. That opens a private thread visible only to you and the maintainer.

Useful things to include, as far as you know them:

- what the problem is, and what an attacker gets out of it
- the file and, if you can, the line
- the macOS version and chip you saw it on
- how to reproduce it, or why you believe it without having run it

You will get a first reply within a week. There is no bounty; this is one person's template repository.

## What is in scope

Anything in this repo that would expose a secret, run something the user did not ask for, or widen what Claude Code is allowed to do:

- a path where a secret reaches a command line, a file, a log, a commit or a message
- a way past the `ask` or `deny` rules in `claude-global/settings.json`
- a script that can be made to write, delete or upload somewhere it should not
- a scheduled job or hook that does more than its description says
- a scaffold or template that ships an insecure default into every new project

## What is not

- **The design limits, which are documented.** The deny rules are pattern matches, not a sandbox; the Bitwarden session token is in the login Keychain where every process the user runs can read it; the `Stop` hook pushes `docs/` at the end of every turn; the `daily-note` job runs Claude unattended. These are described in the README under [Trust](README.md#trust). If you have found a way to make one of them worse than described, that is in scope — the limit itself is not.
- Vulnerabilities in the tools this repo installs. Report those upstream: Homebrew, Claude Code, Bitwarden, rclone, Tailscale, Playwright.
- Anything that needs an attacker who is already running code as the user. At that point the machine is theirs.
