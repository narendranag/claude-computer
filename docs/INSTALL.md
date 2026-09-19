# Installing

One command, on a Mac you have just opened:

```bash
/bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)"
```

It puts the operator on the machine — Xcode's Command Line Tools, Homebrew, the GitHub CLI, Claude Code — creates your own private copy of this template, and then stops and tells you the three things only a human can do. It checks what is already there and skips it, so it is safe to run on a machine that is half set up, and safe to run again after one that failed.

## Read it before you run it

You should. It is a shell script from the internet, and the whole premise of this repo is that you stay the one who decides.

```bash
curl -fsSL https://claude-computer.com/install.sh | less
```

That URL redirects to [`install.sh`](../install.sh) on `main` in this repo, so there is one source of truth and no separately hosted copy to drift or be tampered with independently. You can fetch it from either address:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/narendranag/claude-computer/main/install.sh)"
```

And you can see exactly what it would do, changing nothing:

```bash
/bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)" -- --dry-run
```

### Why `bash -c "$(curl …)"` and not `curl … | bash`

The pipe form would put the download on standard input, and standard input is where the Homebrew installer reads your password and where `gh auth login` reads your answers. With the script on stdin, both of them hang or fail. The `bash -c "$(…)"` form keeps your terminal attached.

The script checks for this: a real run with no terminal on stdin prints the right form and exits 2 rather than starting something it cannot finish. `--dry-run`, `--help` and `--version` change nothing, so those do work down a pipe — `curl -fsSL https://claude-computer.com/install.sh | bash -s -- --dry-run` is fine, and it says so once. Down a pipe a dry run asks nothing at all; with a terminal it asks the one question below, which changes nothing either.

## One repo for the whole fleet

**Use the same name on every machine.** With no flags the installer asks you one question:

```text
  What should your private repo be called? It is ONE repo for every machine you own: use the same name on each.
  Repo name [claude-computer]:
```

