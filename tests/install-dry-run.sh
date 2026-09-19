#!/usr/bin/env bash
# tests/install-dry-run.sh — drive install.sh through twenty-two simulated machines.
#
# Usage: ./tests/install-dry-run.sh
#
# Every case builds a temporary PATH of stub executables and points the installer's
# CC_INSTALL_TEST_* probes at temporary files, so nothing on the real machine is read or
# written. Each stub appends its own invocation to $CC_STUB_LOG, which carries the two
# assertions that matter most: in --dry-run no mutating command ran, and before the Command
# Line Tools are installed no /usr/bin Xcode shim was invoked.
#
# Most cases are dry runs. (x)–(xii) and (xvii) are not: they exercise the post-clone wait,
# which only happens for real. Every command still goes to a stub there, `sleep` included, so
# the 60-second poll costs nothing.
#
# Cases: (i) nothing installed · (ii) everything installed and authed · (iii) brew present
# but not on PATH · (iv) an existing clone at --dir · (v) stdin is not a terminal, for a real
# run and for a dry one · (vi) Linux · (vii) bad arguments · (viii) the first prompt extracts
# from the real docs/FIRST-PROMPT.md · (ix) a stale developer path never touches the shim ·
# (x) the template copy lands on the third poll · (xi) it never lands · (xii) resuming the
# empty clone that left behind · (xiii) gh is owner-qualified · (xiv.a–e) is the existing
# repo actually a private instance · (xv) an existing clone with a public origin warns only ·
# (xvi) resuming refuses a public remote · (xvii) a created repo that is not private stops.
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
INSTALL="$PWD/install.sh"
[ -x "$INSTALL" ] || { echo "install.sh is not executable" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cc-install-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

check_exit() { # check_exit <want> <got>
  if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi
}
contains() { # contains <file> <needle>
  if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "output has no '$2'"; fi
}
absent() { # absent <file> <needle>
  if grep -qF -- "$2" "$1"; then bad "output should not say '$2'"; else ok "silent on: $2"; fi
}
log_lacks() { # log_lacks <logfile> <needle> — the mutation assertion
  if grep -qF -- "$2" "$1"; then bad "DRY RUN RAN IT: '$2'"; else ok "did not run: $2"; fi
}

# stub <dir> <name>, body on stdin. Every stub logs itself first.
stub() {
  local d="$1" n="$2"
  mkdir -p "$d"
  {
    echo '#!/bin/sh'
    # The single quotes are deliberate: this is the stub's source, expanded when it runs.
    # shellcheck disable=SC2016
    printf 'printf %s %s >> "$CC_STUB_LOG"\n' "'%s %s\\n'" "'$n' \"\$*\""
    cat
  } > "$d/$n"
  chmod +x "$d/$n"
}

# The three /usr/bin tools whose absence means "no Command Line Tools". They have to be
# shadowed by failing stubs, because a real macOS has them on PATH whatever we do.
stub_no_clt() {
  local d="$1"
  stub "$d" xcode-select <<'EOF'
exit 2
EOF
  stub "$d" git <<'EOF'
exit 127
EOF
  stub "$d" clang <<'EOF'
exit 127
EOF
}

# stub_clt <bindir> <devdir> — a machine that HAS the tools. install.sh checks the developer
# directory on disk before it dares execute git or clang, so the fake xcode-select has to
# point at a directory that really holds them. A hard-coded /Library/Developer path would
# pass on a developer's Mac and fail on CI, which is the bug this argument prevents.
stub_clt() {
  local d="$1" dev="$2"
  mkdir -p "$dev/usr/bin"
  printf '#!/bin/sh\nexit 0\n' > "$dev/usr/bin/git"
  printf '#!/bin/sh\nexit 0\n' > "$dev/usr/bin/clang"
  chmod +x "$dev/usr/bin/git" "$dev/usr/bin/clang"
  stub "$d" xcode-select <<EOF
case "\$1" in
  -p) echo "$dev"; exit 0 ;;
  --install) echo "xcode-select: note: Command Line Tools are already installed" >&2; exit 1 ;;
esac
exit 0
EOF
  stub "$d" git <<'EOF'
