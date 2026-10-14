#!/usr/bin/env bash
# tests/settings-build.sh — drive bin/settings-build against a throwaway base, overlay and output.
#
# Usage: ./tests/settings-build.sh
#
# Cases: (1) no overlay: the build is the base, written with a copy of the build beside it · (2) an
# overlay adds, removes, sets and unsets, and the build keeps the base's order · (3) an overlay may not
# remove a deny rule, an ask rule that guards secrets, or anything without a `why` · (4) --check: in
# step, an edit made in the output, a pending build, each said apart · (5) a build refuses to overwrite
# edits; --force discards them · (6) --adopt folds the output's edits into the overlay, without undoing a
# pending base change · (7) --adopt --from turns a whole file into an overlay that rebuilds it · (8) a
# link in the output's place is refused until --replace-link · (9) the shipped base and example overlay
# build cleanly
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/settings-build"
[ -x "$SCRIPT" ] || { echo "bin/settings-build is not executable" >&2; exit 1; }
command -v uv > /dev/null || { echo "uv is required (bin/settings-build is a uv script)" >&2; exit 1; }
command -v jq > /dev/null || { echo "jq is required" >&2; exit 1; }

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cc-settings-build-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
lacks() { if grep -qF -- "$2" "$1"; then bad "$(basename "$1") still has '$2'"; else ok "no: $2"; fi; }
is() { # is <jq filter> <file> <want>
  got="$(jq -c "$1" "$2")"
  if [ "$got" = "$3" ]; then ok "$1 = $3"; else bad "$1: want $3, got $got"; fi
}
banner() { printf '\n%s\n' "== $1"; }

export HOME="$WORK/home"
mkdir -p "$HOME/.claude"
B="$WORK/base.json" O="$WORK/overlay.json" OUT="$HOME/.claude/settings.json" LOG="$WORK/log"
run() { "$SCRIPT" --base "$B" --overlay "$O" --out "$OUT" "$@" > "$LOG" 2>&1; }

# On a cold cache uv prints "Installed n packages" to stderr; install the script's environment first.
"$SCRIPT" --help > /dev/null 2>&1

base() {
  cat > "$B" <<'EOF'
{
  "env": { "PAGER": "cat", "NO_COLOR": "1" },
  "permissions": {
    "defaultMode": "auto",
    "allow": ["Bash(ls:*)", "Bash(cat:*)"],
    "ask": ["Bash(git push:*)", "Bash(rm:*)", "Bash(secrets exec:*)"],
    "deny": ["Bash(sops decrypt:*)"]
  },
  "statusLine": { "type": "command", "command": "status.sh" }
}
EOF
}
fresh() { rm -f "$O" "$OUT" "$HOME/.claude/settings.built.json"; base; }

banner "(1) no overlay: the build is the base"
fresh
run; check_exit 0 $?
contains "$LOG" "wrote ~/.claude/settings.json"
is '.permissions.ask' "$OUT" '["Bash(git push:*)","Bash(rm:*)","Bash(secrets exec:*)"]'
if cmp -s "$OUT" "$HOME/.claude/settings.built.json"; then ok "copy of the build beside it"; else bad "no copy of the build"; fi
run; check_exit 0 $?
lacks "$LOG" "wrote"

banner "(2) add, remove, set, unset; the base's order kept"
fresh
cat > "$O" <<'EOF'
{ "set": { "theme": "dark", "env": { "EDITOR": "vi" }, "statusLine": { "command": "mine.sh" } },
  "unset": ["env.NO_COLOR"],
  "allow": { "add": ["Bash(git push:*)", "Bash(tree:*)"] },
  "ask": { "remove": [ { "rule": "Bash(git push:*)", "why": "I push my own branches" } ] },
  "deny": { "add": ["Read(**/.env)"] } }
EOF
run; check_exit 0 $?
is '.permissions.allow' "$OUT" '["Bash(ls:*)","Bash(cat:*)","Bash(git push:*)","Bash(tree:*)"]'
is '.permissions.ask' "$OUT" '["Bash(rm:*)","Bash(secrets exec:*)"]'
is '.permissions.deny' "$OUT" '["Bash(sops decrypt:*)","Read(**/.env)"]'
is '.env' "$OUT" '{"PAGER":"cat","EDITOR":"vi"}'
is '.statusLine' "$OUT" '{"type":"command","command":"mine.sh"}'
is '.theme' "$OUT" '"dark"'
printf '{ "allow": { "add": ["Bash(rm:*)"] } }\n' > "$O"
run --force; check_exit 0 $?
contains "$LOG" "allow Bash(rm:*) has no effect: ask still has it"

