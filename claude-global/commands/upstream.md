---
description: Turn a lesson from this private instance into a generic PR against the public template
argument-hint: "<what to upstream>"
---

Upstream: $ARGUMENTS

**Never push from the instance to the template.** The template is public; the instance is not.

1. Identify the change in this instance (files, commits). Explain the lesson in two sentences.
2. Clone the template fresh into a temp dir: `gh repo clone <template> "$(mktemp -d)/template"` (the `upstream` remote URL tells you which), and branch `upstream/<slug>`.
3. **Never carry a section headed "This instance (not for upstream)"** (an instance may add one to any shared document, such as DEV-GUIDELINES). **Rewrite, don't copy.** Re-implement the change generically in the clone: no hostnames, Tailscale names, emails, usernames, chat IDs, paths under a real home, personal folder names, services only I use. Use placeholders like `example-laptop` and `<person>`.
4. Hygiene before committing, in the clone:
   - `gitleaks git --redact --no-banner` and `gitleaks dir . --redact --no-banner`
   - `rg -i "$(whoami)|$(scutil --get LocalHostName)|<tailnet name>|@gmail|@icloud"` → must be empty
   - `ls docs/machines/` → only `_example.md`
   - `ls secrets/` → only `README.md` and `secrets.example.yaml`; no `.sops.yaml`; `rg 'AGE-SECRET-KEY-1[0-9A-Z]{58}|ENC\[AES256' .` → must be empty
5. Add a CHANGELOG entry under `[Unreleased]`, show me the full diff, and only after I approve: push the branch and `gh pr create` against the template.
