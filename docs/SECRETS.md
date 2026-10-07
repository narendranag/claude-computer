# Secrets

**Machine secrets live in one sops file, `secrets/secrets.yaml`, in your private instance.** API keys, bot tokens, R2 credentials, the crypt password, Google's OAuth client: each is a `<name>.<field>` (`tavily.api_key`) whose value is encrypted with [sops](https://github.com/getsops/sops) to [age](https://age-encryption.org) keys — one per manager machine, plus a paper backup key. The key names are plaintext; the values never are. No keys in other files, the map, `rclone.conf`, shell history or messages.

There is no unlock step. Each machine's key is `~/.config/sops/age/keys.txt` (mode 600), protected at rest by FileVault; scripts in `bin/` decrypt the one value they need at run time, so launchd jobs and hooks work unattended. Human logins and passkeys don't belong here — keep them in your password manager.

`bin/secrets` does everything: `secrets --help` lists it. `secrets/README.md` has the files, the keys, and adding or removing a machine.

## First machine, and every one after

```bash
secrets init --first      # first machine only: its key, age_recipient in its machine file, .sops.yaml, the empty store
secrets backup-key        # in a terminal: write the paper key down twice, keep the sheets in two places
secrets backup-verify     # type it back: proves the paper copy opens the store
```

Every later machine: `secrets init` on it, then `git pull && secrets admit <host>` on a machine that can already read the store, then `git pull` on the new one. `secrets status` says whether this machine can read the store; `secrets check` lists which expected secrets are set, by name only.

## Secrets the scripts expect

Set each when you first need it — nothing breaks until a wrapper that uses it runs, and then it exits with code 5 and names the missing `<name>.<field>`. The shape is `secrets/secrets.example.yaml`.

| Secret                                                                 | What                                                                                                  | Used by                                                        |
| ---------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- |
| `telegram.token`, `telegram.chat_id`                                   | bot token · your chat id                                                                              | `tg-send`, hooks                                               |
| `tavily.api_key`                                                       | API key                                                                                               | `tavily`                                                       |
| `firecrawl.api_key`                                                    | API key                                                                                               | `firecrawl`, `feeds-sync`                                      |
| `jina.api_key`                                                         | API key                                                                                               | `jina`                                                         |
| `exa.api_key`                                                          | API key                                                                                               | `exa`                                                          |
| `r2.access_key_id`, `r2.secret_access_key`, `r2.endpoint`, `r2.bucket` | an R2 API token and where it points (`https://<account-id>.r2.cloudflarestorage.com`)                 | `archive-*`, `camera-ingest`, `library-push`, `resources-sync` |
| `r2-crypt.password`, `r2-crypt.salt`                                   | the two passwords of the rclone crypt over `~/resources`                                              | `resources-sync`                                               |
| `google.credentials`, `google.token`                                   | the downloaded OAuth client `credentials.json` · the token, written by the first run                  | `gcal`, `gmail`, `gdrive`                                      |
| `env.cloudflare_api_token`                                             | a Cloudflare API token with Zone Settings: Edit, only for `--fix`                                     | `https-check --fix`                                            |
| `openai.api_key`, `google-maps.api_key`, `duffel.api_key`              | optional, for your own scripts                                                                        | `secrets exec`                                                 |
| `posthog.<app>`                                                        | an app's PostHog project key                                                                          | apps, via `secrets env`/`exec`                                 |
| `env.<variable>`                                                       | anything else, under its variable name lowercased — where `import-env` puts what it doesn't recognise | `secrets exec`, `secrets env`                                  |

**Losing every machine key and both paper copies loses every secret** — including `r2-crypt`, without which `~/resources` in R2 cannot be decrypted. Run `secrets backup-verify` now and then to prove the paper still works.

## Setting a value

- **Typed:** `secrets set tavily.api_key` in a terminal; the prompt is hidden. Only a human types values.
- **From a file:** `secrets set google.credentials --from-file ~/Downloads/credentials.json`, then delete the file. Claude may run this after asking; the value never enters its context.
- **From a program:** `… | secrets set <name>.<field> --stdin` (what `lib/google_auth.py` does). Denied to Claude.

Each write takes a lock, commits `[<host>] secrets: set <name>.<field>` and pushes — only if origin is private. Other machines see it at their next `git pull`.

## Using secrets in a project

`secrets exec` replaces "source a dotenv file in a subshell": it decrypts the store once and runs one command with exactly the secrets you name as environment variables.

```bash
secrets exec --only STRIPE_SECRET_KEY,RESEND_API_KEY -- pnpm dev
secrets exec --only POSTHOG_KEY=posthog.myapp -- pnpm build      # NAME=<name>.<field> picks the path
secrets exec --all-env -- ./script.sh                            # every env.* secret
```