banner "(3) what an overlay may not remove"
fresh
printf '{ "deny": { "remove": [ { "rule": "Bash(sops decrypt:*)", "why": "x" } ] } }\n' > "$O"
run; check_exit 1 $?
contains "$LOG" "deny rules can't be removed"
printf '{ "ask": { "remove": [ { "rule": "Bash(secrets exec:*)", "why": "x" } ] } }\n' > "$O"
run; check_exit 1 $?
contains "$LOG" "guards secrets"
printf '{ "ask": { "remove": [ { "rule": "Bash(rm:*)" } ] } }\n' > "$O"
run; check_exit 2 $?
contains "$LOG" "has no \`why\`"
printf '{ "set": { "permissions": { "allow": ["Bash(x)"] } } }\n' > "$O"
run; check_exit 2 $?
contains "$LOG" "not in set.permissions"
printf '{ "bogus": 1 }\n' > "$O"
run; check_exit 2 $?
if [ ! -e "$OUT" ]; then ok "nothing written"; else bad "an invalid overlay wrote the output"; fi

banner "(4) --check: in step, an edit, a pending build"
fresh
run
run --check; check_exit 0 $?
jq '.permissions.allow += ["Bash(npm test)"] | .theme = "light"' "$OUT" > "$WORK/t" && mv "$WORK/t" "$OUT"
jq '.permissions.ask += ["Bash(rclone selfupdate:*)"]' "$B" > "$WORK/t" && mv "$WORK/t" "$B"
run --check; check_exit 1 $?
contains "$LOG" "edited in ~/.claude/settings.json"
contains "$LOG" "+ allow Bash(npm test)"
contains "$LOG" "+ theme = \"light\""
contains "$LOG" "waiting for a build"
contains "$LOG" "+ ask Bash(rclone selfupdate:*)"

banner "(5) a build refuses to overwrite edits; --force discards them"
run; check_exit 1 $?
contains "$LOG" "has edits of its own"
is '.theme' "$OUT" '"light"'
run --force; check_exit 0 $?
is '.theme' "$OUT" 'null'
run --check; check_exit 0 $?

banner "(6) --adopt keeps the edits and not the pending change's undoing"
fresh
run
jq '.permissions.allow += ["Bash(npm test)"] | .permissions.ask -= ["Bash(rm:*)", "Bash(secrets exec:*)"] | .theme = "dark" | del(.statusLine)' "$OUT" > "$WORK/t" && mv "$WORK/t" "$OUT"
jq '.permissions.ask += ["Bash(rclone selfupdate:*)"]' "$B" > "$WORK/t" && mv "$WORK/t" "$B"
run --adopt; check_exit 0 $?
contains "$LOG" "refused: ask Bash(secrets exec:*): guards secrets"
contains "$LOG" "replace each placeholder"
is '.allow.add' "$O" '["Bash(npm test)"]'
is '[.ask.remove[].rule]' "$O" '["Bash(rm:*)"]'
is '.set.theme' "$O" '"dark"'
is '.unset' "$O" '["statusLine"]'
is '.permissions.ask' "$OUT" '["Bash(git push:*)","Bash(secrets exec:*)","Bash(rclone selfupdate:*)"]'
run --check; check_exit 0 $?
jq '.permissions.ask += ["Bash(rm:*)"]' "$OUT" > "$WORK/t" && mv "$WORK/t" "$OUT"
run --adopt; check_exit 0 $?
is '.ask' "$O" 'null'

banner "(7) --adopt --from: a whole file into an overlay that rebuilds it"
fresh
jq '.permissions.allow += ["Bash(git checkout:*)"] | .permissions.ask -= ["Bash(git push:*)"] | .model = "opus" | .env.NO_COLOR = "0"' "$B" > "$WORK/mine.json"
run --adopt --from "$WORK/mine.json"; check_exit 0 $?
if [ ! -e "$OUT" ]; then ok "--from writes only the overlay"; else bad "--from wrote the output"; fi
run; check_exit 0 $?
if [ "$(jq -S . "$OUT")" = "$(jq -S . "$WORK/mine.json")" ]; then ok "the build is the file adopted"; else bad "the build differs from the file adopted"; fi

banner "(8) a link in the output's place"
fresh
ln -s "$B" "$OUT"
run --check; check_exit 1 $?
contains "$LOG" "is a link to"
run; check_exit 1 $?
if [ -L "$OUT" ]; then ok "link left alone"; else bad "the link was replaced without --replace-link"; fi
run --replace-link; check_exit 0 $?
if [ -f "$OUT" ] && [ ! -L "$OUT" ]; then ok "a built file in its place"; else bad "still a link"; fi
if cmp -s "$OUT" "$B"; then bad "the base was overwritten through the link"; else ok "the base untouched"; fi

banner "(9) the shipped base and example overlay"
"$SCRIPT" --print --base "$ROOT/claude-global/settings.json" --overlay "$ROOT/claude-global/settings.overlay.example.json" > "$WORK/shipped.json" 2> "$LOG"
check_exit 0 $?
is '.permissions.ask | index("Bash(brew uninstall:*)")' "$WORK/shipped.json" 'null'
if [ -e "$ROOT/claude-global/settings.overlay.json" ]; then bad "the template ships settings.overlay.json"; else ok "no settings.overlay.json in the template"; fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
