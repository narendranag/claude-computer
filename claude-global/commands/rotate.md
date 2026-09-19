---
description: Rotate a secret — new value into Bitwarden, then re-test everything that uses it
argument-hint: "<service, e.g. tavily, telegram, r2>"
---

Rotate the secret for: $ARGUMENTS

I handle the credential itself; you handle everything around it.

1. Find every consumer: `rg -n "cc_secret $ARGUMENTS|secret\(\"$ARGUMENTS" ~/claude-computer/bin ~/claude-computer/lib`, plus deploy secrets (`wrangler secret list`, `gh secret list` in repos that mention it, EAS).
2. Tell me where to generate the new key (the service's dashboard) and which Bitwarden item to update (`claude-computer/$ARGUMENTS`, field names from `docs/SECRETS.md`). I update the item, then run `bw sync` / `secrets-unlock` in a terminal.
3. Re-test each wrapper with a harmless call (`--help` doesn't count; a real one-result query, `tg-send "rotation test"`, `rclone lsd` via the script's `--dry-run`). Report pass/fail per consumer.
4. For deploy secrets, give me the exact commands to update each (`wrangler secret put …`); run them only after I confirm, and never echo the value.
5. Remind me to revoke the old key at the service. Append a `DECISIONS.md` entry: `rotated <service> key` (no values, no key fragments).
