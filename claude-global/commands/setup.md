---
description: Bring this machine into the fleet (new machine, or first run of a fresh instance)
argument-hint: "[--dry-run]"
---

Set up this machine as part of the fleet. Follow `CLAUDE.md` in this repo throughout. If `$ARGUMENTS` contains `--dry-run`, do every read and check but **change nothing**: print each command you would run and each file you would write, then stop.

Before each numbered phase, tell me in three lines what you are about to do and what you need from me.

**Paths.** The repo must live at `~/claude-computer`; hooks, permissions and `PATH` all assume it. `bin/` is not on this shell's `PATH` until phase 6 and a new shell, so until then always call scripts as `./bin/<name>` from the repo root.

**Resuming.** Phase 4 ends with a restart of Claude Code. Before it, write `- [ ] Resume /setup at phase 5 (<host>)` under `## Now` in `TASKS.md`. When `/setup` starts, check `TASKS.md` for a resume line and continue from that phase, then tick it.

## 0. Where are we

- `pwd` must be `~/claude-computer`. If it isn't, stop and tell me to move the clone there (`mv <path> ~/claude-computer`) and restart Claude in it.
- `git remote -v`, `ls docs/machines/`, `gh auth status`.
- Ask me for my name and git email. Copy `dotfiles/gitconfig` to `~/.gitconfig` (back up an existing one to `~/.gitconfig.backup-<date>` and carry over anything personal from it), filling `{{git_name}}` and `{{git_email}}`. Git needs an identity before the first commit below.
- Install the secret scanner before any commit: `brew install gitleaks`, then `git config core.hooksPath .githooks`.
- **If a `.template` file exists**, this is a fresh copy of the public template becoming your private instance. Check `gh repo view --json visibility` says `PRIVATE` — stop if it doesn't. Then, after I confirm: delete `.template`; remove the `docs/machines/*` lines from `.gitignore`; add the template as a fetch-only remote using the URL in `UPSTREAM` (`git remote add upstream "$(cat UPSTREAM)" && git remote set-url --push upstream DISABLED`); fill the placeholders in `claude-global/CLAUDE.md` (`{{user_name}}` from me, `{{github_user}}` from `gh api user --jq .login`); commit `[<host>] instance: initialise from template` and push. `origin` is still HTTPS here, which `gh` authenticates; phase 2 switches it to SSH.

## 1. Identity

- Host: `scutil --get LocalHostName`. Hardware: `system_profiler SPHardwareDataType`. OS: `sw_vers`. CPU: `uname -m` (Apple silicon or Intel changes what installs).
- If `docs/machines/<host>.md` exists, read it and treat this as a **rebuild**: skip questions it already answers.
- Otherwise ask me: role (client / build / server), one-line purpose, and whether sshd should be on. Write `docs/machines/<host>.md` from `docs/machines/_example.md`; add a row to `docs/FLEET.md` with `—` for the Tailscale name and Brewfile layers (filled in phases 3 and 6); append the decision to `docs/DECISIONS.md`.

## 2. SSH key and GitHub

- `ssh-keygen -t ed25519 -C "<host>" -f ~/.ssh/id_ed25519 -N ""` only if no key exists. One key per machine, never copied. Ask me whether I want a passphrase (then I run the command myself).
- `gh ssh-key add` needs the `admin:public_key` scope. If `gh auth status` doesn't list it, I run `gh auth refresh -h github.com -s admin:public_key` (a browser step). Then `gh ssh-key add ~/.ssh/id_ed25519.pub --title "<host>"`.
- Trust GitHub's host keys from GitHub's API, not from a first-connection prompt nobody can answer: `gh api meta --jq '.ssh_keys[]' | sed 's/^/github.com /' >> ~/.ssh/known_hosts`.
- Switch `origin` to SSH (`git remote set-url origin git@github.com:<user>/claude-computer.git`), `git push`, and confirm it worked.

## 3. Tailscale

- `brew install --cask tailscale-app` if missing. I log in with the identity provider I chose for the tailnet. Record the Tailscale name in the machine file and `FLEET.md`.

## 4. Global Claude config

This comes before Bitwarden so the deny rules (no raw `bw get` / `bw list`) are in force from here on.

- **`brew install jq` first.** Every hook in `claude-global/hooks/` parses its stdin with `jq`, and phase 6's `brew bundle` is still several phases away. Link the hooks before `jq` exists and they run without a session id, so the Stop hook can't tell a long turn and the Notification hook sends an empty message.

Link the **contents** of `claude-global/`, not the directory — `~/.claude` also holds session transcripts and state that must never enter a repo:

