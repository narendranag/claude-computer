---
host: example-laptop
role: client            # client | server | build | nas | pi
kind: manager           # manager (has a clone + Claude Code) | headless
os: macOS 26
brewfile_layers: [base, dev]
tailscale_name: example-laptop
ssh: off                # off | tailscale-ssh | openssh-key-only
managed_by: self        # self, or the manager hosts that touch this box
updated: 2026-01-01
---

# example-laptop

Copy this file to `docs/machines/<host>.md` (the output of `scutil --get LocalHostName`) and fill it in. `/setup` does this for you. Sections marked **(checked)** are parsed by `bin/map-check`: keep one item per bullet, backticked.

## Identity

- Hardware: MacBook Pro, Apple silicon, 32 GB
- Purpose: daily driver; travels
- Time Machine target: external disk `TM-Example`, hourly

## Brew (checked)

Anything installed beyond the Brewfile layers named in the frontmatter. `map-check` treats the layers plus this list as the expected set.

- `example-formula`

## VS Code extensions (checked)

Beyond `vscode-extensions.txt`.

- `publisher.extension-id`

## launchd jobs (checked)

User agents in `~/Library/LaunchAgents` and daemons this machine owns, by label.

- `com.github.domt4.homebrew-autoupdate`
- `local.claude-computer.*` — tasks-sync, transcripts-sync (watches the MacParakeet database), feeds-sync …
- `com.google.*` — Chrome updaters (a glob covers a vendor's helpers)

## Listening ports (checked)

`<port>` — `<process>` — why. Loopback-only listeners can be omitted.

- `22000` — `syncthing` — file sync

## Services

- Syncthing: shares `~/projects/_shared` with `example-desktop`

## Keys

Where keys live, never the keys themselves.

- SSH: `~/.ssh/id_ed25519` (this machine only), registered on GitHub as `example-laptop`
- Secrets: Bitwarden, via `bin/secrets-unlock`

## Sensitive locations

Paths holding logged-in state or personal data. Never committed, never synced by git, never read into a note or message.

- `~/.config/browse/profiles/` — Playwright Chromium profiles with logged-in sessions (`browse --profile`); mode 700
- `~/resources/` — family documents (encrypted in R2)
- `~/Library/Application Support/MacParakeet/` — meeting recordings and transcripts

## Security baseline

- FileVault: on
- Firewall: on, stealth mode
- sshd: off (client role)

## Notes

Anything that would surprise the next session on this machine.