`--name` is the name of that GitHub repo, and the design is one private repo shared by the whole fleet. Every machine clones that same repo. That is what lets the laptop see and fix the Mini, keeps one `docs/FLEET.md`, and keeps one append-only `docs/DECISIONS.md`. Answer `mini-admin` on the Mini and `air-admin` on the Air and you get two separate brains that know nothing about each other — the "each machine keeps its own map" setup the [README](../README.md#what-id-tell-my-past-self) says fell apart.

The default, `claude-computer`, is right for almost everyone: a private `<you>/claude-computer` cloned to `~/claude-computer`. You need another name in two cases — you want one, `sys-admin` say, or `<you>/claude-computer` is taken by something that is not your instance. The common version of the second is a **contributor who forked this template**: your fork is `<you>/claude-computer`, it is public, and a map of your machines must never go there. The installer checks and will not use it.

### How it plays out

**First machine.** Run the one-liner, answer the question, and it creates the private repo from the template:

```bash
/bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)"
```

Scripted, or if you would rather not be asked — and this is the form to use on every machine after the first:

```bash
/bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)" -- --name sys-admin --dir ~/claude-computer
```

**Every later machine.** The same command, the same answer. The installer sees that the private repo already exists and takes the second-machine path: it clones the repo instead of creating one, and says so.

```text
  → octocat/sys-admin already exists on GitHub — cloning it instead of creating it (this is the second-machine path)
  ✓ it is private and not a template — an instance, as expected
  same repo on every machine: this one will appear as docs/machines/mini.md
```

`/setup` then asks only what is specific to that machine. It does not offer to initialise a fresh instance: `.template` was deleted on the first machine, so a clone does not have it.

### Where per-machine identity comes from

**The hostname. The repo name plays no part.** [`CLAUDE.md`](../CLAUDE.md) has Claude run `scutil --get LocalHostName`, read or write `docs/machines/<host>.md`, and tag its commits `[<host>]`.

So if you want machines to show up as `mini` and `air`, set those as the hostnames — the fleet files become `docs/machines/mini.md` and `docs/machines/air.md`. The unambiguous route is one command per machine, and it is yours to run because it needs `sudo`:

```bash
sudo scutil --set LocalHostName mini
```

The same name in the GUI lives in System Settings, under Sharing, as the local hostname; the exact wording moves between macOS releases, and the command above is the same thing without the hunt. Do it before `/setup`, or you will have a `docs/machines/Someones-MacBook-Pro.md` to rename. The installer says which file this machine will be, and warns when the hostname is one macOS made up.

A name like `fleet` or `sys-admin` for the one shared repo fits this better than a per-machine name does.

### Keep the directory the same everywhere too

A different `--dir` per machine is possible and is a bad idea. The hooks in `claude-global/hooks/` default to `~/claude-computer` through `CC_HOME`, every permission rule in [`claude-global/settings.json`](../claude-global/settings.json) is written against `~/claude-computer/bin/…`, and `/setup` stops if `pwd` is anything else. A different path on one machine means rules that never match — and an _ask_ rule that does not match fails open, so the prompt you meant to get does not arrive — plus a `CC_HOME` you have to remember to export.

The repo name does not move the directory: `--name sys-admin` alone still clones to `~/claude-computer`. Only an explicit `--dir` changes it.

### If you get it wrong

**Two repos, one per machine.** Pick the one to keep. Move the other's `docs/machines/<host>.md` across, add its row to `docs/FLEET.md` and its lines to `docs/DECISIONS.md`, then on that machine point the clone at the keeper and pull:

```bash
cd ~/claude-computer
git remote set-url origin git@github.com:<you>/sys-admin.git
git fetch origin && git reset --hard origin/main
```

The reset discards that clone's own history, which is why the machine file moves across first — the two repos are separate template copies and share no commits. Then archive or delete the repo you dropped (`gh repo archive <you>/air-admin`), so nobody clones it by accident later.

**The clone is in the wrong directory.** Move it and re-link, rather than setting `CC_HOME` — the environment variable fixes the hooks and nothing else, and the permission rules and `/setup` still expect the path:

```bash
mv ~/sys-admin ~/claude-computer
```

Then relink `~/.claude` — `CLAUDE.md`, `settings.json`, `commands` and `hooks` all point into the old path — which is phase 4 of `/setup`; ask Claude to redo it. Check `map-check` runs afterwards.

## What it does, in order

Before it changes anything it prints a checklist — `✓` what you have, `→` what it will install, `!` what needs you — and asks once whether to go ahead.

**The question.** With no `--name` and a terminal, it asks what your private repo should be called before anything else, and prints `repo: <you>/<name> · directory: ~/claude-computer` so the two are never confused. `--yes`, `--name` and a run with no terminal skip it. See [One repo for the whole fleet](#one-repo-for-the-whole-fleet).

**Preflight.** macOS only (a Linux box exits 3: headless machines are managed from a Mac over SSH, never set up this way). macOS version and chip — the MacParakeet dictation and transcript pipeline is Apple silicon only, and the Brewfile skips it on Intel. Whether `github.com` is reachable, whether there is enough disk, and whether you are an administrator, because Homebrew needs one. Then the state of each component, and the URLs it will fetch.

| Step                      | What happens                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **1. Command Line Tools** | `xcode-select --install` opens a macOS dialog — you click **Install**. The script then waits up to 30 minutes, polling until the developer directory `xcode-select -p` names actually holds a `git` and a `clang`, and those two run. It checks the directory rather than just asking `xcode-select`, because a stale developer path after an OS upgrade leaves `xcode-select -p` answering while the tools underneath are gone — and because running `/usr/bin/git` before the tools exist pops the install dialog by itself.                                                                                                                                           |
| **2. Homebrew**           | Runs Homebrew's own installer, interactively, exactly as Homebrew documents it. **It asks for your password** — that is Homebrew, not this script, and it prints everything it is about to do first. Afterwards the script makes `brew` work in its own process, and appends the one `eval "$(… shellenv)"` line Homebrew asks for to `~/.zprofile` if it is not there already, telling you exactly what it appended.                                                                                                                                                                                                                                                    |
| **3. GitHub CLI**         | `brew install gh`. If you are not logged in, `gh auth login` runs and **you** answer it — take the defaults, GitHub.com over HTTPS, authenticate in a browser. This template creates a per-machine SSH key of its own later, during `/setup`; you do not need one now.                                                                                                                                                                                                                                                                                                                                                                                                   |
| **4. Claude Code**        | `brew install --cask claude-code`, unless a Claude Code is already there. It looks for `claude` on `PATH`, the cask, and the native installer at `~/.local/bin/claude` or `~/.claude/local` — if it finds any of them it leaves them alone rather than installing a second copy.                                                                                                                                                                                                                                                                                                                                                                                         |
| **5. Your private copy**  | `gh repo create claude-computer --template narendranag/claude-computer --private`, then confirms the new repo really is private and clones it to `~/claude-computer`. GitHub finishes copying the template asynchronously, so the script polls the clone for up to 60 seconds until the files arrive. It then verifies `CLAUDE.md` and `docs/FIRST-PROMPT.md` are in it — plus `.template` when the copy came straight from the template, which a second machine's clone will not have, because `/setup` deletes it. Finally `git config core.hooksPath .githooks`, which arms the gitleaks pre-commit scan. The `upstream` remote is `/setup`'s job, not this script's. |
| **6. Hand over**          | Prints the three remaining steps and copies the first prompt to your clipboard, read out of the clone's own `docs/FIRST-PROMPT.md` so it cannot drift from the file in the repo.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |

Then you do the rest:

```bash
cd ~/claude-computer && claude
```

Log in to Claude Code. Check the status line reads **⏵⏵ auto mode on** — Shift+Tab cycles the modes, and never _bypass permissions_. Paste the first prompt (⌘V; it is already on your clipboard) and let it go.

The script does not start Claude Code for you and passes no permission-mode flag. Choosing the mode is one of the three jobs that stay yours.

## Flags

| Flag             | What it does                                                                                                                                                                                                                             |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--dry-run`      | Print every command it would run. Changes nothing and writes nothing. It asks only for the repo name, and only with a terminal and no `--name`.                                                                                          |
| `--yes`          | Do not pause for confirmation, and do not ask for the repo name.                                                                                                                                                                         |
| `--dir <path>`   | Where the clone goes. Default `$HOME/claude-computer` whatever `--name` says, because the hooks, the permission rules and `/setup` assume that path.                                                                                     |
| `--name <repo>`  | The name of your private GitHub repo. Default `claude-computer`, and it is what the question asks for. One repo for the whole fleet: the same name on every machine — see [One repo for the whole fleet](#one-repo-for-the-whole-fleet). |
| `--public-clone` | Do not create a repo of your own: clone the template read-only, to look at it first.                                                                                                                                                     |
| `--help`         | The usage text.                                                                                                                                                                                                                          |
| `--version`      | The version, then exit.                                                                                                                                                                                                                  |

Flags go after a `--`, because of how `bash -c` assigns arguments — the first word after the script becomes `$0`, so the flags need a placeholder in front of them:

```bash
/bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)" -- --dry-run --dir ~/work/cc
```

From a local checkout it is just `./install.sh --dry-run`.

`CC_INSTALL_TEMPLATE` overrides the template slug, for a fork:

```bash
CC_INSTALL_TEMPLATE=you/your-fork /bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)"
```

`NO_COLOR` turns colour off; colour is on only when the output is a terminal anyway.

> [!NOTE]
> The script also reads a set of `CC_INSTALL_TEST_*` variables. Those are for `tests/install-dry-run.sh`, which uses them to simulate a machine without weakening any real check. Do not set them by hand.

## Exit codes

| Code | Meaning                                                                                                                                            |
| ---- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| 0    | Done, or you answered no at the prompt.                                                                                                            |
| 1    | A step failed. The message says which; re-running is safe.                                                                                         |
| 2    | Bad arguments, a real run with no terminal on stdin, or no usable repo name after three tries.                                                     |
| 3    | Not macOS.                                                                                                                                         |
| 4    | Something that is not a `claude-computer` clone is already at the target directory.                                                                |
| 5    | The Command Line Tools installer did not finish within 30 minutes.                                                                                 |
| 6    | The repo of that name is not a private instance: it is the template, a template repo, or public. An interactive run asks for another name instead. |

## The equivalent by hand

The script exists to save you these, not to hide them. This is the same install, and it is the by-hand path the README keeps in [The build](../README.md#the-build):

```bash
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install gh && gh auth login
brew install --cask claude-code
cd ~ && gh repo create claude-computer --template narendranag/claude-computer --private --clone
cd ~/claude-computer && git config core.hooksPath .githooks && claude
```

On a second machine, replace the `gh repo create` line with a clone of the repo the first machine made — the same repo, at the same path:

```bash
gh repo clone <you>/sys-admin ~/claude-computer
```

Two differences worth knowing. The Homebrew installer finishes by printing two `eval "$(… shellenv)"` lines — **run them**, or `brew` is not on your `PATH` and the third command fails with `command not found`. And `gh repo create --clone` clones into `./<name>` in whatever directory you are in; the script runs `gh repo create` and `gh repo clone` separately so that `--dir` can point anywhere.

## What it never does

- **Never reads, writes or asks for a credential.** Every login is yours. There is no token, no password and no key anywhere in it.
- **Never runs `sudo` itself.** Homebrew's installer does, for its own directories, and shows you what it will do before it does it.
- **Never touches `~/.claude`.** It reads two paths there to avoid installing a second Claude Code, and writes nothing.
- **Never edits a shell profile** except to append the single `brew shellenv` line to `~/.zprofile`, and only if no `brew shellenv` line is there. It tells you the exact line.
- **Never downloads anything** but the official Homebrew installer from `raw.githubusercontent.com/Homebrew/install`, your copy of this template from GitHub, and whatever `brew` and `gh` fetch for `gh` and the Claude Code cask. The preflight prints those URLs.
- **Never phones home.** No telemetry, no analytics, no ping.
- **Never starts Claude Code, and never sets a permission mode.**

## Troubleshooting

**The Command Line Tools dialog never appeared.** It sometimes opens behind the frontmost window — check Mission Control and the Dock. If `xcode-select --install` said "already installed" but `git --version` fails, the developer path is stale, which is common after a macOS upgrade: `sudo rm -rf /Library/Developer/CommandLineTools` and run the installer again. If the 30-minute wait times out (exit 5), the download is slow rather than stuck — let the dialog finish, then re-run the one-liner; it will see the tools and move on.

**A dialog offering to install developer tools appeared out of nowhere.** It should not, and if it does during the preflight or a `--dry-run`, that is a bug worth reporting. On a Mac without the Command Line Tools, `/usr/bin/git`, `/usr/bin/clang` and `/usr/bin/python3` are not those programs — they are one small shim that pops that dialog the moment it is _run_. So the script decides whether the tools are present by looking at the developer directory on disk, and executes `git` or `clang` only once the real binaries are there. Nothing before step 1 runs one, including the git-identity check, which is why the preflight says "checked once the Command Line Tools are in" on a fresh machine.

**It sat at "waiting for GitHub to finish copying the template…".** `gh repo create --template` returns before GitHub has finished populating the new repo, so a clone made immediately afterwards can come back empty. The script polls for up to 60 seconds and fetches again until `CLAUDE.md` appears. If it gives up (exit 1) nothing is broken: the repo exists now, so running the one-liner again takes the "already exists → clone" path and finishes off the half-filled clone it left behind.

**`brew: command not found` after Homebrew installed.** Homebrew does not put itself on your `PATH`; the two lines it prints at the end do. The script appends one of them to `~/.zprofile`, but that only takes effect in a _new_ shell. Open a new terminal tab, or run `eval "$(/opt/homebrew/bin/brew shellenv)"` (Intel: `/usr/local/bin/brew`) in this one. This is why the script probes both prefixes by path rather than trusting `PATH`.

**`gh auth login` in a session with no browser** — over SSH, or in a terminal on a machine with no GUI. Choose "Login with a web browser" anyway and open the URL and code it prints on any other device; or generate a personal access token on github.com and paste it. If the script cannot get you logged in, it stops with exit 1 and everything before it stays done, so re-running picks up from there.

**The repo name is already taken.** If `claude-computer` already exists on your account _and is a private repo that is not a template_, the script clones it instead of creating a second one, and says so — that is the documented second-machine path, and it is what you want on machine two. A private fork of the template counts and is allowed. If the name belongs to something unrelated, answer the question with another name, or pass it:

```bash
/bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)" -- --name sys-admin --dir ~/claude-computer
```

Whatever you pick, use the same name on every machine you own, and leave the directory at `~/claude-computer`.

**"…is a template repository, not an instance" / "…is public" (exit 6).** A repo of the right _name_ is not automatically your instance. If you are the template's owner, `claude-computer` on your account **is** the template. If you have forked the template to contribute, `<you>/claude-computer` is a public fork of it. In both cases cloning it as your fleet brain would mean pushing a map of your machines — hostnames, ports, what is installed and listening — to a repo the world can read, so the script stops before touching anything. An interactive run does not stop: it says why and asks for another name. Otherwise give your instance a different name yourself — the same one on every machine:

```bash
/bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)" -- --name sys-admin --dir ~/claude-computer
```

or, if that repo really is meant to be your instance, make it private first with `gh repo edit <owner>/<name> --visibility private` and run the one-liner again. A **private** fork of the template is fine and is used as-is. If you already have a clone on disk whose origin is public, the script warns rather than stopping — but fix the origin before `/setup` pushes anything.

**Something is already at `~/claude-computer`.** If it is a clone of your instance the script leaves it alone. If it is anything else it stops with exit 4 rather than writing into it — move it aside, or use `--dir`.

**You are not an administrator.** The preflight says so and Homebrew's installer will refuse. Log in as an admin user, or have one run the Homebrew step.

## For the maintainer

`https://claude-computer.com/install.sh` should be a redirect to `https://raw.githubusercontent.com/narendranag/claude-computer/main/install.sh`, not a copy. One source of truth: the file reviewed in this repo is the file people run, and a change to it ships without a second deploy. The script behaves identically fetched from either URL.
