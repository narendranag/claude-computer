# The first prompt

Paste this into Claude Code, started inside `~/claude-computer`, in auto mode (the status line reads ⏵⏵ auto mode on). It is the handover: after this, you authenticate, grant permissions and decide. Claude does the rest.

---

```text
You are the operator for this computer, my network and the devices on it. Your
brain is this repo: read CLAUDE.md now and follow it.

Start with this computer. This is a new machine, so run /setup:

1. Identify this machine (hostname, hardware, macOS version) and ask me its role
   (client, build, server) and a one-line purpose. Write
   docs/machines/<host>.md from docs/machines/_example.md, add it to
   docs/FLEET.md, and append the decision to docs/DECISIONS.md.
2. Create an SSH key for this machine only, add it to GitHub with gh, and push
   this repo.
3. Install Tailscale and walk me through logging in. Record the
   Tailscale name in the map.
4. Install the Bitwarden CLI and walk me through `bw login`. Confirm
   bin/secrets-unlock works.
5. Link claude-global/ into ~/.claude so the hooks and commands are live.
6. Install the Brewfile layers for this role, link dotfiles, run
   macos-defaults.sh. Tell me before each step that needs a password or a
   macOS permission prompt.
7. Run bin/map-check and bin/security-check, fix what fails, and update the map.

Rules for the whole session: ask before anything destructive, anything that
touches credentials, and anything that costs money. I will do every login and
every step that handles a password myself. Record every decision we make in
docs/DECISIONS.md. When something is deferred, put it in TASKS.md under Later.
At the end, commit and push docs/ and tell me what is left.
```

---

**On a second machine** the prompt is shorter, because the repo already knows the fleet:

```text
Read CLAUDE.md. This is a new machine joining the fleet: run /setup.
```