case "$*" in
  --version) echo "git version 2.48.0"; exit 0 ;;
  "config --global user.name")  echo "A Person"; exit 0 ;;
  "config --global user.email") echo "you@example.com"; exit 0 ;;
esac
exit 0
EOF
  stub "$d" clang <<'EOF'
echo "Apple clang version 17.0.0"
exit 0
EOF
}

stub_pbcopy() { stub "$1" pbcopy <<'EOF'
cat > /dev/null
exit 0
EOF
}

# A brew that answers `shellenv`, `list --cask` and swallows installs.
stub_brew() { # stub_brew <dir> <has-claude-cask: yes|no>
  local d="$1" cask="$2"
  stub "$d" brew <<EOF
case "\$*" in
  shellenv) echo 'export CC_FAKE_BREW=1' ;;
  "list --cask claude-code") [ "$cask" = yes ] && exit 0 || exit 1 ;;
esac
exit 0
EOF
}

# gh: <dir> <authed: yes|no> <remote repo exists: yes|no>
#
# The --json branch answers the suitability query and must come first, because the plain
# `repo view` pattern would otherwise swallow it. What it reports is $CC_TEST_REPO_FACTS —
# isPrivate, isFork, isTemplate, parent, tab separated — so a case can vary the answer
# without rebuilding the stub. base_env defaults it to a private non-fork instance.
stub_gh() {
  local d="$1" authed="$2" remote="$3"
  stub "$d" gh <<EOF
case "\$*" in
  *--json*)             [ "$remote" = yes ] && { printf '%s\\n' "\$CC_TEST_REPO_FACTS"; exit 0; }; exit 1 ;;
  "auth status")        [ "$authed" = yes ] && exit 0 || exit 1 ;;
  "api user --jq .login") [ "$authed" = yes ] && { echo octocat; exit 0; }; exit 1 ;;
  "repo view "*)        [ "$remote" = yes ] && exit 0 || exit 1 ;;
esac
exit 0
EOF
}

# isPrivate, isFork, isTemplate, parent — as `gh repo view --json … --jq '…|@tsv'` returns it.
facts() { # facts <private> <fork> <template> [parent]
  printf '%s\t%s\t%s\t%s' "$1" "$2" "$3" "${4:-}"
}

# Common environment for every dry-run case. Exported by run_installer's caller.
base_env() {
  export CC_INSTALL_TEST_TTY=1
  export CC_INSTALL_TEST_UNAME_S=Darwin
  export CC_INSTALL_TEST_ARCH=arm64
  export CC_INSTALL_TEST_OS_VERSION=15.6
  export CC_INSTALL_TEST_SKIP_NET=1
  export CC_INSTALL_TEST_ADMIN=yes
  export CC_INSTALL_TEST_DISK_KB=200000000
  export NO_COLOR=1
  export CC_INSTALL_TEMPLATE=narendranag/claude-computer
  # A private, non-fork, non-template repo: a real instance. Cases override it.
  CC_TEST_REPO_FACTS="$(facts true false false)"
  export CC_TEST_REPO_FACTS
}

# The commands that would change the machine. None may appear in a dry run's stub log.
assert_no_mutation() { # assert_no_mutation <logfile>
  log_lacks "$1" "xcode-select --install"
  log_lacks "$1" "brew install"
  log_lacks "$1" "gh repo create"
  log_lacks "$1" "gh repo clone"
  log_lacks "$1" "gh auth login"
  log_lacks "$1" "git clone"
  log_lacks "$1" "curl -fsSL https://raw.githubusercontent.com/Homebrew/install"
}

# On a Mac without the Command Line Tools, /usr/bin/git, /usr/bin/clang and /usr/bin/python3
# are one shim binary that opens the "install developer tools" GUI dialog when *invoked*.
# Before step 1 has finished, install.sh must not execute any of them — a dialog during
# preflight, or during a --dry-run that promised to ask nothing, is the bug this catches.
assert_no_shim_invoked() { # assert_no_shim_invoked <logfile>
  local t
  for t in git clang python3 make; do
    if grep -q "^$t " "$1" 2>/dev/null; then
      bad "POPPED THE XCODE DIALOG: ran $t before the tools were installed"
    else
      ok "never invoked the $t shim"
    fi
  done
}

banner() { printf '\n%s\n' "== $1"; }

