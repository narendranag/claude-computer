#!/usr/bin/env bash
# tests/new-client.sh — drive bin/new-client against temporary client folders.
#
# Usage: ./tests/new-client.sh
#
# Every case gets its own temporary --dir. git is real, because the point is that a client folder
# really becomes a repo with brief/ tracked. `gh` and `gitleaks` are stubs that log their calls:
# no case reaches the network, and gitleaks passes so the pre-commit hook can run.
#
# Cases: (1) --dry-run on a new client changes nothing · (2) a new client gets the template,
# __NAME__ substituted, brief/ tracked, one commit · (3) adopting an existing folder keeps its
# files, tracks brief/, and ignores a code repo inside it · (4) a folder that is already a repo is
# refused · (5) a file over the size limit is refused before anything is written · (6) the remote
# is created private, named client-<lowercased name>.
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/new-client"
[ -x "$SCRIPT" ] || { echo "bin/new-client is not executable" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cc-new-client-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_GLOBAL=/dev/null

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
lacks() { if grep -qF -- "$2" "$1"; then bad "$(basename "$1") has '$2'"; else ok "no: $2"; fi; }
exists() { if [ -e "$1" ]; then ok "exists: ${1#"$CASE"/}"; else bad "missing: ${1#"$CASE"/}"; fi; }
absent() { if [ -e "$1" ]; then bad "should not exist: ${1#"$CASE"/}"; else ok "absent: ${1#"$CASE"/}"; fi; }
tracked() { if git -C "$1" ls-files --error-unmatch "$2" >/dev/null 2>&1; then ok "tracked: $2"; else bad "not tracked: $2"; fi; }
untracked() { if git -C "$1" ls-files --error-unmatch "$2" >/dev/null 2>&1; then bad "tracked: $2"; else ok "not tracked: $2"; fi; }

n=0
case_new() {
  n=$((n + 1))
  printf '\n(%s) %s\n' "$n" "$1"
  CASE="$WORK/case$n"
  BIN="$CASE/bin"
  CLIENTS="$CASE/clients"
  OUT="$CASE/out.txt"
  LOG="$CASE/stub.log"
  mkdir -p "$BIN" "$CLIENTS"
  : > "$LOG"
  for s in gh gitleaks; do
    printf '#!/bin/sh\nprintf "%%s %%s\\n" %s "$*" >> "%s"\nexit 0\n' "$s" "$LOG" > "$BIN/$s"
    chmod +x "$BIN/$s"
  done
}
run() {
  ( PATH="$BIN:$PATH" CC_MAX_FILE_MB="${CC_MAX_FILE_MB:-95}" "$SCRIPT" "$@" --dir "$CLIENTS" ) > "$OUT" 2>&1 </dev/null
  rc=$?
}

# =========================================================================
case_new "--dry-run on a new client changes nothing"
run acme --dry-run
check_exit 0 "$rc"
contains "$OUT" "new: $CLIENTS/acme"
contains "$OUT" "client-acme (private)"
absent "$CLIENTS/acme"
lacks "$LOG" "gh repo create"

# =========================================================================
case_new "a new client: template, name substituted, brief/ tracked, one commit"
run acme --no-remote
check_exit 0 "$rc"
D="$CLIENTS/acme"
exists "$D/.git"
exists "$D/.git/hooks/pre-commit"
contains "$D/CLAUDE.md" "# acme"
lacks "$D/CLAUDE.md" "__NAME__"
tracked "$D" "brief/.gitkeep"
tracked "$D" "TASKS.md"
if [ "$(git -C "$D" rev-list --count HEAD)" = 1 ]; then ok "one commit"; else bad "want one commit"; fi
contains "$LOG" "gitleaks"
lacks "$LOG" "gh repo create"

# =========================================================================
case_new "adopt an existing folder: files kept, brief/ tracked, inner repo ignored"
D="$CLIENTS/Northwind"
mkdir -p "$D/brief" "$D/northwind-app/src"
printf 'my own notes\n' > "$D/CLAUDE.md"
printf 'analysis\n' > "$D/analysis.md"
printf 'the deck\n' > "$D/brief/deck.pdf"
printf 'code\n' > "$D/northwind-app/src/main.py"
git -C "$D/northwind-app" init -q -b main
run Northwind --no-remote
check_exit 0 "$rc"
contains "$OUT" "adopt: $D"
contains "$OUT" "ignore the repo inside it: northwind-app/"
contains "$D/CLAUDE.md" "my own notes"
lacks "$D/CLAUDE.md" "new-client replaces this stub"
tracked "$D" "brief/deck.pdf"
tracked "$D" "analysis.md"
tracked "$D" "TASKS.md"
untracked "$D" "northwind-app/src/main.py"
absent "$D/brief/.gitkeep"
contains "$D/.gitignore" "/northwind-app/"
exists "$D/northwind-app/.git"

# =========================================================================
case_new "a folder that is already a git repo is refused"
mkdir -p "$CLIENTS/already" && git -C "$CLIENTS/already" init -q -b main
run already --no-remote
check_exit 2 "$rc"
contains "$OUT" "already a git repo"

# =========================================================================
case_new "a file over the size limit stops the commit; ignoring it lets a rerun through"
mkdir -p "$CLIENTS/big/brief"
dd if=/dev/zero of="$CLIENTS/big/brief/video.mov" bs=1024 count=2048 2>/dev/null
CC_MAX_FILE_MB=1 run big --no-remote
check_exit 2 "$rc"
contains "$OUT" "brief/video.mov"
absent "$CLIENTS/big/.git"
printf 'brief/video.mov\n' >> "$CLIENTS/big/.gitignore"
CC_MAX_FILE_MB=1 run big --no-remote
check_exit 0 "$rc"
untracked "$CLIENTS/big" "brief/video.mov"
if [ "$(grep -cxF '# --- claude-computer template: client ---' "$CLIENTS/big/.gitignore")" = 1 ]; then ok "template .gitignore appended once across two runs"; else bad "template .gitignore appended twice"; fi

# =========================================================================
case_new "the remote is private and named client-<lowercased name>"
mkdir -p "$CLIENTS/BlueHarbor"
printf 'notes\n' > "$CLIENTS/BlueHarbor/notes.md"
run BlueHarbor
check_exit 0 "$rc"
contains "$LOG" "gh repo create client-blueharbor --private"

# =========================================================================
case_new "repos with spaces in their names, and repos nested deep, are ignored — never committed"
D="$CLIENTS/Deep"
mkdir -p "$D/My App" "$D/work/2024/q1/site"
printf 'x\n' > "$D/My App/a.txt"; printf 'y\n' > "$D/work/2024/q1/site/b.txt"; printf 'notes\n' > "$D/notes.md"
git -C "$D/My App" init -q -b main
git -C "$D/work/2024/q1/site" init -q -b main && git -C "$D/work/2024/q1/site" add -A && git -C "$D/work/2024/q1/site" commit -q -m c
run Deep --no-remote
check_exit 0 "$rc"
contains "$D/.gitignore" "/My App/"
contains "$D/.gitignore" "/work/2024/q1/site/"
untracked "$D" "My App/a.txt"
if git -C "$D" ls-files -s | awk '$1 == "160000"' | grep -q .; then bad "a repo was committed as a submodule"; else ok "no submodules committed"; fi
tracked "$D" "notes.md"

# =========================================================================
case_new "a failed first commit removes the new .git, so a rerun starts clean"
mkdir -p "$CLIENTS/leaky" && printf 'doc\n' > "$CLIENTS/leaky/doc.md"
printf '#!/bin/sh\nexit 1\n' > "$BIN/gitleaks"
run leaky --no-remote
check_exit 1 "$rc"
contains "$OUT" ".git was removed"
absent "$CLIENTS/leaky/.git"

# =========================================================================
case_new "a GitHub failure keeps the commit and prints the command that finishes the job"
mkdir -p "$CLIENTS/offline" && printf 'doc\n' > "$CLIENTS/offline/doc.md"
printf '#!/bin/sh\nexit 1\n' > "$BIN/gh"
run offline
check_exit 1 "$rc"
contains "$OUT" "gh repo create client-offline --private --source"
exists "$CLIENTS/offline/.git"

# =========================================================================
case_new "a relative --dir works, including the GitHub step"
( cd "$CASE" && PATH="$BIN:$PATH" "$SCRIPT" rel --dir clients ) > "$OUT" 2>&1 </dev/null; rc=$?
check_exit 0 "$rc"
contains "$LOG" "/clients/rel --remote origin --push"
if grep -qF "clients/clients" "$LOG"; then bad "relative --dir doubled the path"; else ok "path not doubled"; fi

# =========================================================================
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
