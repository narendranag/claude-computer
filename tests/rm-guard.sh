#!/usr/bin/env bash
# tests/rm-guard.sh — feed claude-global/hooks/rm-guard.py the JSON Claude Code sends, check its decision.
#
# Usage: ./tests/rm-guard.sh
#
# Allowed: a plain rm of literal paths strictly inside /tmp or $TMPDIR. Asked: every other rm —
# outside temp, the temp folder itself, `..`, symlinks out, variables, globs, ~, compound commands,
# sudo, xargs. No decision: commands without rm. Bad input asks (fails closed).
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
HOOK="$PWD/claude-global/hooks/rm-guard.py"
[ -x "$HOOK" ] || { echo "rm-guard.py is not executable" >&2; exit 1; }

WORK="$(mktemp -d /tmp/cc-rm-guard-test.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/dir"
ln -s "$HOME" "$WORK/home-link"
export TMPDIR="${TMPDIR:-/tmp}"

PASS=0
FAIL=0
decision() {
  out="$(jq -n --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}' | "$HOOK")"
  if [ -z "$out" ]; then echo none; else printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision'; fi
}
expect() {
  got="$(decision "$2")"
  if [ "$got" = "$1" ]; then printf '    ok   %-5s %s\n' "$1" "$2"; PASS=$((PASS + 1))
  else printf '    FAIL want %s, got %s: %s\n' "$1" "$got" "$2" >&2; FAIL=$((FAIL + 1)); fi
}

printf '\nallowed\n'
expect allow "rm -rf $WORK/dir"
expect allow "rm $WORK/dir/file.txt"
expect allow "rm -r -f $WORK/dir $WORK/other"
expect allow "rm -rf $WORK/dir/"
expect allow "rm -f ${TMPDIR%/}/cc-something"

printf '\nasked\n'
expect ask "rm -rf $HOME/projects"
expect ask "rm -rf /tmp"
expect ask "rm -rf /tmp/"
expect ask "rm -rf ${TMPDIR%/}"
expect ask "rm -rf /tmp/../Users"
expect ask "rm -rf $WORK/dir/../../.."
expect ask "rm -rf $WORK/home-link/x"
expect ask "rm -rf $WORK/dir $HOME/x"
expect ask "rm -rf /tmp/*"
# shellcheck disable=SC2016 # the $S must reach the hook unexpanded
expect ask 'rm -rf $S'
expect ask "$(printf 'echo hi\nrm -rf %s/x' "$HOME")"
expect ask "rm -rf ~/x"
expect ask "rm -rf relative/path"
expect ask "rm -rf -- $WORK/dir"
expect ask "rm -rf $WORK/dir && echo done"
expect ask "cd /tmp && rm -rf x"
expect ask "sudo rm -rf $WORK/dir"
expect ask "ls | xargs rm"
expect ask "/bin/rm -rf $HOME/x"
expect ask "rm"
expect ask "rm \"$WORK/dir\""

printf '\nno decision\n'
expect none "ls -la /tmp"
expect none "echo rm is a word in a sentence"
expect none "git rm --cached file"
expect none "grep -r format ."

printf '\nbad input asks\n'
got="$(printf 'not json' | "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision')"
if [ "$got" = ask ]; then printf '    ok   ask   unparseable input\n'; PASS=$((PASS + 1)); else printf '    FAIL bad input: %s\n' "$got" >&2; FAIL=$((FAIL + 1)); fi

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