# --------------------------------------------------------------------------
banner "(i) nothing installed"
D="$WORK/i"; mkdir -p "$D"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_no_clt "$D/bin"; stub_pbcopy "$D/bin"
base_env
export CC_INSTALL_TEST_BREW_PREFIXES="$D/no-brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --dir "$D/claude-computer" > "$D/out" 2>&1
check_exit 0 $?
contains "$D/out" "→ Xcode Command Line Tools"
contains "$D/out" "→ Homebrew"
contains "$D/out" "→ gh (brew install gh)"
contains "$D/out" "→ Claude Code (brew install --cask claude-code)"
contains "$D/out" "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
contains "$D/out" "gh repo create claude-computer --template narendranag/claude-computer --private"
contains "$D/out" "dry run — nothing on this machine will change."
absent   "$D/out" "Proceed?"
if [ -e "$D/zprofile" ]; then bad "dry run wrote the zprofile"; else ok "left the zprofile alone"; fi
contains "$D/out" "git identity — checked once the Command Line Tools are in"
assert_no_mutation "$CC_STUB_LOG"
assert_no_shim_invoked "$CC_STUB_LOG"

# --------------------------------------------------------------------------
banner "(ii) everything installed and authed"
D="$WORK/ii"; mkdir -p "$D/bin"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
stub_brew "$D/bin" yes
stub_gh "$D/bin" yes no
stub "$D/bin" claude <<'EOF'
exit 0
EOF
base_env
export CC_INSTALL_TEST_BREW_PREFIXES="$D/bin/brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
# shellcheck disable=SC2016  # a literal profile line, not an expression to expand here
printf 'eval "%s"\n' '$(/opt/homebrew/bin/brew shellenv)' > "$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --yes --dir "$D/claude-computer" > "$D/out" 2>&1
check_exit 0 $?
contains "$D/out" "✓ Xcode Command Line Tools"
contains "$D/out" "✓ Homebrew"
contains "$D/out" "✓ gh is logged in as octocat"
contains "$D/out" "✓ Claude Code"
contains "$D/out" "✓ git identity: A Person <you@example.com>"
contains "$D/out" "already loads brew"
contains "$D/out" "already installed — not adding a second copy"
assert_no_mutation "$CC_STUB_LOG"

# --------------------------------------------------------------------------
banner "(iii) brew installed but not on PATH"
D="$WORK/iii"; mkdir -p "$D/bin" "$D/offpath"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
stub_brew "$D/offpath" no        # the binary exists, but $D/offpath is not on PATH
stub_gh "$D/bin" yes no
base_env
export CC_INSTALL_TEST_BREW_PREFIXES="$D/offpath/brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --yes --dir "$D/claude-computer" > "$D/out" 2>&1
check_exit 0 $?
contains "$D/out" "installed but not on your PATH"
contains "$D/out" "Adding the line Homebrew asks for"
contains "$D/out" "$D/offpath/brew shellenv"
if [ -e "$D/zprofile" ]; then bad "dry run wrote the zprofile"; else ok "left the zprofile alone"; fi
assert_no_mutation "$CC_STUB_LOG"

# --------------------------------------------------------------------------
banner "(iv) an existing clone at --dir"
D="$WORK/iv"; mkdir -p "$D/bin"
CLONE="$D/claude-computer"
mkdir -p "$CLONE/.git" "$CLONE/docs"
echo "# claude-computer" > "$CLONE/CLAUDE.md"
: > "$CLONE/.template"
cat > "$CLONE/docs/FIRST-PROMPT.md" <<'EOF'
# The first prompt

```text
You are the operator for this computer.
```
EOF
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
stub_brew "$D/bin" yes
stub_gh "$D/bin" yes yes
stub "$D/bin" claude <<'EOF'
exit 0
EOF
base_env
export CC_INSTALL_TEST_BREW_PREFIXES="$D/bin/brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --yes --dir "$CLONE" > "$D/out" 2>&1
check_exit 0 $?
contains "$D/out" "is already a claude-computer clone"
contains "$D/out" "nothing to create"
contains "$D/out" "already there — skipping"
contains "$D/out" "| pbcopy"
absent   "$D/out" "gh repo create"
assert_no_mutation "$CC_STUB_LOG"

