#!/usr/bin/env bash
# install.sh — put the operator on a new Mac, then hand it the machine.
#
# This is the one-liner behind https://claude-computer.com/install.sh. It does by hand what
# the README's four commands do, checking what is already there and skipping it. It is safe
# to re-run: every step is idempotent and every step announces itself before it acts.
#
# It cannot read its own source (it is usually piped in from curl), so the --help text lives
# in usage() below rather than in this comment block. Keep the two in step.
#
# What it never does: read, write or ask for a credential; run sudo itself; touch ~/.claude;
# edit any shell profile but the single `brew shellenv` line; download anything but the
# official Homebrew installer and whatever brew and gh fetch; phone home.
#
# Exit codes: 0 ok · 1 a step failed · 2 usage, no terminal, or no usable repo name after
# three tries · 3 not macOS · 4 something is already at the target directory · 5 the Command
# Line Tools installer never finished · 6 the repo of that name is not a private instance
# (the template itself, or a public fork).
set -euo pipefail

VERSION="0.3.2"
TEMPLATE="${CC_INSTALL_TEMPLATE:-narendranag/claude-computer}"
BREW_INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"

usage() {
  cat <<'EOF'
install.sh — put the operator on a new Mac: Xcode Command Line Tools, Homebrew, the GitHub
CLI, Claude Code, and your own private copy of the claude-computer template. Then it tells
you the three things left for a human to do.

Usage:
  /bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)"
  /bin/bash -c "$(curl -fsSL https://claude-computer.com/install.sh)" -- --dry-run

  The `--` matters. In `bash -c <script> <name> <args…>` the first word after the script
  becomes $0, so flags need a placeholder in front of them. Run from a local checkout it is
  just `./install.sh --dry-run`.

With no flags it asks you one question — what your private repo should be called —
and then does the rest. Every machine you own uses the same answer.

Flags:
  --dry-run        print every command it would run; change nothing on the machine. It asks
                   only for the repo name, and only with a terminal and no --name
  --yes            do not pause for confirmation, and do not ask for the repo name
  --dir <path>     where the clone goes. Default $HOME/claude-computer whatever --name says,
                   because the hooks, the permission rules and /setup all assume that path
  --name <repo>    the name of your private GitHub repo (default: claude-computer). ONE repo
                   is shared by the whole fleet — pass the same name on every machine
  --public-clone   do not create a private copy; clone the template read-only, to look first
  --help           this text
  --version        print the version and exit

Environment:
  CC_INSTALL_TEMPLATE   template slug to copy from (default: narendranag/claude-computer).
                        Set it if you are installing from a fork.
  NO_COLOR              set to anything to turn colour off.

A real run needs a terminal on stdin, which is why the command above is
`bash -c "$(curl …)"` and not `curl … | bash`: the Homebrew installer's sudo prompt and
`gh auth login` both read from the terminal, and a pipe takes it away. `--help` and
`--version` change nothing and ask nothing. `--dry-run` changes nothing either, and down a
pipe it asks nothing — with a terminal it asks the repo-name question, which changes nothing.

One repo, every machine. The repo name is not how a machine is identified: that is the
hostname, `scutil --get LocalHostName`, which becomes docs/machines/<host>.md inside the one
shared repo. Run this on a second machine with the same --name and it clones that repo
rather than creating a second one.

A repo of the right name is not automatically your instance: on the template owner's account
it IS the template, and on a contributor's it is most likely a public fork. Before cloning
an existing repo as your fleet brain, this checks that it is private and not a template. An
interactive run asks for another name; otherwise it stops with exit 6 — your instance holds
a map of your machines.

Exit codes: 0 ok · 1 a step failed · 2 usage, a real run with no terminal, or no usable repo
name after three tries · 3 not macOS · 4 something is already at the target directory · 5 the
Command Line Tools installer never finished · 6 the repo of that name is not a private
instance.
EOF
}

# ---------------------------------------------------------------------------
# Test-only overrides. These exist so tests/install-dry-run.sh can simulate a machine
# without weakening any real check: unset (the default on a real Mac) every probe below
# behaves exactly as written. Do not set them by hand.
#   CC_INSTALL_TEST_TTY             1 = pretend stdin is a terminal
#   CC_INSTALL_TEST_UNAME_S         value of `uname -s`
#   CC_INSTALL_TEST_ARCH            value of `uname -m`
#   CC_INSTALL_TEST_OS_VERSION      value of `sw_vers -productVersion`
#   CC_INSTALL_TEST_BREW_PREFIXES   colon-separated brew paths to probe
#   CC_INSTALL_TEST_CLAUDE_NATIVE   colon-separated native-install paths to probe
#   CC_INSTALL_TEST_ZPROFILE        path to use instead of ~/.zprofile
#   CC_INSTALL_TEST_ADMIN           yes | no
#   CC_INSTALL_TEST_DISK_KB         free KB to report instead of asking df
#   CC_INSTALL_TEST_SKIP_NET        1 = skip the reachability probe
#   CC_INSTALL_TEST_HOSTNAME        value of `scutil --get LocalHostName`
# ---------------------------------------------------------------------------

# ---- output ---------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_D=$'\033[2m'; C_0=$'\033[0m'
else
  C_B=""; C_G=""; C_Y=""; C_R=""; C_D=""; C_0=""
fi

say()  { printf '%s\n' "$*"; }
info() { printf '%s%s%s\n' "$C_D" "$*" "$C_0"; }
warn() { printf '%s! %s%s\n' "$C_Y" "$*" "$C_0" >&2; }
err()  { printf '%sinstall.sh: %s%s\n' "$C_R" "$*" "$C_0" >&2; }
die()  { code="$1"; shift; err "$*"; exit "$code"; }
head2() { printf '\n%s%s%s\n' "$C_B" "$*" "$C_0"; }

have()      { printf '  %s✓%s %s\n' "$C_G" "$C_0" "$*"; }
will()      { printf '  %s→%s %s\n' "$C_B" "$C_0" "$*"; }
needs_you() { printf '  %s!%s %s\n' "$C_Y" "$C_0" "$*"; }

