# Fleet

Every machine this brain manages. A machine not listed here is out of scope.

- **Manager** machines have a clone of `claude-computer` and run Claude Code.
- **Headless** machines have no brain; a manager reaches them over SSH via Tailscale. Each keeps a copy of its file at `/etc/claude-computer/machine.md`.

| Host | Role | Kind | Tailscale name | Brewfile layers | Managed by | File |
|---|---|---|---|---|---|---|

<!-- Example row (delete when adding the first real machine):
| my-laptop | client | manager | my-laptop | base, dev | self | machines/my-laptop.md |
-->