# --------------------------------------------------------------------------
banner "(v) stdin is not a terminal"
D="$WORK/v"; mkdir -p "$D/bin"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_no_clt "$D/bin"; stub_pbcopy "$D/bin"
base_env
export CC_INSTALL_TEST_BREW_PREFIXES="$D/no-brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
unset CC_INSTALL_TEST_TTY

# A real run refuses: the Homebrew installer and gh auth login both need the terminal.
"$INSTALL" --yes < /dev/null > "$D/out" 2>&1
check_exit 2 $?
contains "$D/out" "no terminal on stdin"
contains "$D/out" "the pipe takes the terminal away"

# A dry run changes nothing and asks nothing, so it does not need one.
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --dir "$D/cc" < /dev/null > "$D/dry" 2>&1
check_exit 0 $?
contains "$D/dry" "Fine for --dry-run; a real run needs one"
contains "$D/dry" "5/5 Your copy of the template"
absent   "$D/dry" "no terminal on stdin."
assert_no_mutation "$CC_STUB_LOG"
export CC_INSTALL_TEST_TTY=1

# --help must still work with no terminal, or nobody can read it from a pipe.
"$INSTALL" --help < /dev/null > "$D/help" 2>&1
check_exit 0 $?
contains "$D/help" "--public-clone"
contains "$D/help" "CC_INSTALL_TEMPLATE"

# --------------------------------------------------------------------------
banner "(vi) Linux"
D="$WORK/vi"; mkdir -p "$D/bin"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub "$D/bin" uname <<'EOF'
echo Linux
EOF
base_env
unset CC_INSTALL_TEST_UNAME_S          # let the uname stub answer, as a real Linux box would
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --yes > "$D/out" 2>&1
check_exit 3 $?
contains "$D/out" "macOS only"
contains "$D/out" "managed from a Mac over SSH"
export CC_INSTALL_TEST_UNAME_S=Darwin

# --------------------------------------------------------------------------
banner "(vii) bad arguments"
D="$WORK/vii"; mkdir -p "$D"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
base_env
"$INSTALL" --nonsense > "$D/out" 2>&1
check_exit 2 $?
"$INSTALL" --dir > "$D/out2" 2>&1
check_exit 2 $?
contains "$D/out2" "--dir needs a path"

# --------------------------------------------------------------------------
# The handover copies the repo's own first prompt, so the extraction has to match the
# real file, not a fixture. This is the same awk the installer runs.
banner "(viii) the first prompt extracts from the real docs/FIRST-PROMPT.md"
EXTRACT="$(awk '
  /^```text$/ { if (!seen) { seen = 1; inb = 1; next } }
  inb && /^```/ { exit }
  inb { print }
' docs/FIRST-PROMPT.md)"
if [ -n "$EXTRACT" ]; then ok "the first fenced text block is not empty"; else bad "extracted nothing"; fi
case "$EXTRACT" in
  "You are the operator for this computer"*) ok "it starts with the handover line" ;;
  *) bad "the first block is not the first prompt: ${EXTRACT%%$'\n'*}" ;;
esac
case "$EXTRACT" in
  *'```'*) bad "the extraction swallowed a fence" ;;
  *) ok "no fence in the extracted text" ;;
esac

# --------------------------------------------------------------------------
# A stale developer path: `xcode-select -p` answers, but the directory it names holds no
# real git. install.sh must decide the tools are missing from the filesystem alone and never
# run the shim to find out.
banner "(ix) a stale developer path never touches the shim"
D="$WORK/ix"; mkdir -p "$D/bin" "$D/stale"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_pbcopy "$D/bin"
stub "$D/bin" xcode-select <<EOF
case "\$1" in -p) echo "$D/stale"; exit 0 ;; esac
exit 0
EOF
stub "$D/bin" git <<'EOF'
exit 0
EOF
stub "$D/bin" clang <<'EOF'
exit 0
EOF
base_env
export CC_INSTALL_TEST_BREW_PREFIXES="$D/no-brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --dir "$D/claude-computer" > "$D/out" 2>&1
check_exit 0 $?
contains "$D/out" "the path is set but git or clang is broken"
contains "$D/out" "git identity — checked once the Command Line Tools are in"
assert_no_shim_invoked "$CC_STUB_LOG"
assert_no_mutation "$CC_STUB_LOG"

