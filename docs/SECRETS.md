# Secrets

**Bitwarden is the only secret store.** No keys in files, repos, the map, `rclone.conf`, shell history or messages. Scripts in `bin/` read items at run time through `bw`, using the session that `secrets-unlock` keeps in the macOS Keychain (Linux: `$XDG_RUNTIME_DIR`).

Unlock once per login session, in a terminal: `secrets-unlock` (or the `unlock` alias, which also exports `BW_SESSION` into that shell).

## Items the scripts expect

All names start with `claude-computer/` (override with `CC_BW_PREFIX`). Create each when you first need it — nothing breaks until a wrapper that uses it runs, and then it exits with code 5 and names the missing item.

| Item                                 | Type        | Fields                                                                                                                                         | Used by                                        |
| ------------------------------------ | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| `claude-computer/telegram`           | Login       | password = bot token · custom field `chat_id`                                                                                                  | `tg-send`, hooks                               |
| `claude-computer/tavily`             | Login       | password = API key                                                                                                                             | `tavily`                                       |
| `claude-computer/firecrawl`          | Login       | password = API key                                                                                                                             | `firecrawl`, `feeds-sync`                      |
| `claude-computer/jina`               | Login       | password = API key                                                                                                                             | `jina`                                         |
| `claude-computer/exa`                | Login       | password = API key                                                                                                                             | `exa`                                          |
| `claude-computer/r2`                 | Login       | username = access key ID · password = secret access key · custom fields `endpoint` (`https://<account-id>.r2.cloudflarestorage.com`), `bucket` | `archive-*`, `camera-ingest`, `resources-sync` |
| `claude-computer/r2-crypt`           | Login       | password = crypt password · custom field `salt`                                                                                                | `resources-sync`                               |
| `claude-computer/google-credentials` | Secure note | notes = the downloaded OAuth client `credentials.json`                                                                                         | `gcal`, `gmail`, `gdrive`                      |
| `claude-computer/google-token`       | Secure note | written by the first Google wrapper run                                                                                                        | `gcal`, `gmail`, `gdrive`                      |
| `claude-computer/posthog-<app>`      | Login       | password = project API key                                                                                                                     | apps, via `.envrc`                             |

**Losing `r2-crypt` means losing `~/resources` in R2.** It cannot be recovered from the bucket. Keep Bitwarden's own recovery (emergency access or an export stored offline) in order.

## Getting each value

- **Telegram:** message @BotFather, `/newbot`, copy the token. Send your bot any message, then open `https://api.telegram.org/bot<token>/getUpdates` in a browser and copy `message.chat.id`.
- **R2:** Cloudflare dashboard → R2 → create a bucket → _Manage API tokens_ → an Object Read & Write token scoped to that bucket. The endpoint is shown with the token.
- **Crypt password and salt:** generate two long random passwords in Bitwarden's generator.
- **Google:** Cloud Console → new project → enable Gmail, Calendar, Drive APIs → OAuth consent screen (External, Testing, add yourself as a test user) → Credentials → OAuth client ID → _Desktop app_ → download JSON → paste into the secure note. The first `gcal list` opens a browser for consent and stores the token.

## Rules for Claude

- Never run `bw get`, `bw list` or `bw export` directly (denied in `claude-global/settings.json`); use the wrappers.
- Never print, log, commit or message a secret or a fragment of one.
- The human does every login, every unlock, and every step where a password is typed or a key is copied.

## Migrating existing passwords

Claude walks you through it; you do every step that touches a credential. Export from the old manager (Apple Passwords: _File → Export_; Chrome: _Password Manager → Settings → Export_; 1Password: `.1pux`; others: CSV), then `bw import <format> <file>`. Claude runs the import command and confirms the item count but never reads the file, then securely deletes the export. Afterwards: install the Bitwarden browser extension and turn off password saving in Chrome and Apple Passwords, so there is one store.

No cloud at all? KeePassXC + Syncthing works; the wrappers would need `keepassxc-cli` in place of `bw`.
