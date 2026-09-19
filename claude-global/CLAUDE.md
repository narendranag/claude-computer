# Global instructions

Linked into `~/.claude/` from `~/claude-computer/claude-global/`. Edit it there, never in `~/.claude`.

**Global = who I am and how I work. Per-folder = what to do here.** Anything specific to a project goes in that project's `CLAUDE.md`.

## Who I am

- Name: {{user_name}}
- GitHub: {{github_user}}
- I work in Python and TypeScript. How I build: `~/claude-computer/docs/DEV-GUIDELINES.md`.
- My machines, their roles and how to reach them: `~/claude-computer/docs/FLEET.md`. This machine's state: `~/claude-computer/docs/machines/<host>.md`.

## How you work with me

- Start where the work is. A project's `CLAUDE.md` says what to do there; `~/claude-computer/docs/` says what the system looks like.
- **Ask before** anything destructive (deleting, overwriting, force-pushing, `rclone sync`, `--resync`), anything that touches credentials, and anything that costs money. I do every login and every step that handles a password myself.
- **Secrets live in Bitwarden, nowhere else.** Never write a secret into a file, a commit, a note or a message. Never run `bw get` directly; use the wrappers.
- **After any change to a machine** (install, service, port, launchd job, key), update its file in `~/claude-computer/docs/machines/` in the same session.
- **Record decisions** in `~/claude-computer/docs/DECISIONS.md` (system) or the project's `DECISIONS.md`: `- [<host>] [YYYY-MM-DD] <decision> — <why>`.
- **Tasks** live in the `TASKS.md` of the brain they belong to (`## Now / ## Next / ## Later / ## Done`). When I say "later" or "defer", write it under `## Later` and move on.
- **Scripts over prose.** If something is deterministic, make it a script in `~/claude-computer/bin/`. Slash commands call scripts; they don't reimplement them.
- Conventional commits, small and single-purpose.

## Tools on the PATH

Everything in `~/claude-computer/bin/` is on the PATH and answers `--help`. Prefer these over MCP servers and over ad-hoc `curl`: they read keys from Bitwarden and cost no context until used. Research: `tavily "q"` (web search), `exa "q"` (semantic search), `firecrawl <url>` (page → markdown), `jina <url>` / `jina --search "q"`, `browse <url>` (headless Chromium via Playwright, for JavaScript-rendered or logged-in pages: `--md` default, `--screenshot`, `--pdf`, `--profile <name>`; never `chrome --headless`). Google: `gcal list|add`, `gmail search|get`, `gdrive search|download|upload|share`. System: `map-check`, `security-check`, `tasks-sync`, `secrets-unlock --status`, `wt <branch>`. Storage: `archive-push`, `archive-pull --search`, `camera-ingest`, `resources-sync`. Projects: `new-app <type> <name>`. Feeds: `feeds-sync`. Voice: `transcripts-sync` (MacParakeet → `~/vault/inbox/transcripts/`). Notify: `tg-send "text"`. If one fails with exit code 4, Bitwarden is locked: ask me to run `secrets-unlock` in a terminal.

## Voice and transcripts

- **Files, URLs and podcasts** go straight into the vault: `macparakeet-cli transcribe <input> --no-history --output-dir ~/vault/inbox/transcripts --format transcript` (`--podcast "<show> <episode>"` for podcast search). `--no-history` keeps them out of MacParakeet's database, so `transcripts-sync` never exports them twice.
- **Meetings** recorded in the MacParakeet app arrive on their own: `transcripts-sync` exports each completed one to `~/vault/inbox/transcripts/`. Process them with `/transcripts`.
- **Short dictation** goes straight into `~/vault/inbox/quick.md` — no script.

## Parallel sessions

One Claude session per git worktree; never two sessions in the same working tree. For parallel work on a repo, create a worktree with `wt <branch>` and run the other session there.

## Telling me things

When you finish something that took a while, or you are blocked waiting on me, send one line with `tg-send "<what>"`. The hooks already do this for long turns and permission prompts; use it yourself for milestones inside a long task. Plain text, no secrets, no file contents.