```
~/.claude/CLAUDE.md      → ~/claude-computer/claude-global/CLAUDE.md
~/.claude/settings.json  → ~/claude-computer/claude-global/settings.json
~/.claude/commands       → ~/claude-computer/claude-global/commands
~/.claude/hooks          → ~/claude-computer/claude-global/hooks
```

If any of these already exist, **don't just move them aside**: show me a diff of each against the repo version, propose a merge (my existing permissions, hooks and commands into `claude-global/` — this repo is private, so they belong there), apply what I approve, and only then back the originals up to `~/.claude/backup-<date>/` and link.

Write the resume line in `TASKS.md` (see top), commit, and tell me to restart Claude Code in `~/claude-computer`. After the restart, confirm the status line shows auto mode. If auto mode isn't available on this account or model, the session starts in Manual; tell me, and carry on — the ask and deny rules work the same.

## 5. Bitwarden

- `brew install bitwarden-cli` if missing. I run `bw login` myself, then `./bin/secrets-unlock` in a terminal. You verify with `./bin/secrets-unlock --status`.
- `./bin/secrets-unlock --check` reports which of the items in `docs/SECRETS.md` exist, without reading any value. Missing items are fine for now: list them in `TASKS.md` under `## Later` with the service each one unlocks.

## 6. Environment

- **Show me what's about to install first.** Print the casks in `Brewfile` and the role layer, and ask which apps I don't want; comment those lines out in this instance (and note why in `DECISIONS.md`). Then `brew bundle --file Brewfile` and the role layer (`Brewfile.dev` for machines that build software, `Brewfile.server` for headless Macs). Warn me before casks that need a password. Record the layers in the machine file and `FLEET.md`.
- Link `dotfiles/` (map in `dotfiles/README.md`; existing files → `*.backup-<date>`). `gitconfig` was copied in phase 0.
- `./setup-tools.sh --dry-run`, then for real: oh-my-zsh, mise runtimes, **Playwright + its bundled Chromium** (headless browsing for `bin/browse` and e2e tests), the `macparakeet-cli` link, VS Code extensions, the daily `brew autoupdate` agent.
- Confirm `./bin/browse https://example.com` prints markdown. Record `~/.config/browse/profiles/` under **Sensitive locations** in the machine file.
- **MacParakeet** (Apple silicon only — skip on Intel): three human steps in the app — tell me each one and wait: grant **Microphone**; grant **Screen Recording** (system audio for meetings); download the **Parakeet v3** model when onboarding offers it. Verify with `macparakeet-cli health --json` (database ok, `parakeetModelVariant: v3`). Ask whether I want its telemetry off (`macparakeet-cli config set telemetry off`). Then `./bin/schedule install transcripts-sync`, and record the job and `~/Library/Application Support/MacParakeet/` under **Sensitive locations**.
- `./macos-defaults.sh --dry-run` — show me the list, then run it.

## 7. Protection

- **Firewall**: `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on` — I type the password.
- **FileVault**: if `fdesetup status` says off, I turn it on in System Settings → Privacy & Security, and store the recovery key in Bitwarden myself.
- **Time Machine**: ask me which target (external disk or a box on the tailnet); I enable it in System Settings. Record it in the machine file.

## 8. Verify and record

- A new shell now has `bin/` on `PATH`. `tg-send "hello from <host>"` — I confirm it arrived (skip if the Telegram item is still missing).
- `map-check`. Fix the machine or the map until it is clean; `security-check` must pass.
- Update `docs/machines/<host>.md`, append decisions, tick the resume line, commit `[<host>] setup complete`, push.
- Folders, brains and workflows come next and are separate jobs. Add them to `TASKS.md` under `## Next`: create `~/personal`, `~/projects/_scratch`, `~/products`; **the vault: `./bin/vault-setup`** — it creates `~/vault` from `templates/vault` and installs Obsidian Git, Dataview and Templater from Obsidian's registry, which is third-party code, so read what it prints; **ask me before passing `--create-remote`**, which publishes the vault to GitHub. It comes after phase 6, which installs the `obsidian` cask. Then `~/archive`, `~/library/camera`, `~/resources` brains from `templates/`; `schedule install` for tasks-sync, feeds-sync, the daily note and map-check. Tell me what is left.
- `vault-setup` ends with two steps nobody can script. Put both in `TASKS.md` under `## Next`: turn off Obsidian's restricted mode (Settings → Community plugins), and install the Obsidian Web Clipper extension saving to `inbox/`.