# ---- flags ----------------------------------------------------------------
DRY=0
ASSUME_YES=0
PUBLIC_CLONE=0
NAME="claude-computer"
NAME_GIVEN=0
DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)      DRY=1; shift ;;
    --yes|-y)       ASSUME_YES=1; shift ;;
    --public-clone) PUBLIC_CLONE=1; shift ;;
    --dir)          [ $# -ge 2 ] || die 2 "--dir needs a path"; DIR="$2"; shift 2 ;;
    --name)         [ $# -ge 2 ] || die 2 "--name needs a repo name"; NAME="$2"; NAME_GIVEN=1; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    --version)      say "install.sh $VERSION"; exit 0 ;;
    --)             shift ;;
    *)              usage >&2; die 2 "unknown argument: $1" ;;
  esac
done

# The directory is load-bearing in a way the repo name is not. The hooks fall back to
# ~/claude-computer through CC_HOME, every rule in claude-global/settings.json is written
# against ~/claude-computer/bin/…, and /setup refuses to run anywhere else. So --name moves
# the repo on GitHub and nothing on disk: the default destination is ~/claude-computer
# whatever the repo is called, and only an explicit --dir changes it.
[ -n "$DIR" ] || DIR="$HOME/claude-computer"
case "$DIR" in /*) ;; *) DIR="$PWD/$DIR" ;; esac
PARENT="$(dirname "$DIR")"
DISPLAY_DIR="$DIR"
case "$DIR" in "$HOME"/*) DISPLAY_DIR="~${DIR#"$HOME"}" ;; esac

# ---- traps ----------------------------------------------------------------
STEP="starting up"

# shellcheck disable=SC2317,SC2329  # invoked by the ERR trap below, not by name (older shellcheck: SC2317)
on_err() {
  err "failed during: $STEP"
  err "nothing is half-installed that a re-run cannot finish — run the same command again."
}
trap on_err ERR

# ---- the run idiom --------------------------------------------------------
# Same shape as setup-tools.sh: in --dry-run every command is printed and none is run.
# For the handful of things that are a shell line, not an argv: print it in dry-run,
# and let the caller run the real thing in its own branch.
show() { printf '    %s%s%s\n' "$C_D" "$*" "$C_0"; }

run() {
  if [ "$DRY" -eq 1 ]; then
    printf '    %s%s%s\n' "$C_D" "$*" "$C_0"
  else
    "$@"
  fi
}

confirm() {
  local reply
  if [ "$DRY" -eq 1 ] || [ "$ASSUME_YES" -eq 1 ]; then return 0; fi
  printf '%s [y/N] ' "$1"
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

is_tty() {
  if [ "${CC_INSTALL_TEST_TTY:-0}" = "1" ]; then return 0; fi
  [ -t 0 ]
}

# ---- terminal gate --------------------------------------------------------
# `curl … | bash` puts the download on stdin. The Homebrew installer's sudo prompt and
# `gh auth login` both need the terminal there instead, so refuse rather than hang.
#
# A dry run changes nothing and asks nothing, so it has no use for a terminal: let it
# through, including down a pipe, and say once that the real thing needs one.
if ! is_tty; then
  if [ "$DRY" -eq 1 ]; then
    say "(No terminal on stdin. Fine for --dry-run; a real run needs one — see --help.)"
  else
    err "no terminal on stdin."
    say "Run it this way instead, so the installers can ask you for a password:"
    say ""
    say "  /bin/bash -c \"\$(curl -fsSL https://claude-computer.com/install.sh)\""
    say ""
    say "Not: curl … | bash — the pipe takes the terminal away."
    exit 2
  fi
fi

# ---- the repo -------------------------------------------------------------
# One private repo, shared by the whole fleet. --name is that repo's name on GitHub and
# nothing else: a machine is identified inside the repo by its hostname, so every machine
# passes — or answers with — the same name, and the laptop can see and fix the Mini.

GH_ACCOUNT=""

# Always owner-qualified once the account is known: a bare `gh repo view <name>` run from
# inside some other git repo can resolve against that repo's remote rather than the account.
REPO_SLUG="$NAME"
set_repo_slug() {
  if [ -n "$GH_ACCOUNT" ]; then REPO_SLUG="$GH_ACCOUNT/$NAME"; else REPO_SLUG="$NAME"; fi
}
gh_repo_exists() {
  set_repo_slug
  gh repo view "$REPO_SLUG" >/dev/null 2>&1
}

# A repo of the right *name* is not necessarily an instance. On the template owner's account
# `claude-computer` IS the template; on a contributor's it is most likely a public fork of
# it. Cloning either as your fleet brain would put a map of your machines — hostnames, ports,
# what is installed and listening — into a public repo. So the name is not enough: ask what
# the repo actually is.
#
# `gh --jq` is gh's own built-in, so this needs no jq on the machine; jq arrives much later,
# with the Brewfile.
REPO_PRIVATE=""; REPO_FORK=""; REPO_TEMPLATE=""; REPO_PARENT=""
gh_repo_facts() {
  local out
  set_repo_slug
  out="$(gh repo view "$REPO_SLUG" --json isPrivate,isFork,isTemplate,parent \
    --jq '[.isPrivate, .isFork, .isTemplate, (.parent.nameWithOwner // "")] | @tsv' 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  REPO_PRIVATE="$(printf '%s' "$out" | cut -f1)"
  REPO_FORK="$(printf '%s' "$out" | cut -f2)"
  REPO_TEMPLATE="$(printf '%s' "$out" | cut -f3)"
  REPO_PARENT="$(printf '%s' "$out" | cut -f4)"
  return 0
}

# ok | template | public | privatefork
REPO_VERDICT=""
classify_repo() {
  if [ "$REPO_TEMPLATE" = "true" ] || [ "$REPO_SLUG" = "$TEMPLATE" ]; then
    REPO_VERDICT="template"
  elif [ "$REPO_PRIVATE" != "true" ]; then
    REPO_VERDICT="public"
  elif [ "$REPO_FORK" = "true" ]; then
    REPO_VERDICT="privatefork"
  else
    REPO_VERDICT="ok"
  fi
}

# Why an existing repo of that name cannot be the fleet brain. Printed before anything on
# the machine has changed, by both the refusal and the re-ask.
explain_unsuitable_repo() {
  case "$REPO_VERDICT" in
    template)
      err "$REPO_SLUG is a template repository, not an instance."
      say "That is the thing you copy, not the copy. Give your instance another name — and use"
      say "the same name on every machine you own:"
      say ""
      say "  … -- --name sys-admin --dir ~/claude-computer"
      say ""
      ;;
    public)
      err "$REPO_SLUG is public."
      if [ "$REPO_FORK" = "true" ]; then
        say "It looks like a public fork${REPO_PARENT:+ of $REPO_PARENT}, not a private instance."
      fi
      say "Your instance holds a map of your machines — hostnames, ports, what is installed and"
      say "listening — so it has to be private. Either give the instance another name, using the"
      say "same name on every machine you own:"
      say ""
      say "  … -- --name sys-admin --dir ~/claude-computer"
      say ""
      say "or make this one private first:  gh repo edit $REPO_SLUG --visibility private"
      ;;
  esac
}

refuse_unsuitable_repo() {
  case "$REPO_VERDICT" in
    template|public) explain_unsuitable_repo; exit 6 ;;
  esac
}

# GitHub's rules, near enough: letters, digits, dot, dash, underscore; not . or ..; ≤100.
valid_repo_name() {
  case "$1" in
    ""|.|..) return 1 ;;
    *[!A-Za-z0-9._-]*) return 1 ;;
  esac
  [ "${#1}" -le 100 ]
}

# A question changes nothing, so a dry run may ask it; --yes and a pipe may not.
can_ask() {
  [ "$ASSUME_YES" -eq 0 ] || return 1
  is_tty
}

# read_name <prompt> → NAME_REPLY. Reads stdin, which is the terminal in a real run and the
# harness's answers under test.
NAME_REPLY=""
read_name() {
  printf '%s' "$1"
  read -r NAME_REPLY || NAME_REPLY=""
}

ONE_REPO_LINE="It is ONE repo for every machine you own: use the same name on each."

# The first question the installer asks, and with no flags the only one before the checklist.
# If gh is already logged in it looks first: an existing private instance of the default name
# is offered as the Enter answer, and one that cannot be an instance — the template, or the
# public fork every contributor has — is named as such and not offered.
ask_repo_name() {
  local tries=0 offer="" why=""

  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    GH_ACCOUNT="$(gh api user --jq .login 2>/dev/null || true)"
  fi

  if [ -n "$GH_ACCOUNT" ] && gh_repo_exists; then
    if gh_repo_facts; then classify_repo; else REPO_VERDICT="unknown"; fi
    case "$REPO_VERDICT" in
      ok|privatefork) offer="$REPO_SLUG" ;;
      template) why="it is a template repository, not an instance" ;;
      public)   why="it is public, and a map of your machines must not go there" ;;
    esac
  fi
  # Nothing learned here may leak into the preflight's own verdict for the chosen name.
  REPO_VERDICT=""; REPO_PRIVATE=""; REPO_FORK=""; REPO_TEMPLATE=""; REPO_PARENT=""

  say ""
  if [ -n "$offer" ]; then
    say "  Found your existing private repo ${C_B}$offer${C_0} — press Enter to use it"
    say "  (this machine will join that fleet)."
  elif [ -n "$why" ]; then
    say "  ${C_Y}$REPO_SLUG exists, but $why.${C_0}"
    say "  So pick another name for your private repo — for example ${C_B}sys-admin${C_0}."
  fi

  say "  What should your private repo be called? $ONE_REPO_LINE"
  while [ "$tries" -lt 3 ]; do
    tries=$((tries + 1))
    if [ -n "$why" ]; then
      read_name "  Repo name: "
    else
      read_name "  Repo name [claude-computer]: "
      [ -n "$NAME_REPLY" ] || NAME_REPLY="claude-computer"
    fi
    if valid_repo_name "$NAME_REPLY"; then
      NAME="$NAME_REPLY"
      set_repo_slug
      return 0
    fi
    # No default to fall back on here, so an empty answer is not a typo to be corrected.
    if [ -z "$NAME_REPLY" ]; then
      warn "it needs a name — there is no default this time. sys-admin would do."
    else
      warn "not a usable GitHub repo name: letters, digits, dot, dash and underscore only."
    fi
  done
  die 2 "no usable repo name after three tries."
}

# The suitability gate said no. Interactively that is a question, not a wall: ask for another
# name and settle REMOTE_STATE / REPO_VERDICT for it. A scripted run still exits 6.
reask_or_refuse() {
  local tries=0
  if [ "$NAME_GIVEN" -eq 1 ] || ! can_ask; then
    refuse_unsuitable_repo
    return 0
  fi
  explain_unsuitable_repo
  say "  Pick another name for your private repo. $ONE_REPO_LINE"
  while [ "$tries" -lt 3 ]; do
    tries=$((tries + 1))
    read_name "  Repo name: "
    if ! valid_repo_name "$NAME_REPLY"; then
      warn "not a usable GitHub repo name: letters, digits, dot, dash and underscore only."
      continue
    fi
    NAME="$NAME_REPLY"
    set_repo_slug
    if ! gh_repo_exists; then
      REMOTE_STATE="absent"; REPO_VERDICT=""
      have "$REPO_SLUG does not exist yet — it will be created from the template"
      return 0
    fi
    if gh_repo_facts; then classify_repo; else REPO_VERDICT="unknown"; fi
    case "$REPO_VERDICT" in
      template|public) explain_unsuitable_repo ;;
      *) REMOTE_STATE="exists"; return 0 ;;
    esac
  done
  die 2 "no usable repo name after three tries."
}

# ---- this machine's name in the fleet -------------------------------------
# The repo name plays no part in it: CLAUDE.md has Claude read `scutil --get LocalHostName`
# and write docs/machines/<host>.md, and tag its commits [<host>].
local_hostname() {
  if [ -n "${CC_INSTALL_TEST_HOSTNAME:-}" ]; then printf '%s' "$CC_INSTALL_TEST_HOSTNAME"; return 0; fi
  scutil --get LocalHostName 2>/dev/null || true
}

# "Someones-MacBook-Pro" and friends: the name macOS made up, which nobody meant.
hostname_looks_default() {
  case "$1" in
    *MacBook*|*Mac-mini*|*Mac-Studio*|*Mac-Pro*|*iMac*|*MacPro*|*s-Mac*) return 0 ;;
  esac
  [ "${#1}" -gt 24 ]
}

hostname_note() {
  local h="$1"
  [ -n "$h" ] || return 0
  hostname_looks_default "$h" || return 0
  needs_you "machines are identified by hostname, not by repo name, and \"$h\" is the name macOS"
  say "    made up. To change it before /setup — yours to run, it needs sudo:"
  say "      ${C_D}sudo scutil --set LocalHostName mini${C_0}"
}

# ---- probes ---------------------------------------------------------------
uname_s() { printf '%s' "${CC_INSTALL_TEST_UNAME_S:-$(uname -s)}"; }
uname_m() { printf '%s' "${CC_INSTALL_TEST_ARCH:-$(uname -m)}"; }

os_version() {
  if [ -n "${CC_INSTALL_TEST_OS_VERSION:-}" ]; then
    printf '%s' "$CC_INSTALL_TEST_OS_VERSION"
  elif command -v sw_vers >/dev/null 2>&1; then
    sw_vers -productVersion 2>/dev/null || printf 'unknown'
  else
    printf 'unknown'
  fi
}

ZPROFILE="${CC_INSTALL_TEST_ZPROFILE:-$HOME/.zprofile}"
BREW_PREFIXES="${CC_INSTALL_TEST_BREW_PREFIXES:-/opt/homebrew/bin/brew:/usr/local/bin/brew}"
CLAUDE_NATIVE="${CC_INSTALL_TEST_CLAUDE_NATIVE:-$HOME/.local/bin/claude:$HOME/.claude/local}"

# Homebrew is regularly installed but not yet on PATH — that is the single most common
# stall for a new user — so probe the two prefixes by path, not just `command -v`.
find_brew() {
  local saved_ifs p
  saved_ifs="$IFS"; IFS=":"
  for p in $BREW_PREFIXES; do
    IFS="$saved_ifs"
    if [ -x "$p" ]; then printf '%s' "$p"; return 0; fi
    IFS=":"
  done
  IFS="$saved_ifs"
  command -v brew 2>/dev/null || return 1
}

# /usr/bin/git, /usr/bin/clang and /usr/bin/python3 are not those programs on a Mac without
# the Command Line Tools: they are one small shim binary, and *invoking* any of them pops the
# "install developer tools" GUI dialog. Nothing may execute one before step 1 has finished —
# not even under --dry-run, which promises to change nothing and ask nothing.
#
# So this probe is filesystem-first. A stale developer directory after an OS upgrade leaves
# `xcode-select -p` answering while the tools underneath are gone, which is the case the
# three-way check exists for; looking for the real binaries on disk catches it without
# running the shim. Only once they are there is it safe to execute git and clang, because by
# then /usr/bin/git forwards to a real one instead of opening the installer.
clt_ok() {
  local p
  p="$(xcode-select -p 2>/dev/null)" || return 1
  [ -n "$p" ] || return 1
  [ -d "$p" ] || return 1
  [ -x "$p/usr/bin/git" ] || return 1
  [ -x "$p/usr/bin/clang" ] || return 1
  git --version >/dev/null 2>&1 || return 1
  clang --version >/dev/null 2>&1 || return 1
  return 0
}

find_claude_native() {
  local saved_ifs p
  saved_ifs="$IFS"; IFS=":"
  for p in $CLAUDE_NATIVE; do
    IFS="$saved_ifs"
    if [ -e "$p" ]; then printf '%s' "$p"; return 0; fi
    IFS=":"
  done
  IFS="$saved_ifs"
  return 1
}

is_admin() {
  if [ -n "${CC_INSTALL_TEST_ADMIN:-}" ]; then
    [ "$CC_INSTALL_TEST_ADMIN" = "yes" ]
    return
  fi
  id -Gn 2>/dev/null | tr ' ' '\n' | grep -qx admin
}

free_kb() {
  if [ -n "${CC_INSTALL_TEST_DISK_KB:-}" ]; then
    printf '%s' "$CC_INSTALL_TEST_DISK_KB"
  else
    df -k "$HOME" 2>/dev/null | awk 'NR==2 {print $4}' || printf '0'
  fi
}

net_ok() {
  if [ "${CC_INSTALL_TEST_SKIP_NET:-0}" = "1" ]; then return 0; fi
  curl -fsS --max-time 10 -o /dev/null "https://github.com" 2>/dev/null
}

# ---- preflight ------------------------------------------------------------
STEP="preflight"

say ""
say "${C_B}claude-computer installer${C_0} ${C_D}$VERSION${C_0}"
if [ "$DRY" -eq 1 ]; then say "${C_Y}dry run — nothing on this machine will change.${C_0}"; fi

# The one question, and only when nobody has answered it already. A dry run may ask it: a
# question changes nothing, and seeing the real repo name in the plan is the point of one.
# Not on a machine this installer is about to refuse: the macOS check is two lines below.
if [ "$NAME_GIVEN" -eq 0 ] && [ "$PUBLIC_CLONE" -eq 0 ] && [ "$(uname_s)" = "Darwin" ] && can_ask; then
  ask_repo_name
else
  set_repo_slug
fi

say ""
say "${C_D}template: $TEMPLATE${C_0}"
say "${C_D}repo: ${GH_ACCOUNT:+$GH_ACCOUNT/}$NAME · directory: $DISPLAY_DIR${C_0}"

head2 "The machine"

if [ "$(uname_s)" != "Darwin" ]; then
  err "this installer is macOS only (found $(uname_s))."
  say "Headless Linux boxes are managed from a Mac over SSH — they are never set up this way."
  say "See the README: https://github.com/$TEMPLATE#the-map"
  exit 3
fi
have "macOS $(os_version)"

ARCH="$(uname_m)"
case "$ARCH" in
  arm64)  have "Apple silicon ($ARCH)" ;;
  x86_64) have "Intel ($ARCH) — note: the MacParakeet dictation and transcript pipeline is Apple silicon only; the Brewfile skips it here" ;;
  *)      warn "unrecognised architecture: $ARCH — Homebrew may not support it" ;;
esac

if is_admin; then
  have "you are an administrator (Homebrew needs it)"
else
  needs_you "you are not an administrator — the Homebrew install will fail; log in as one first"
fi

FREE="$(free_kb)"
case "$FREE" in
  ''|*[!0-9]*) warn "could not read free disk space" ;;
  *)
    FREE_GB=$((FREE / 1024 / 1024))
    if [ "$FREE_GB" -lt 15 ]; then
      needs_you "${FREE_GB}GB free — the Command Line Tools and Homebrew want about 15GB"
    else
      have "${FREE_GB}GB free on this volume"
    fi
    ;;
esac

if net_ok; then
  have "github.com is reachable"
else
  needs_you "could not reach github.com — check your connection before continuing"
fi

head2 "What it will fetch"
say "  $BREW_INSTALLER_URL   ${C_D}(the official Homebrew installer)${C_0}"
say "  https://github.com/$TEMPLATE            ${C_D}(your copy of the template)${C_0}"
say "  ${C_D}whatever brew and gh download for gh and the Claude Code cask${C_0}"

head2 "What is already here"

DO_CLT=0
if clt_ok; then
  have "Xcode Command Line Tools ($(xcode-select -p 2>/dev/null))"
else
  DO_CLT=1
  if xcode-select -p >/dev/null 2>&1; then
    will "Xcode Command Line Tools — the path is set but git or clang is broken (stale after an OS upgrade); reinstalling"
  else
    will "Xcode Command Line Tools — a GUI dialog will open; click Install"
  fi
fi

DO_BREW=0
BREW_BIN=""
if BREW_BIN="$(find_brew)"; then
  if command -v brew >/dev/null 2>&1; then
    have "Homebrew ($BREW_BIN)"
  else
    have "Homebrew ($BREW_BIN) — installed but not on your PATH; this run will fix that"
  fi
else
  DO_BREW=1
  BREW_BIN=""
  will "Homebrew — its installer will ask for your password"
fi

DO_GH=0
DO_GH_AUTH=0
GH_ACCOUNT=""
if command -v gh >/dev/null 2>&1; then
  have "gh ($(command -v gh))"
  if gh auth status >/dev/null 2>&1; then
    GH_ACCOUNT="$(gh api user --jq .login 2>/dev/null || true)"
    if [ -n "$GH_ACCOUNT" ]; then
      have "gh is logged in as $GH_ACCOUNT"
    else
      have "gh is logged in"
    fi
  else
    DO_GH_AUTH=1
    needs_you "gh is not logged in — you will do the login yourself"
  fi
else
  DO_GH=1
  DO_GH_AUTH=1
  will "gh (brew install gh)"
  needs_you "then a GitHub login, which you do yourself"
fi

DO_CLAUDE=0
if command -v claude >/dev/null 2>&1; then
  have "Claude Code ($(command -v claude))"
elif CLAUDE_AT="$(find_claude_native)"; then
  have "Claude Code, native install ($CLAUDE_AT) — leaving it alone, not adding a second copy"
elif [ -n "$BREW_BIN" ] && "$BREW_BIN" list --cask claude-code >/dev/null 2>&1; then
  have "Claude Code (the claude-code cask)"
else
  DO_CLAUDE=1
  will "Claude Code (brew install --cask claude-code)"
fi

# Reading the git identity means running git, which before step 1 is the shim. A warning
# either way: /setup asks for these, and nothing before then makes a commit.
report_git_identity() {
  local n e
  if ! clt_ok; then
    needs_you "git identity — checked once the Command Line Tools are in; /setup asks for it either way"
    return 0
  fi
  n="$(git config --global user.name 2>/dev/null || true)"
  e="$(git config --global user.email 2>/dev/null || true)"
  if [ -n "$n" ] && [ -n "$e" ]; then
    have "git identity: $n <$e>"
  else
    needs_you "git has no global user.name/user.email — /setup will ask you for them later"
  fi
}
report_git_identity

# A clone of our own repo with no CLAUDE.md in it is the wreckage of a run that gave up
# while GitHub was still copying the template. It is resumable, not an obstruction, so it
# must not be mistaken for someone else's directory and refused with exit 4.
#
# The origin is read out of .git/config with grep rather than `git remote get-url`, because
# this runs before step 1, where git is the shim. Nothing here executes git.
unfinished_clone() {
  [ -d "$DIR/.git" ] || return 1
  [ -f "$DIR/CLAUDE.md" ] && return 1
  [ -f "$DIR/.git/config" ] || return 1
  grep -qE "url *=.*[/:]$NAME(\.git)?\$" "$DIR/.git/config" 2>/dev/null
}

# The destination, and whether a repo of that name already exists on the account.
# "existing remote, no local clone" is exactly the documented second-machine path.
DIR_STATE="none"
if [ -e "$DIR" ]; then
  if [ -d "$DIR/.git" ] && [ -f "$DIR/CLAUDE.md" ]; then
    DIR_STATE="clone"
    have "$DIR is already a claude-computer clone — leaving it as it is"
  elif unfinished_clone; then
    DIR_STATE="unfinished"
    will "$DIR is a clone of $NAME that GitHub had not finished filling — resuming it"
  elif [ -d "$DIR" ] && [ -z "$(ls -A "$DIR" 2>/dev/null)" ]; then
    DIR_STATE="empty"
    will "$DIR exists but is empty — cloning into it"
  else
    DIR_STATE="occupied"
  fi
fi

REMOTE_STATE="unknown"
if [ "$PUBLIC_CLONE" -eq 1 ]; then
  REMOTE_STATE="skipped"
elif [ "$DO_GH_AUTH" -eq 0 ] && command -v gh >/dev/null 2>&1; then
  if gh_repo_exists; then REMOTE_STATE="exists"; else REMOTE_STATE="absent"; fi
fi

# What the existing repo actually is. An existing local clone is only warned about: /setup
# and the Stop hook have their own guard against pushing a map to a public remote, and the
# clone is already on disk either way, so refusing here would stop a machine that is
# otherwise fine. A repo we are about to clone fresh is refused outright.
if [ "$REMOTE_STATE" = "exists" ]; then
  if gh_repo_facts; then
    classify_repo
    if [ "$DIR_STATE" = "clone" ]; then
      case "$REPO_VERDICT" in
        template) needs_you "the clone at $DIR points at $REPO_SLUG, which is a TEMPLATE repo — check its origin before /setup pushes anything" ;;
        public) needs_you "the clone at $DIR points at $REPO_SLUG, which is PUBLIC — a machine map must not be pushed there; fix its origin before /setup" ;;
      esac
    fi
  else
    REPO_VERDICT="unknown"
  fi
fi

head2 "Your copy"
if [ "$PUBLIC_CLONE" -eq 1 ]; then
  will "read-only clone of $TEMPLATE into $DIR (--public-clone: no repo of your own)"
elif [ "$DIR_STATE" = "clone" ]; then
  have "nothing to create — $DIR is already there"
elif [ "$DIR_STATE" = "unfinished" ]; then
  # Resuming still means filling a local clone from a remote, so the remote still has to be
  # an instance and not the template or a public fork. The verdict comes first, as it does on
  # the exists-remote path below: promising to finish the clone off and then refusing in the
  # next breath reads like a bug.
  case "$REPO_VERDICT" in
    template)
      needs_you "$REPO_SLUG is a TEMPLATE repo, not an instance — the half-filled clone at $DIR cannot be finished off from it"
      refuse_unsuitable_repo
      ;;
    public)
      needs_you "$REPO_SLUG is PUBLIC — a machine map must not be pushed there, so the half-filled clone at $DIR cannot be your instance"
      refuse_unsuitable_repo
      ;;
  esac
  will "the half-filled clone at $DIR finished off — no new repo is created"
elif [ "$DIR_STATE" = "occupied" ]; then
  err "$DIR already exists and is not a claude-computer clone."
  say "Move it aside, or pass --dir <somewhere else>, and run this again."
  exit 4
elif [ "$REMOTE_STATE" = "exists" ]; then
  # The verdict comes first: promising to clone it and then refusing in the next breath reads
  # like a bug. An unsuitable repo gets a ! line naming the problem, then the refusal — or,
  # interactively, another go at the name.
  case "$REPO_VERDICT" in
    template)
      needs_you "$REPO_SLUG exists on GitHub but is a TEMPLATE repo, not an instance — nothing can be cloned from it as your fleet brain"
      reask_or_refuse
      ;;
    public)
      needs_you "$REPO_SLUG exists on GitHub but is PUBLIC — a machine map must not be pushed there, so it cannot be your instance"
      reask_or_refuse
      ;;
  esac
  if [ "$REMOTE_STATE" = "exists" ]; then
    will "$REPO_SLUG already exists on GitHub — cloning it instead of creating it (this is the second-machine path)"
    case "$REPO_VERDICT" in
      privatefork) have "it is a private fork${REPO_PARENT:+ of $REPO_PARENT} — that is fine, using it" ;;
      ok) have "it is private and not a template — an instance, as expected" ;;
      unknown) needs_you "could not read whether $REPO_SLUG is private — confirm it is before /setup pushes a machine map to it" ;;
    esac
    THIS_HOST="$(local_hostname)"
    if [ -n "$THIS_HOST" ]; then
      say "  ${C_D}same repo on every machine: this one will appear as docs/machines/$THIS_HOST.md${C_0}"
    fi
    hostname_note "$THIS_HOST"
  else
    will "a private $NAME from the $TEMPLATE template, cloned to $DIR"
  fi
elif [ "$REMOTE_STATE" = "absent" ]; then
  will "a private $NAME from the $TEMPLATE template, cloned to $DIR"
  THIS_HOST="$(local_hostname)"
  if [ -n "$THIS_HOST" ]; then
    say "  ${C_D}one repo for the whole fleet: this machine will be docs/machines/$THIS_HOST.md in it${C_0}"
  fi
  hostname_note "$THIS_HOST"
else
  will "a private $NAME from the $TEMPLATE template, cloned to $DIR (checked after you log in)"
fi

# The two things people conflate, said plainly and last, after any re-ask has settled the
# name: the repo is on GitHub and may be called anything; the directory is load-bearing.
set_repo_slug
say "  ${C_D}repo: $REPO_SLUG · directory: $DISPLAY_DIR${C_0}"

head2 "What stays yours"
say "  Every login and every password. This script never reads, writes or asks for a credential."
say "  It never runs sudo itself — Homebrew's own installer does that, and shows you what it will do."
say "  It does not touch ~/.claude, and edits no shell profile but one ${C_D}brew shellenv${C_0} line."

say ""
if [ "$DRY" -eq 1 ]; then
  say "${C_Y}Dry run: here is every command it would run.${C_0}"
elif [ "$ASSUME_YES" -eq 0 ]; then
  if ! confirm "Proceed?"; then
    say "Nothing changed."
    exit 0
  fi
fi

# ---- a. Xcode Command Line Tools -----------------------------------------
STEP="Xcode Command Line Tools"
head2 "1/5 Xcode Command Line Tools"

if [ "$DO_CLT" -eq 0 ]; then
  info "  already installed"
else
  say "  A macOS dialog will open. Click ${C_B}Install${C_0} and accept the licence."
  if [ "$DRY" -eq 1 ]; then
    run xcode-select --install
    info "    (then poll xcode-select -p / git --version for up to 30 minutes)"
  else
    # `xcode-select --install` exits non-zero with "already installed" when it is; that is
    # not a failure, and the poll below is the real answer either way.
    if ! out="$(xcode-select --install 2>&1)"; then
      case "$out" in
        *"already installed"*) info "  the tools are already installed" ;;
        *) info "  $out" ;;
      esac
    fi
    say "  Waiting for the Command Line Tools installer to finish…"
    waited=0
    while [ "$waited" -lt 1800 ]; do
      if clt_ok; then break; fi
      sleep 10
      waited=$((waited + 10))
      if [ $((waited % 120)) -eq 0 ]; then
        info "  still waiting… (${waited}s; the dialog may be behind another window)"
      fi
    done
    if ! clt_ok; then
      err "the Command Line Tools did not finish within 30 minutes."
      say "Finish the installer (or run 'xcode-select --install' by hand), then run this again."
      exit 5
    fi
    say "  ${C_G}done${C_0} ($(xcode-select -p))"
  fi
fi

# ---- b. Homebrew ----------------------------------------------------------
STEP="Homebrew"
head2 "2/5 Homebrew"

if [ "$DO_BREW" -eq 1 ]; then
  say "  Homebrew's own installer runs next. It will ${C_B}ask for your password${C_0} and print"
  say "  everything it is about to do. Read it; it is not this script asking."
  if [ "$DRY" -eq 1 ]; then
    show "/bin/bash -c \"\$(curl -fsSL $BREW_INSTALLER_URL)\""
    BREW_BIN="/opt/homebrew/bin/brew"
  else
    # Run the official line exactly as Homebrew documents it, interactively — not
    # NONINTERACTIVE=1, so the user sees and approves each part of it and types their
    # own password. This script never runs sudo itself.
    /bin/bash -c "$(curl -fsSL "$BREW_INSTALLER_URL")"
    BREW_BIN="$(find_brew)" || die 1 "Homebrew installed but brew is still not at /opt/homebrew/bin or /usr/local/bin"
  fi
else
  info "  already installed ($BREW_BIN)"
fi

# Make brew usable in *this* process, whatever the profile says.
if [ "$DRY" -eq 1 ]; then
  show "eval \"\$($BREW_BIN shellenv)\""
else
  eval "$("$BREW_BIN" shellenv)"
fi

# Homebrew finishes by printing two lines to add to your shell profile, and not running them
# is the classic newcomer stall — the next command fails with "brew: command not found".
SHELLENV_LINE="eval \"\$($BREW_BIN shellenv)\""
if [ -f "$ZPROFILE" ] && grep -q 'brew shellenv' "$ZPROFILE" 2>/dev/null; then
  info "  $ZPROFILE already loads brew"
else
  say "  Adding the line Homebrew asks for to $ZPROFILE, so brew is on your PATH in new shells:"
  say "    ${C_D}$SHELLENV_LINE${C_0}"
  if [ "$DRY" -eq 1 ]; then
    show "printf '%s' '$SHELLENV_LINE' >> $ZPROFILE"
  else
    printf '\n# added by the claude-computer installer\n%s\n' "$SHELLENV_LINE" >> "$ZPROFILE"
  fi
fi

# ---- c. gh ----------------------------------------------------------------
STEP="the GitHub CLI"
head2 "3/5 The GitHub CLI"

if [ "$DO_GH" -eq 1 ]; then
  say "  Installing gh. No password needed."
  run "$BREW_BIN" install gh
else
  info "  already installed"
fi

if [ "$DO_GH_AUTH" -eq 1 ]; then
  say "  ${C_B}This next bit is yours.${C_0} gh will ask how you want to log in — take the defaults"
  say "  (GitHub.com, HTTPS, authenticate in a browser). The template creates a per-machine"
  say "  SSH key of its own later, during /setup; you do not need one now."
  if [ "$DRY" -eq 1 ]; then
    run gh auth login
  else
    gh auth login
    gh auth status >/dev/null 2>&1 || die 1 "gh is still not logged in — run 'gh auth login' and try again"
    GH_ACCOUNT="$(gh api user --jq .login 2>/dev/null || true)"
    # Now that we can ask, settle the question preflight had to leave open.
    if [ "$PUBLIC_CLONE" -eq 0 ] && [ "$REMOTE_STATE" = "unknown" ]; then
      if gh_repo_exists; then REMOTE_STATE="exists"; else REMOTE_STATE="absent"; fi
      # The same suitability gate as the preflight, which could not run it before the login.
      # Still before anything of yours is touched: only gh and brew have run so far.
      if [ "$REMOTE_STATE" = "exists" ]; then
        if gh_repo_facts; then classify_repo; else REPO_VERDICT="unknown"; fi
        case "$REPO_VERDICT" in
          template|public)
            if [ "$DIR_STATE" = "clone" ]; then
              needs_you "$REPO_SLUG is not a private instance — check the clone's origin before /setup pushes a map"
            else
              reask_or_refuse
            fi
            ;;
          privatefork) info "  $REPO_SLUG is a private fork${REPO_PARENT:+ of $REPO_PARENT} — using it" ;;
        esac
      fi
      if [ "$REMOTE_STATE" = "exists" ] && [ "$DIR_STATE" != "clone" ]; then
        info "  $REPO_SLUG already exists — this is the second-machine path: it will be cloned, not created"
        THIS_HOST="$(local_hostname)"
        if [ -n "$THIS_HOST" ]; then
          info "  same repo on every machine: this one will appear as docs/machines/$THIS_HOST.md"
        fi
        hostname_note "$THIS_HOST"
      fi
    fi
  fi
else
  info "  already logged in${GH_ACCOUNT:+ as $GH_ACCOUNT}"
fi

# ---- d. Claude Code -------------------------------------------------------
STEP="Claude Code"
head2 "4/5 Claude Code"

if [ "$DO_CLAUDE" -eq 1 ]; then
  say "  Installing the Claude Code cask. macOS may ask you to confirm the app the first time you open it."
  run "$BREW_BIN" install --cask claude-code
else
  info "  already installed — not adding a second copy"
fi

# ---- e. your private copy -------------------------------------------------
STEP="your copy of the template"
head2 "5/5 Your copy of the template"

# /setup deletes .template when it turns a fresh copy into your instance, so a clone of a
# repo you already ran /setup on will not have it. Only a straight-from-the-template copy
# is required to.
WANT_TEMPLATE_MARK=1

# `gh repo create --template` returns before GitHub has finished copying the template into
# the new repo, so a clone issued straight afterwards can come back empty — "You appear to
# have cloned an empty repository". gh's own --clone flag retries internally; since we clone
# separately so that --dir can point anywhere, we have to do the waiting ourselves.
#
# An empty clone has origin set and an unborn branch, so `pull --ff-only` fails on it with
# no upstream. Fetch first, work out the default branch from origin/HEAD, and check it out.
# Everything is best-effort: whether CLAUDE.md turned up is the only real answer.
wait_for_template_copy() {
  local waited=0 br=""
  if [ -f "$DIR/CLAUDE.md" ]; then return 0; fi
  say "  Waiting for GitHub to finish copying the template…"
  while [ "$waited" -lt 60 ]; do
    sleep 5
    waited=$((waited + 5))
    git -C "$DIR" fetch --quiet origin >/dev/null 2>&1 || true
    br="$(git -C "$DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
    br="${br#origin/}"
    if [ -z "$br" ]; then
      br="$(git -C "$DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    fi
    [ -n "$br" ] || br="main"
    git -C "$DIR" checkout --quiet -B "$br" "origin/$br" >/dev/null 2>&1 ||
      git -C "$DIR" pull --ff-only --quiet >/dev/null 2>&1 || true
    if [ -f "$DIR/CLAUDE.md" ]; then
      say "  ${C_G}✓${C_0} the copy arrived (after ${waited}s)"
      return 0
    fi
  done
  return 1
}

NEED_WAIT=0

if [ "$DIR_STATE" = "clone" ]; then
  info "  $DIR is already there — skipping"
  WANT_TEMPLATE_MARK=0
elif [ "$DIR_STATE" = "unfinished" ]; then
  say "  Finishing the clone at $DIR that the last run left half-filled."
  WANT_TEMPLATE_MARK=0
  NEED_WAIT=1
elif [ "$PUBLIC_CLONE" -eq 1 ]; then
  say "  Read-only clone of $TEMPLATE. Nothing is created on your account."
  run git clone "https://github.com/$TEMPLATE.git" "$DIR"
elif [ "$REMOTE_STATE" = "exists" ]; then
  say "  $NAME already exists on your account — cloning it rather than creating a second one."
  say "  (This is the second-machine path: the repo already knows your fleet.)"
  run gh repo clone "$REPO_SLUG" "$DIR"
  WANT_TEMPLATE_MARK=0
else
  say "  Creating a private $NAME from $TEMPLATE, then cloning it to $DIR."
  run mkdir -p "$PARENT"
  # Two commands rather than the README's single `--clone`, so that --dir can point anywhere
  # and not just at ./<name> in the current directory.
  run gh repo create "$NAME" --template "$TEMPLATE" --private
  # Belt and braces: confirm what was actually created is private before a machine map is
  # ever written into it. An org default or a flag that silently did not take would
  # otherwise only show up much later, in a public repo.
  if [ "$DRY" -eq 0 ]; then
    if ! gh_repo_facts; then
      die 6 "cannot confirm $REPO_SLUG is private — refusing to clone it as your fleet brain"
    elif [ "$REPO_PRIVATE" != "true" ]; then
      err "$REPO_SLUG was created but is not private."
      say "Your instance holds a map of your machines, so this stops here. Fix it with:"
      say "  gh repo edit $REPO_SLUG --visibility private"
      say "then run this again — it will take the 'already exists → clone' path."
      exit 6
    fi
    say "  ${C_G}✓${C_0} $REPO_SLUG is private"
  fi
  run gh repo clone "$NAME" "$DIR"
  NEED_WAIT=1
fi

if [ "$NEED_WAIT" -eq 1 ]; then
  if [ "$DRY" -eq 1 ]; then
    show "# then poll the clone for up to 60s while GitHub copies the template"
  elif ! wait_for_template_copy; then
    err "GitHub has not finished copying the template into $NAME after 60 seconds."
    say "Nothing is broken and re-running is safe: the repo exists now, so the next run takes"
    say "the 'already exists → clone' path and picks up the half-filled clone at $DIR."
    exit 1
  fi
fi

if [ "$DRY" -eq 0 ]; then
  for f in CLAUDE.md docs/FIRST-PROMPT.md; do
    [ -e "$DIR/$f" ] || die 1 "the clone at $DIR is missing $f — it is not a copy of $TEMPLATE"
  done
  if [ "$WANT_TEMPLATE_MARK" -eq 1 ]; then
    [ -e "$DIR/.template" ] || die 1 "the clone at $DIR has no .template — the copy did not come from $TEMPLATE"
    say "  ${C_G}✓${C_0} CLAUDE.md, docs/FIRST-PROMPT.md and .template are all there"
  else
    say "  ${C_G}✓${C_0} CLAUDE.md and docs/FIRST-PROMPT.md are there"
  fi
fi
# gitleaks scans every commit; without this the hook is inert.
run git -C "$DIR" config core.hooksPath .githooks

# ---- handover -------------------------------------------------------------
STEP="the handover"
head2 "Done. Three things left, and they are all yours."

FIRST_PROMPT=""
if [ -f "$DIR/docs/FIRST-PROMPT.md" ]; then
  # The first fenced ```text block of the repo's own FIRST-PROMPT.md, so this can never
  # drift from the file the README points at.
  FIRST_PROMPT="$(awk '
    /^```text$/ { if (!seen) { seen = 1; inb = 1; next } }
    inb && /^```/ { exit }
    inb { print }
  ' "$DIR/docs/FIRST-PROMPT.md")"
fi

if [ -n "$FIRST_PROMPT" ] && command -v pbcopy >/dev/null 2>&1; then
  if [ "$DRY" -eq 1 ]; then
    show "awk '/^\`\`\`text\$/…' $DIR/docs/FIRST-PROMPT.md | pbcopy"
  else
    printf '%s\n' "$FIRST_PROMPT" | pbcopy
  fi
  COPIED=1
else
  COPIED=0
fi

say ""
say "  1. ${C_B}cd $DISPLAY_DIR && claude${C_0}"
say "  2. Log in to Claude Code, then check the status line reads ${C_B}⏵⏵ auto mode on${C_0}."
say "     Shift+Tab cycles the modes. Never ${C_B}bypass permissions${C_0}."
say "  3. Paste the first prompt and let it go."
if [ "$COPIED" -eq 1 ]; then
  say "     ${C_G}It is on your clipboard already${C_0} — ⌘V. It is also in docs/FIRST-PROMPT.md."
else
  say "     It is in $DIR/docs/FIRST-PROMPT.md."
fi
say ""
info "  This script does not start Claude Code for you, and sets no permission mode. You do."
say ""

trap - ERR
exit 0