# --------------------------------------------------------------------------
# The rest of the cases are NOT dry runs: they exercise the post-clone wait, which only
# happens for real. Every command still goes to a stub, and `sleep` is a stub too, so the
# 60-second poll costs nothing here.
#
# stub_race <bindir> <clonedir> <populate-at-nth-fetch | never>
stub_race() {
  local d="$1" clone="$2" at="$3"
  stub "$d" sleep <<'EOF'
exit 0
EOF
  stub "$d" gh <<EOF
case "\$*" in
  "auth status") exit 0 ;;
  "api user --jq .login") echo octocat; exit 0 ;;
  *--json*)
    # Once repo-create has run, the repo exists whatever CC_TEST_REMOTE said beforehand.
    # (No backticks in this heredoc: it expands, so they would be command substitution.)
    [ -f "$D/created" ] || [ "\${CC_TEST_REMOTE:-no}" = yes ] || exit 1
    printf '%s\\n' "\$CC_TEST_REPO_FACTS"; exit 0 ;;
  "repo view "*) [ "\${CC_TEST_REMOTE:-no}" = yes ] && exit 0 || exit 1 ;;
  "repo create "*) : > "$D/created"; exit 0 ;;
  "repo clone "*)
    # What a clone of a repo GitHub has not populated yet leaves behind: origin is set,
    # there are no commits, and the work tree is empty.
    mkdir -p "$clone/.git"
    echo '[remote "origin"]' > "$clone/.git/config"
    echo '	url = https://github.com/octocat/claude-computer.git' >> "$clone/.git/config"
    exit 0 ;;
esac
exit 0
EOF
  stub "$d" git <<EOF
populate() {
  echo '# claude-computer' > "$clone/CLAUDE.md"
  mkdir -p "$clone/docs"
  printf '# p\\n\\n\`\`\`text\\nYou are the operator for this computer.\\n\`\`\`\\n' > "$clone/docs/FIRST-PROMPT.md"
  : > "$clone/.template"
}
case "\$*" in
  *--version*) echo "git version 2.48.0"; exit 0 ;;
  *"config --global user.name"*)  echo "A Person"; exit 0 ;;
  *"config --global user.email"*) echo "you@example.com"; exit 0 ;;
  *fetch*)
    n=\$(cat "$D/polls" 2>/dev/null || echo 0)
    n=\$((n + 1)); echo "\$n" > "$D/polls"
    if [ "$at" != never ] && [ "\$n" -ge "$at" ]; then populate; fi
    exit 0 ;;
esac
exit 0
EOF
}

banner "(x) the template copy lands on the third poll"
D="$WORK/x"; mkdir -p "$D/bin" "$D/dev/usr/bin"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
stub_brew "$D/bin" yes
stub "$D/bin" claude <<'EOF'
exit 0
EOF
stub_race "$D/bin" "$D/cc" 3
base_env
export CC_TEST_REMOTE=no
export CC_INSTALL_TEST_BREW_PREFIXES="$D/bin/brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
# shellcheck disable=SC2016  # a literal profile line, not an expression to expand here
printf 'eval "%s"\n' '$(/opt/homebrew/bin/brew shellenv)' > "$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --yes --dir "$D/cc" > "$D/out" 2>&1
check_exit 0 $?
contains "$D/out" "Waiting for GitHub to finish copying the template"
contains "$D/out" "the copy arrived"
contains "$D/out" "CLAUDE.md, docs/FIRST-PROMPT.md and .template are all there"
if [ "$(cat "$D/polls")" = 3 ]; then ok "polled three times"; else bad "polled $(cat "$D/polls") times, wanted 3"; fi

banner "(xi) the template copy never lands"
D="$WORK/xi"; mkdir -p "$D/bin" "$D/dev/usr/bin"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
stub_brew "$D/bin" yes
stub "$D/bin" claude <<'EOF'
exit 0
EOF
stub_race "$D/bin" "$D/cc" never
base_env
export CC_TEST_REMOTE=no
export CC_INSTALL_TEST_BREW_PREFIXES="$D/bin/brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
# shellcheck disable=SC2016  # a literal profile line, not an expression to expand here
printf 'eval "%s"\n' '$(/opt/homebrew/bin/brew shellenv)' > "$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --yes --dir "$D/cc" > "$D/out" 2>&1
check_exit 1 $?
contains "$D/out" "has not finished copying the template"
contains "$D/out" "re-running is safe"
contains "$D/out" "already exists → clone"
absent   "$D/out" "it is not a copy of"

