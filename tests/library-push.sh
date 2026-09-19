#!/usr/bin/env bash
# tests/library-push.sh — drive bin/library-push with a stubbed rclone and bw.
#
# Usage: ./tests/library-push.sh
#
# Every case gets its own temporary HOME, library and PATH of stub executables over a
# hermetic $SYSBIN, so nothing outside the temporary directory is read or touched and no
# real rclone or Bitwarden call is ever made. `rclone` and `bw` are stubs; each logs its
# own invocation to $CC_STUB_LOG.
#
# Cases: (i) neither books nor comics exists: exit 0, message, rclone never runs ·
# (ii) --dry-run with books only: rclone gets `copy --dry-run`, never `sync`, no credential
# in any logged argv, and nothing under the fake R2 remote gets created · (iii) a real run
# with both directories: push then verify for each, exit 0 · (iv) a failing `rclone check`
# fails the whole run.
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/library-push"
[ -x "$SCRIPT" ] || { echo "bin/library-push is not executable" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cc-library-push-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

# ---- the hermetic system PATH ---------------------------------------------
SYSBIN="$WORK/sysbin"
mkdir -p "$SYSBIN"

SYS_TOOLS="sh bash env cat ls mkdir rmdir rm cp mv chmod touch mktemp date jq
awk sed grep cut tr head tail sort uniq wc stat find dirname basename
id uname printf test true false expr"

for t in $SYS_TOOLS; do
  p="$(command -v "$t" 2>/dev/null)"
  case "$p" in
    /*) ln -sf "$p" "$SYSBIN/$t" ;;
    ?*) : ;;   # a shell builtin: always there, nothing to link
    *)  printf 'tests/library-push.sh: required system tool not found: %s\n' "$t" >&2; exit 1 ;;
  esac
done
unset t p

ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }

check_exit() { # check_exit <want> <got>
  if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi
}
contains() { # contains <file> <needle>
  if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "output has no '$2'"; fi
}
log_lacks() { # log_lacks <logfile> <needle>
  if grep -qF -- "$2" "$1"; then bad "IT RAN: '$2'"; else ok "did not run: $2"; fi
}

# stub <dir> <name>, body on stdin. Every stub logs itself first.
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

# bw: answers status (always unlocked) and the four r2 fields the script reads.
stub_bw() {
  stub "$1" bw <<'EOF'
case "$*" in
  status)               echo '{"status":"unlocked"}' ;;
  "get password "*r2-crypt*) echo "fake-crypt-password" ;;
  "get password "*r2*)  echo "fake-secret-access-key" ;;
  "get username "*r2*)  echo "fake-access-key-id" ;;
  "get item "*r2*)
    echo '{"fields":[{"name":"endpoint","value":"https://fake.example/r2"},{"name":"bucket","value":"fake-bucket"}]}' ;;
  *) exit 1 ;;
esac
exit 0
EOF
}

# rclone: logs its own argv (already done by `stub`) and only ever succeeds, unless
# CC_TEST_CHECK_FAILS is set, in which case `rclone check` fails.
stub_rclone() {
  stub "$1" rclone <<'EOF'
case "$1" in
  check) [ -n "${CC_TEST_CHECK_FAILS:-}" ] && exit 1 ;;
esac
exit 0
EOF
}

# ---- one case ------------------------------------------------------------
n=0
case_new() {
  n=$((n + 1))
  printf '\n(%s) %s\n' "$n" "$1"
  CASE="$WORK/case$n"
  BIN="$CASE/bin"
  HOME="$CASE/home"
  LIB="$HOME/library"
  OUT="$CASE/out.txt"
  LOG="$CASE/stub.log"
  mkdir -p "$BIN" "$HOME" "$LIB"
  : > "$LOG"
  stub_bw "$BIN"
  stub_rclone "$BIN"
}

run() { # run [args…] — library-push in this case's world; exit status in $rc
  ( PATH="$BIN:$SYSBIN" \
    HOME="$HOME" \
    CC_LIBRARY="$LIB" \
    CC_STUB_LOG="$LOG" \
    CC_TEST_CHECK_FAILS="${CC_TEST_CHECK_FAILS:-}" \
    "$SCRIPT" "$@" ) > "$OUT" 2>&1
  rc=$?
}

# =========================================================================
case_new "neither books nor comics exists: exit 0, message, rclone never runs"
run
check_exit 0 "$rc"
contains "$OUT" "no $LIB/books here, skipping"
contains "$OUT" "no $LIB/comics here, skipping"
log_lacks "$LOG" "rclone"
log_lacks "$LOG" "bw "

# =========================================================================
case_new "--dry-run with books only: copy --dry-run, never sync, no credential in argv"
mkdir -p "$LIB/books"
run --dry-run
check_exit 0 "$rc"
contains "$LOG" "rclone copy --dry-run"
log_lacks "$LOG" "sync"
log_lacks "$LOG" "fake-secret-access-key"
log_lacks "$LOG" "fake-access-key-id"
log_lacks "$LOG" "fake-crypt-password"
log_lacks "$OUT" "fake-secret-access-key"

# =========================================================================
case_new "real run with both directories: push then verify each, exit 0"
mkdir -p "$LIB/books" "$LIB/comics"
run
check_exit 0 "$rc"
contains "$LOG" "rclone copy --checksum"
contains "$LOG" "rclone check --one-way"
contains "$OUT" "library-push books: verified"
contains "$OUT" "library-push comics: verified"
log_lacks "$LOG" "sync"

# =========================================================================
case_new "a failing rclone check fails the whole run"
mkdir -p "$LIB/books"
CC_TEST_CHECK_FAILS=1
run
check_exit 1 "$rc"
contains "$OUT" "verify failed: books"

# =========================================================================
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
