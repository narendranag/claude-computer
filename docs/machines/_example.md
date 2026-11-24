---
host: example-laptop
role: client # client | server | build | nas | pi
kind: manager # manager (has a clone + Claude Code) | headless
os: macOS 26
brewfile_layers: [base, dev]
tailscale_name: example-laptop
ssh: off # off | tailscale-ssh | openssh-key-only
managed_by: self # self, or the manager hosts that touch this box
age_recipient: # managers: this machine's age public key, written by `secrets init`
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

## Brew skipped

Brewfile entries deliberately not installed on this machine, so they are not reported as missing. Not otherwise checked.

- `some-formula`

## Listening ports (checked)

`<port>` — `<process>` — why. Loopback-only listeners can be omitted.

- `8000` — `uvicorn` — example-app's API, reached over the tailnet
- `rapportd:*` — rapportd — Continuity; ports change every boot (`<process>:*` accepts any port that process listens on)

## Services

- example-app API (`uvicorn`, port 8000), started by `local.claude-computer.example-app`

## Keys

Where keys live, never the keys themselves.

- SSH: `~/.ssh/id_ed25519` (this machine only), registered on GitHub as `example-laptop`
- Secrets: sops + age — this machine's key at `~/.config/sops/age/keys.txt` (mode 600); its public half is `age_recipient` above

## Sensitive locations

Paths holding logged-in state or personal data. Never committed, never synced by git, never read into a note or message.

- `~/.config/browse/profiles/` — Playwright Chromium profiles with logged-in sessions (`browse --profile`); mode 700
- `~/.config/sops/age/` — this machine's age key, which opens every secret in the store (mode 700/600)
- `~/.agent-reach/` — Agent Reach config; `config.yaml` holds cookies and keys once a login channel is added (mode 600)
- `~/resources/` — family documents (encrypted in R2)
- `~/Library/Application Support/MacParakeet/` — meeting recordings and transcripts

## Security baseline

- FileVault: on
- Firewall: on, stealth mode
- sshd: off (client role)

## Notes

Anything that would surprise the next session on this machine.
