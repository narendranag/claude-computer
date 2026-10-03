---
description: Rotate a secret — new value into the sops store, then re-test everything that uses it
argument-hint: "<service, e.g. tavily, telegram, r2>"
---

Rotate the secret for: $ARGUMENTS

I handle the credential itself; you handle everything around it.

1. Find every consumer: `rg -n "cc_secret $ARGUMENTS |secret\(\"$ARGUMENTS\"|$ARGUMENTS\." ~/claude-computer/bin ~/claude-computer/lib` and `secrets exec`/`secrets env` lines in `.envrc` files that name it, plus deploy secrets (`wrangler secret list`, `gh secret list` in repos that mention it, EAS).
2. Tell me where to generate the new key (the service's dashboard) and which `<name>.<field>` to update (from `secrets/secrets.example.yaml` and `docs/SECRETS.md`). I run `secrets set $ARGUMENTS.<field>` in a terminal; it commits and pushes. Other managers pick it up with their next `git pull`.
3. Re-test each wrapper with a harmless call (`--help` doesn't count; a real one-result query, `tg-send "rotation test"`, `rclone lsd` via the script's `--dry-run`). Report pass/fail per consumer.
4. For deploy secrets, give me the exact commands to update each (`wrangler secret put …`); run them only after I confirm, and never echo the value.
5. Remind me to revoke the old key at the service. Append a `DECISIONS.md` entry: `rotated <service> key` (no values, no key fragments).
