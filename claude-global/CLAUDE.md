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
- **Secrets live in `~/claude-computer/secrets/secrets.yaml`, sops-encrypted, nowhere else.** Never decrypt it (`sops decrypt`, `secrets env`) and never read `~/.config/sops/`; the wrappers decrypt what they need. Never write a secret into a file, a commit, a note or a message. A project gets its secrets with `secrets exec --only NAME,… -- <cmd>`, after asking me.
- **After any change to a machine** (install, service, port, launchd job, key), update its file in `~/claude-computer/docs/machines/` in the same session.
- **Record decisions** in `~/claude-computer/docs/DECISIONS.md` (system) or the project's `DECISIONS.md`: `- [<host>] [YYYY-MM-DD] <decision> — <why>`.
- **Tasks** live in the `TASKS.md` of the brain they belong to (`## Now / ## Next / ## Later / ## Done`). When I say "later" or "defer", write it under `## Later` and move on.
- **Scripts over prose.** If something is deterministic, make it a script in `~/claude-computer/bin/`. Slash commands call scripts; they don't reimplement them.
- Conventional commits, small and single-purpose.
- **Project docs follow the documentation standard** (`~/claude-computer/docs/DEV-GUIDELINES.md`, "Documentation"): Markdown with front matter in `docs/`, rebuilt with `docs-build` after every change, never a hand-edited `index.html`. Read a project's `docs/llms.txt` before its Markdown. This repo's docs as one page: `~/claude-computer/.docs-view/index.html`.

## Tools on the PATH

Everything in `~/claude-computer/bin/` is on the PATH and answers `--help`. Prefer these over MCP servers and over ad-hoc `curl`: they decrypt their keys from the secrets store and cost no context until used. Research: `tavily "q"` (web search), `exa "q"` (semantic search), `firecrawl <url>` (page → markdown), `jina <url>` / `jina --search "q"`, `browse <url>` (headless Chromium via Playwright, for JavaScript-rendered or logged-in pages: `--md` default, `--screenshot`, `--pdf`, `--profile <name>`; never `chrome --headless`). Google: `gcal list|add`, `gmail search|get`, `gdrive search|download|upload|share`. System: `map-check`, `security-check`, `tasks-sync`, `secrets status|check`, `wt <branch>`. Storage: `archive-push`, `archive-pull --search`, `camera-ingest`, `resources-sync`. Projects: `new-app <type> <name>`, `docs-build [--check|--init|--view]`, `new-client <name>` (each client is a private repo in `~/clients`). Feeds: `feeds-sync`. Voice: `transcripts-sync` (MacParakeet → `~/vault/inbox/transcripts/`). Notify: `tg-send "text"`. If one fails with exit code 4, this machine has no age key or isn't admitted; exit code 5, the secret isn't set — tell me the command `secrets status` suggests, which I run.

**Agent Reach** covers the platforms the wrappers don't: YouTube (`yt-dlp`), GitHub (`gh`), RSS, and any channel I have added myself (X, Reddit, LinkedIn…). Its skill routes to the upstream tool; `agent-reach doctor` shows which channels work. For plain web search and page-to-markdown, the `bin/` wrappers above come first. Adding a channel that needs a cookie, a key or a logged-in browser is my step: I run `agent-reach configure <key>` in a terminal with no value after it, so it prompts with the input hidden; a value typed on the command line lands in shell history. Never ask me to paste a cookie into the conversation, and never read `~/.agent-reach/config.yaml`.

## Searching

- **Text: `rg`, never recursive `grep`.** `rg` skips hidden files and reads `.gitignore` and `.ignore`; `grep -r` does neither the same way, so the two return different files for the same question. Files by name: `rg --files -g '<glob>'` or `fd`. Always give `rg` a path (`rg pattern .`): with none, and a stdin that isn't a terminal, it searches stdin and waits forever.
- **Code by structure: `ast-grep`.** When the question is about syntax — every call to a function, every use of a decorator — `ast-grep run -p 'subprocess.run($$$ARGS)' -l python <path>` matches real calls and skips comments and strings, which `rg` cannot tell apart. It chooses files by extension, so extensionless scripts (everything in `~/claude-computer/bin/`) need `rg`.
- **Narrow before you read.** `rg -l` or `rg -c` first to see where the matches are, then search or read those files. Add `-t <type>` or `-g '<glob>'` whenever you know the kind of file.
- **Long lines are cut at 200 bytes** by `~/.config/ripgrep/ripgreprc`, so a minified bundle can't flood the context. When you need the whole line, or you are piping `rg` into something that parses it, add `--no-config`.

## Keeping output small

Everything a command prints stays in the context for the rest of the session. Ask for the summary first and the detail only where it matters.

- **Git:** `git status -sb`; `git diff --stat` or `--name-status` before a full diff; `git log --oneline`.
- **JSON and YAML:** select fields with `jq -c` or `yq`; never print a whole file to find one value.
- **GitHub:** `gh … --json <fields> --jq '<filter>'`, not the default tables.
- Pagers and colour are already off in your shell (`PAGER=cat`, `NO_COLOR=1`, from `settings.json`).

## Voice and transcripts

- **Files, URLs and podcasts** go straight into the vault: `macparakeet-cli transcribe <input> --no-history --output-dir ~/vault/inbox/transcripts --format transcript` (`--podcast "<show> <episode>"` for podcast search). `--no-history` keeps them out of MacParakeet's database, so `transcripts-sync` never exports them twice.
- **Meetings** recorded in the MacParakeet app arrive on their own: `transcripts-sync` exports each completed one to `~/vault/inbox/transcripts/`. Process them with `/transcripts`.
- **Short dictation** goes straight into `~/vault/inbox/quick.md` — no script.

## Parallel sessions

One Claude session per git worktree; never two sessions in the same working tree. For parallel work on a repo, create a worktree with `wt <branch>` and run the other session there.

## Telling me things

When you finish something that took a while, or you are blocked waiting on me, send one line with `tg-send "<what>"`. The hooks already do this for long turns and permission prompts; use it yourself for milestones inside a long task. Plain text, no secrets, no file contents.