banner "(xii) resuming the empty clone that (xi) left behind"
D="$WORK/xii"; mkdir -p "$D/bin" "$D/dev/usr/bin" "$D/cc/.git"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
# Exactly what a given-up run leaves: origin set to our repo, no CLAUDE.md.
echo '[remote "origin"]' > "$D/cc/.git/config"
printf '\turl = https://github.com/octocat/claude-computer.git\n' >> "$D/cc/.git/config"
stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
stub_brew "$D/bin" yes
stub "$D/bin" claude <<'EOF'
exit 0
EOF
stub_race "$D/bin" "$D/cc" 1
base_env
export CC_TEST_REMOTE=yes
export CC_INSTALL_TEST_BREW_PREFIXES="$D/bin/brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
# shellcheck disable=SC2016  # a literal profile line, not an expression to expand here
printf 'eval "%s"\n' '$(/opt/homebrew/bin/brew shellenv)' > "$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --yes --dir "$D/cc" > "$D/out" 2>&1
check_exit 0 $?
contains "$D/out" "GitHub had not finished filling — resuming it"
contains "$D/out" "Finishing the clone at"
log_lacks "$CC_STUB_LOG" "gh repo create"
log_lacks "$CC_STUB_LOG" "gh repo clone"
unset CC_TEST_REMOTE

# --------------------------------------------------------------------------
# A bare `gh repo view <name>` inside another git repo can resolve against that repo's
# remote instead of the account, so the slug must carry the owner once it is known.
banner "(xiii) gh is owner-qualified once the account is known"
D="$WORK/xiii"; mkdir -p "$D/bin" "$D/dev/usr/bin"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
stub_brew "$D/bin" yes
stub_gh "$D/bin" yes no
stub "$D/bin" claude <<'EOF'
exit 0
EOF
base_env
export CC_INSTALL_TEST_BREW_PREFIXES="$D/bin/brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --yes --dir "$D/cc" > "$D/out" 2>&1
check_exit 0 $?
if grep -q "^gh repo view octocat/claude-computer\$" "$CC_STUB_LOG"; then
  ok "asked gh for octocat/claude-computer, not a bare name"
else
  bad "gh repo view was not owner-qualified: $(grep '^gh repo view' "$CC_STUB_LOG" || echo none)"
fi

# --------------------------------------------------------------------------
# A repo of the right name is not necessarily an instance. On the template owner's account
# `claude-computer` IS the template; on a contributor's it is most likely a public fork.
# Cloning either as the fleet brain would put a map of the user's machines in a public repo.
#
# suitability_case <label> <facts> <want-exit> <needle>
suitability_case() {
  local label="$1" f="$2" want="$3" needle="$4"
  banner "(xiv.$label)"
  D="$WORK/s$label"; mkdir -p "$D/bin" "$D/dev/usr/bin"
  export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
  stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
  stub_brew "$D/bin" yes
  stub_gh "$D/bin" yes yes
  stub "$D/bin" claude <<'EOF'
exit 0
EOF
  base_env
  export CC_TEST_REPO_FACTS="$f"
  export CC_INSTALL_TEST_BREW_PREFIXES="$D/bin/brew"
  export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
  export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
  PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --yes --dir "$D/cc" > "$D/out" 2>&1
  check_exit "$want" $?
  contains "$D/out" "$needle"
  # Whatever the verdict, a refusal happens before anything is touched.
  assert_no_mutation "$CC_STUB_LOG"
}

# (a) the template itself, or any template repo
suitability_case a "$(facts true false true)" 6 "is a template repository, not an instance"
contains "$D/out" "--name my-claude-computer"

# (b) a public fork of the template — the contributor's trap
suitability_case b "$(facts false true false narendranag/claude-computer)" 6 "is public."
contains "$D/out" "public fork of narendranag/claude-computer"
contains "$D/out" "gh repo edit"

# (b2) public and not a fork is refused just the same
suitability_case b2 "$(facts false false false)" 6 "is public."

