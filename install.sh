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
# Exit codes: 0 ok · 1 a step failed · 2 usage or no terminal · 3 not macOS · 4 something is
# already at the target directory · 5 the Command Line Tools installer never finished.
set -euo pipefail

VERSION="0.2.1"
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

Flags:
  --dry-run        print every command it would run; change nothing, ask nothing
  --yes            do not pause for confirmation between steps
  --dir <path>     where the clone goes (default: $HOME/claude-computer)
  --name <repo>    the name of your private repo (default: claude-computer)
  --public-clone   do not create a private copy; clone the template read-only, to look first
  --help           this text
  --version        print the version and exit

Environment:
  CC_INSTALL_TEMPLATE   template slug to copy from (default: narendranag/claude-computer).
                        Set it if you are installing from a fork.
  NO_COLOR              set to anything to turn colour off.

It must be run with a terminal on stdin, which is why the command above is
`bash -c "$(curl …)"` and not `curl … | bash`: the Homebrew installer's sudo prompt and
`gh auth login` both read from the terminal, and a pipe takes it away.

Exit codes: 0 ok · 1 a step failed · 2 usage or no terminal · 3 not macOS · 4 something is
already at the target directory · 5 the Command Line Tools installer never finished.
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
DIR=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)      DRY=1; shift ;;
    --yes|-y)       ASSUME_YES=1; shift ;;
    --public-clone) PUBLIC_CLONE=1; shift ;;
    --dir)          [ $# -ge 2 ] || die 2 "--dir needs a path"; DIR="$2"; shift 2 ;;
    --name)         [ $# -ge 2 ] || die 2 "--name needs a repo name"; NAME="$2"; shift 2 ;;
    -h|--help)      usage; exit 0 ;;
    --version)      say "install.sh $VERSION"; exit 0 ;;
    --)             shift ;;
    *)              usage >&2; die 2 "unknown argument: $1" ;;
  esac
done

[ -n "$DIR" ] || DIR="$HOME/$NAME"
case "$DIR" in /*) ;; *) DIR="$PWD/$DIR" ;; esac
PARENT="$(dirname "$DIR")"
DISPLAY_DIR="$DIR"
case "$DIR" in "$HOME"/*) DISPLAY_DIR="~${DIR#"$HOME"}" ;; esac

# ---- traps ----------------------------------------------------------------
STEP="starting up"

# shellcheck disable=SC2329  # invoked by the ERR trap below, not by name
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
if ! is_tty; then
  err "no terminal on stdin."
  say "Run it this way instead, so the installers can ask you for a password:"
  say ""
  say "  /bin/bash -c \"\$(curl -fsSL https://claude-computer.com/install.sh)\""
  say ""
  say "Not: curl … | bash — the pipe takes the terminal away."
  exit 2
fi

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

# A stale developer directory after an OS upgrade leaves `xcode-select -p` answering while
# git and clang are broken, so all three have to work before we call this done.
clt_ok() {
  xcode-select -p >/dev/null 2>&1 || return 1
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
say "${C_D}template: $TEMPLATE · destination: $DIR${C_0}"
if [ "$DRY" -eq 1 ]; then say "${C_Y}dry run — nothing on this machine will change.${C_0}"; fi

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

GIT_NAME="$(git config --global user.name 2>/dev/null || true)"
GIT_EMAIL="$(git config --global user.email 2>/dev/null || true)"
if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
  have "git identity: $GIT_NAME <$GIT_EMAIL>"
else
  # A warning, not a blocker: /setup asks for these, and nothing before then needs a commit.
  needs_you "git has no global user.name/user.email — /setup will ask you for them later"
fi

# The destination, and whether a repo of that name already exists on the account.
# "existing remote, no local clone" is exactly the documented second-machine path.
DIR_STATE="none"
if [ -e "$DIR" ]; then
  if [ -d "$DIR/.git" ] && [ -f "$DIR/CLAUDE.md" ]; then
    DIR_STATE="clone"
    have "$DIR is already a claude-computer clone — leaving it as it is"
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
  if gh repo view "$NAME" >/dev/null 2>&1; then
    REMOTE_STATE="exists"
  else
    REMOTE_STATE="absent"
  fi
fi

head2 "Your copy"
if [ "$PUBLIC_CLONE" -eq 1 ]; then
  will "read-only clone of $TEMPLATE into $DIR (--public-clone: no repo of your own)"
elif [ "$DIR_STATE" = "clone" ]; then
  have "nothing to create — $DIR is already there"
elif [ "$DIR_STATE" = "occupied" ]; then
  err "$DIR already exists and is not a claude-computer clone."
  say "Move it aside, or pass --dir <somewhere else>, and run this again."
  exit 4
elif [ "$REMOTE_STATE" = "exists" ]; then
  will "$GH_ACCOUNT/$NAME already exists on GitHub — cloning it instead of creating it (this is the second-machine path)"
elif [ "$REMOTE_STATE" = "absent" ]; then
  will "a private $NAME from the $TEMPLATE template, cloned to $DIR"
else
  will "a private $NAME from the $TEMPLATE template, cloned to $DIR (checked after you log in)"
fi

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
      if gh repo view "$NAME" >/dev/null 2>&1; then REMOTE_STATE="exists"; else REMOTE_STATE="absent"; fi
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

if [ "$DIR_STATE" = "clone" ]; then
  info "  $DIR is already there — skipping"
  WANT_TEMPLATE_MARK=0
elif [ "$PUBLIC_CLONE" -eq 1 ]; then
  say "  Read-only clone of $TEMPLATE. Nothing is created on your account."
  run git clone "https://github.com/$TEMPLATE.git" "$DIR"
elif [ "$REMOTE_STATE" = "exists" ]; then
  say "  $NAME already exists on your account — cloning it rather than creating a second one."
  say "  (This is the second-machine path: the repo already knows your fleet.)"
  run gh repo clone "$NAME" "$DIR"
  WANT_TEMPLATE_MARK=0
else
  say "  Creating a private $NAME from $TEMPLATE, then cloning it to $DIR."
  run mkdir -p "$PARENT"
  # Two commands rather than the README's single `--clone`, so that --dir can point anywhere
  # and not just at ./<name> in the current directory.
  run gh repo create "$NAME" --template "$TEMPLATE" --private
  run gh repo clone "$NAME" "$DIR"
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
