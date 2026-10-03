#!/usr/bin/env bash
# tests/setup-tools-dry-run.sh — drive setup-tools.sh --only vscode and --only agent-reach with stubs.
#
# Usage: ./tests/setup-tools-dry-run.sh
#
# setup-tools.sh cds into its own directory and reads the real vscode-extensions.txt, so
# these cases run against the real list — only `code` is stubbed, and it is the only
# executable that could mutate anything (an install). Everything else on PATH is a
# hermetic $SYSBIN.
#
# Cases: (i) --dry-run prints the command that would run for each extension not already
# installed, and a "N already installed" summary, and never calls --install-extension ·
# (ii) a real (stubbed) run with one failing extension prints a per-extension result, a
# final summary, and exits non-zero · (iii) --only agent-reach --dry-run prints the pinned
# commit install and the zero-config `install --system`, with no --channels, and runs
# nothing · (iv) without npm or mise the step fails before installing anything.
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/setup-tools.sh"
[ -x "$SCRIPT" ] || { echo "setup-tools.sh is not executable" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cc-setup-tools-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

SYSBIN="$WORK/sysbin"
mkdir -p "$SYSBIN"
SYS_TOOLS="sh bash env cat mkdir rm chmod mktemp printf tr grep sed awk cut head tail
sort uniq wc dirname basename id uname test true false expr"
for t in $SYS_TOOLS; do
  p="$(command -v "$t" 2>/dev/null)"
  case "$p" in
    /*) ln -sf "$p" "$SYSBIN/$t" ;;
    ?*) : ;;
    *)  printf 'tests/setup-tools-dry-run.sh: required system tool not found: %s\n' "$t" >&2; exit 1 ;;
  esac
done
unset t p

ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "output has no '$2'"; fi; }
log_lacks() { if grep -qF -- "$2" "$1"; then bad "IT RAN: '$2'"; else ok "did not run: $2"; fi; }

stub() {
  local d="$1" n="$2"
  mkdir -p "$d"
  {
    echo '#!/bin/sh'
    # shellcheck disable=SC2016
    printf 'printf %s %s >> "$CC_STUB_LOG"\n' "'%s %s\\n'" "'$n' \"\$*\""
    cat
  } > "$d/$n"
  chmod +x "$d/$n"
}

# code: --list-extensions answers with two real ids from vscode-extensions.txt already
# "installed"; --install-extension succeeds, except for one id when CC_TEST_FAIL_EXT is set.
stub_code() {
  stub "$1" code <<'EOF'
case "$1" in
  --list-extensions) printf 'ms-python.python\neamodio.gitlens\n' ;;
  --install-extension)
    [ -n "${CC_TEST_FAIL_EXT:-}" ] && [ "$2" = "$CC_TEST_FAIL_EXT" ] && exit 1
    exit 0 ;;
esac
EOF
}

n=0
case_new() {
  n=$((n + 1))
  printf '\n(%s) %s\n' "$n" "$1"
  CASE="$WORK/case$n"
  BIN="$CASE/bin"
  OUT="$CASE/out.txt"
  LOG="$CASE/stub.log"
  mkdir -p "$BIN"
  : > "$LOG"
  stub_code "$BIN"
}

run() {
  ( PATH="$BIN:$SYSBIN" CC_STUB_LOG="$LOG" CC_TEST_FAIL_EXT="${CC_TEST_FAIL_EXT:-}" \
    "$SCRIPT" "$@" ) > "$OUT" 2>&1
  rc=$?
}

# =========================================================================
case_new "--dry-run: prints would-run commands, an already-installed summary, installs nothing"
run --dry-run --only vscode
check_exit 0 "$rc"
contains "$OUT" "code --install-extension anthropic.claude-code"
contains "$OUT" "code --install-extension biomejs.biome"
contains "$OUT" "2 already installed"
log_lacks "$LOG" "--install-extension"

# =========================================================================
case_new "a real (stubbed) run: per-extension result, final summary, non-zero on a failed install"
CC_TEST_FAIL_EXT="biomejs.biome"
run --only vscode
check_exit 1 "$rc"
contains "$OUT" "installed: anthropic.claude-code"
contains "$OUT" "failed: biomejs.biome"
contains "$LOG" "code --install-extension biomejs.biome"
contains "$OUT" "failed, 2 already installed"

# =========================================================================
case_new "agent-reach --dry-run: pinned commit, zero-config install, nothing runs"
stub "$BIN" uv < /dev/null
stub "$BIN" npm < /dev/null
run --dry-run --only agent-reach
check_exit 0 "$rc"
pin="$(sed -n 's/^AGENT_REACH_COMMIT="\([0-9a-f]*\)".*/\1/p' "$SCRIPT")"
if [ "${#pin}" -eq 40 ]; then ok "pin is a full commit: $pin"; else bad "AGENT_REACH_COMMIT is not a 40-character commit: '$pin'"; fi
contains "$OUT" "uv tool install --force https://github.com/Panniantong/agent-reach/archive/$pin.zip"
contains "$OUT" "mkdir -p $HOME/.claude/skills"
contains "$OUT" "uv tool install yt-dlp[default]"
contains "$OUT" "agent-reach install --env=auto --system"
if grep -qF -- "--channels" "$OUT"; then bad "dry run passes --channels"; else ok "no --channels"; fi
if grep -qF -- "archive/main" "$OUT"; then bad "installs from main"; else ok "never installs from main"; fi
log_lacks "$LOG" "uv tool install"

# =========================================================================
case_new "agent-reach without npm or mise: fails before installing anything"
stub "$BIN" uv < /dev/null
run --only agent-reach
check_exit 1 "$rc"
contains "$OUT" "npm missing"
log_lacks "$LOG" "uv tool install"

# =========================================================================
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