A `NAME` the wrappers already know maps to their path (`TAVILY_API_KEY` → `tavily.api_key`, `TELEGRAM_BOT_TOKEN` → `telegram.token`, `R2_ACCESS_KEY_ID` → `r2.access_key_id` …); any other is `env.<name lowercased>`. With direnv, an app's `.envrc` can say `eval "$(secrets env --only STRIPE_SECRET_KEY)"`. Deploy targets get values with the platform's own command (`wrangler secret put`, EAS, `gh secret set`) run under `secrets exec`, never pasted.

## Getting each value

- **Telegram:** message @BotFather, `/newbot`, copy the token. Send your bot any message, then open `https://api.telegram.org/bot<token>/getUpdates` in a browser and copy `message.chat.id`.
- **Cloudflare API token** (optional, for `https-check --fix`): Cloudflare dashboard → My Profile → API Tokens → Create Token → Custom, permission Zone · Zone Settings · Edit (plus Zone · Zone · Read), limited to the zones you serve sites from. `secrets set env.cloudflare_api_token`.
- **R2:** Cloudflare dashboard → R2 → create a bucket → _Manage API tokens_ → an Object Read & Write token scoped to that bucket. The endpoint is shown with the token.
- **Crypt password and salt:** two long random passwords from your password manager's generator (`openssl rand -base64 32` works too).
- **Google:** Cloud Console → new project → enable the Gmail, Calendar and Drive APIs, plus any others the scopes in `lib/google_auth.py` need (Docs, Sheets, Slides, People, Analytics, Tag Manager …) → OAuth consent screen (External; fill Branding: name, support email, a homepage and privacy-policy link on a domain you own, that domain as authorized, **no logo**; then **Publish app** to production — in Testing, Google expires the sign-in every 7 days) → Credentials → OAuth client ID → _Desktop app_ → download JSON → `secrets set google.credentials --from-file <it>`. The first `gcal list` opens a browser for consent and stores the token. The access token is refreshed in memory on each run; the token is written back only when Google issues a new refresh token.

## Rules for Claude

- Never decrypt. `sops decrypt`, `sops edit`, `sops exec-env`, `secrets env`, `age -d`, `age-keygen` and reading `~/.config/sops/` are denied in `claude-global/settings.json`; use the wrappers.
- `secrets status`, `secrets check` and `secrets recipients --check` are allowed. `secrets init`, `set --from-file`, `import-env`, `recipients`, `admit`, `revoke`, `push` and `exec` ask first — `exec` runs a command with secrets in its environment, which can send them anywhere, so it is never allowed outright.
- Never print, log, commit or message a secret or a fragment of one.
- The human types every value, makes and keeps the paper key, and does every login.

## Removing a machine

`secrets revoke <host>` on a manager that stays: it drops the host's key, re-encrypts, rotates the data key, and lists every secret that host could read. Git history still holds ciphertext the old key opens, so **rotate each listed value at its provider** (`/rotate <name>`). Until then, the removed machine's key can still read the old values.

## Migrating from a plaintext dotenv file

If your keys live in something like `~/.config/secrets.env` (`export NAME=value` lines your shell sources):

1. `secrets import-env ~/.config/secrets.env --dry-run` prints where each variable would go (`TAVILY_API_KEY → tavily.api_key`, `STRIPE_SECRET_KEY → env.stripe_secret_key`) and nothing else. Add `--map NAME=<name>.<field>` for any you want somewhere specific.
2. `secrets import-env ~/.config/secrets.env [--map …]` writes each value through `sops set --value-stdin` — never an argument, never printed — and prints names and counts, then commits once. Values already in the store are skipped unless `--overwrite`. Quoted values are unquoted (`"…"` with `\"` escapes, `'…'` literally); multi-line values aren't supported — set those with `--from-file`.
3. Replace each `source ~/.config/secrets.env` with `secrets exec --only NAME,… -- <command>` (or `secrets env` in an `.envrc`), and remove the line from `~/.zshrc`.
4. When nothing reads it any more, delete the plaintext file and rotate anything that ever left the machine in it.

Claude may run step 1, and step 2 after asking; it never sees a value either way.

## Migrating from Bitwarden (0.4 → 0.5)

There is no import tool: copy each value across by hand, which is also the moment to rotate the ones you've been meaning to. In a terminal, for each old `claude-computer/<name>` item, run `secrets set <name>.<field>` and paste the value from Bitwarden: a `password` becomes `api_key` (or `telegram.token`), the `chat_id` field `telegram.chat_id`; R2's username `r2.access_key_id`, password `r2.secret_access_key`, fields `r2.endpoint` and `r2.bucket`; `r2-crypt`'s password and `salt` fields `r2-crypt.password` and `r2-crypt.salt`; the `google-credentials` note `google.credentials` (with `--from-file` if you still have the JSON). Skip `google-token`: the first Google wrapper run asks for consent again and stores a fresh one. Then `secrets check`, and `brew uninstall bitwarden-cli`.