# (c) a private fork is a legitimate instance
suitability_case c "$(facts true true false narendranag/claude-computer)" 0 "it is a private fork of narendranag/claude-computer"

# the happy case: private, not a fork, not a template
suitability_case d "$(facts true false false)" 0 "it is private and not a template"

# gh could not answer: warn, do not block
suitability_case e "" 0 "could not read whether"

# --------------------------------------------------------------------------
# An existing local clone whose origin is public is warned about, not blocked: /setup and the
# Stop hook have their own guard, and refusing would strand a machine that is otherwise set up.
banner "(xv) an existing clone with a public origin warns but does not block"
D="$WORK/xv"; mkdir -p "$D/bin" "$D/dev/usr/bin"
CLONE="$D/cc"; mkdir -p "$CLONE/.git" "$CLONE/docs"
echo "# claude-computer" > "$CLONE/CLAUDE.md"
: > "$CLONE/.template"
# shellcheck disable=SC2016  # a literal fenced block, not an expression
printf '# p\n\n```text\nYou are the operator for this computer.\n```\n' > "$CLONE/docs/FIRST-PROMPT.md"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
stub_brew "$D/bin" yes
stub_gh "$D/bin" yes yes
stub "$D/bin" claude <<'EOF'
exit 0
EOF
base_env
CC_TEST_REPO_FACTS="$(facts false false false)"; export CC_TEST_REPO_FACTS
export CC_INSTALL_TEST_BREW_PREFIXES="$D/bin/brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --yes --dir "$CLONE" > "$D/out" 2>&1
check_exit 0 $?
contains "$D/out" "which is PUBLIC"
absent   "$D/out" "is public."

# --------------------------------------------------------------------------
# Resuming a half-filled clone still means filling it from a remote, so the remote still has
# to be an instance.
banner "(xvi) resuming refuses a public remote"
D="$WORK/xvi"; mkdir -p "$D/bin" "$D/dev/usr/bin" "$D/cc/.git"
echo '[remote "origin"]' > "$D/cc/.git/config"
printf '\turl = https://github.com/octocat/claude-computer.git\n' >> "$D/cc/.git/config"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
stub_brew "$D/bin" yes
stub_gh "$D/bin" yes yes
stub "$D/bin" claude <<'EOF'
exit 0
EOF
base_env
CC_TEST_REPO_FACTS="$(facts false false false)"; export CC_TEST_REPO_FACTS
export CC_INSTALL_TEST_BREW_PREFIXES="$D/bin/brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --dry-run --yes --dir "$D/cc" > "$D/out" 2>&1
check_exit 6 $?
contains "$D/out" "is public."
assert_no_mutation "$CC_STUB_LOG"

# --------------------------------------------------------------------------
# Belt and braces: whatever gh reports after `repo create`, a non-private result stops before
# a machine map is written into it.
banner "(xvii) a freshly created repo that is not private stops at exit 6"
D="$WORK/xvii"; mkdir -p "$D/bin" "$D/dev/usr/bin"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_clt "$D/bin" "$D/dev"; stub_pbcopy "$D/bin"
stub_brew "$D/bin" yes
stub "$D/bin" claude <<'EOF'
exit 0
EOF
stub_race "$D/bin" "$D/cc" 1
base_env
export CC_TEST_REMOTE=no
CC_TEST_REPO_FACTS="$(facts false false false)"; export CC_TEST_REPO_FACTS
export CC_INSTALL_TEST_BREW_PREFIXES="$D/bin/brew"
export CC_INSTALL_TEST_CLAUDE_NATIVE="$D/no-claude"
export CC_INSTALL_TEST_ZPROFILE="$D/zprofile"
# shellcheck disable=SC2016  # a literal profile line, not an expression to expand here
printf 'eval "%s"\n' '$(/opt/homebrew/bin/brew shellenv)' > "$D/zprofile"
PATH="$D/bin:/usr/bin:/bin" "$INSTALL" --yes --dir "$D/cc" > "$D/out" 2>&1
check_exit 6 $?
contains "$D/out" "was created but is not private"
contains "$D/out" "gh repo edit"
log_lacks "$CC_STUB_LOG" "gh repo clone"
unset CC_TEST_REMOTE

# --------------------------------------------------------------------------
printf '\n%s\n' "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
