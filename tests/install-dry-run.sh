#!/usr/bin/env bash
# tests/install-dry-run.sh — drive install.sh through six simulated machines, in --dry-run.
#
# Usage: ./tests/install-dry-run.sh
#
# Every case builds a temporary PATH of stub executables and points the installer's
# CC_INSTALL_TEST_* probes at temporary files, so nothing on the real machine is read or
# written. Each stub appends its own invocation to $CC_STUB_LOG, which lets the last
# assertion in each case be the important one: in --dry-run, no mutating command ran.
#
# Cases: (i) nothing installed · (ii) everything installed and authed · (iii) brew present
# but not on PATH · (iv) an existing clone at --dir · (v) stdin is not a terminal ·
# (vi) Linux · (vii) bad arguments · (viii) the first prompt extracts from the real
# docs/FIRST-PROMPT.md.
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

stub_clt() {
  local d="$1"
  stub "$d" xcode-select <<'EOF'
case "$1" in
  -p) echo /Library/Developer/CommandLineTools; exit 0 ;;
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
stub_gh() {
  local d="$1" authed="$2" remote="$3"
  stub "$d" gh <<EOF
case "\$*" in
  "auth status")        [ "$authed" = yes ] && exit 0 || exit 1 ;;
  "api user --jq .login") [ "$authed" = yes ] && { echo octocat; exit 0; }; exit 1 ;;
  "repo view "*)        [ "$remote" = yes ] && exit 0 || exit 1 ;;
esac
exit 0
EOF
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
assert_no_mutation "$CC_STUB_LOG"

# --------------------------------------------------------------------------
banner "(ii) everything installed and authed"
D="$WORK/ii"; mkdir -p "$D/bin"
export CC_STUB_LOG="$D/log"; : > "$CC_STUB_LOG"
stub_clt "$D/bin"; stub_pbcopy "$D/bin"
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
stub_clt "$D/bin"; stub_pbcopy "$D/bin"
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
stub_clt "$D/bin"; stub_pbcopy "$D/bin"
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
base_env
unset CC_INSTALL_TEST_TTY
"$INSTALL" --dry-run < /dev/null > "$D/out" 2>&1
check_exit 2 $?
contains "$D/out" "no terminal on stdin"
contains "$D/out" "the pipe takes the terminal away"
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
printf '\n%s\n' "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
