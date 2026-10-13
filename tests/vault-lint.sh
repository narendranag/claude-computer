#!/usr/bin/env bash
# tests/vault-lint.sh — run bin/vault-lint against the fixture vault in tests/fixtures/vault-lint/.
#
# Usage: ./tests/vault-lint.sh
#
# The fixture holds a valid note of every memory/ type, a generated repo snapshot and catalogue, and
# notes that break each rule once or twice (markers: a hub whose block start line an edit cut). tests/fixtures/vault-lint.expected is the exact output.
#
# Cases: (1) the default scope (memory/ and sources/repos/) gives exactly the expected findings, exit 1 ·
# (2) --json carries the same findings · (3) PATHs narrow the check, and a duplicate is still found
# against notes outside them · (4) a clean subset exits 0; _templates/ is never checked · (5) usage and
# a missing vault
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/vault-lint"
FIX="$ROOT/tests/fixtures/vault-lint"
[ -x "$SCRIPT" ] || { echo "bin/vault-lint is not executable" >&2; exit 1; }
command -v uv > /dev/null || { echo "uv is required" >&2; exit 1; }

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cc-vault-lint-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
unset CC_VAULT

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
lacks() { if grep -qF -- "$2" "$1"; then bad "$(basename "$1") has '$2'"; else ok "no: $2"; fi; }

n=0
case_new() { n=$((n + 1)); printf '\n(%s) %s\n' "$n" "$1"; OUT="$WORK/out$n.txt"; }
run() { "$SCRIPT" "$@" > "$OUT" 2>&1; }

# On a cold cache uv prints "Installed 1 package" to stderr; install the script's environment first.
"$SCRIPT" --help > /dev/null 2>&1

case_new "the default scope gives exactly the expected findings"
run --vault "$FIX"
check_exit 1 $?
if diff -u "$ROOT/tests/fixtures/vault-lint.expected" "$OUT"; then ok "output matches vault-lint.expected"; else bad "output differs"; fi
for rule in frontmatter type required enum date folder link link-format filename duplicate log-citation markers ties; do
  if grep -q ": $rule: " "$OUT"; then ok "rule $rule fires"; else bad "rule $rule never fires"; fi
done
lacks "$OUT" "_catalogue.md"
lacks "$OUT" "memory/people/sam-rivera.md:1: link"
lacks "$OUT" "sources/repos/widget.md"
lacks "$OUT" "sam-rivera.md:6: ties"
contains "$OUT" "priya-shah.md:6: ties: tie 3: since 2026-09-01 is after until 2026-03-01"

case_new "--json carries the same findings"
run --vault "$FIX" --json
check_exit 1 $?
if python3 - "$OUT" "$ROOT/tests/fixtures/vault-lint.expected" <<'EOF'; then ok "json == text"; else bad "json and text disagree"; fi
import json, sys
data = json.load(open(sys.argv[1]))
text = [l for l in open(sys.argv[2]).read().splitlines() if not l.startswith("vault-lint:")]
mine = [f"{e['path']}:{e['line']}: {e['rule']}: {e['message']}" for e in data["errors"]]
sys.exit(0 if mine == text and data["checked"] == 20 else 1)
EOF

case_new "PATHs narrow the check"
run --vault "$FIX" notes
check_exit 1 $?
contains "$OUT" "notes/Untidy_Note.md:1: filename: 'Untidy_Note.md' is not a kebab-case slug"
contains "$OUT" "notes/Untidy_Note.md:4: link: topics: [[memory/topics/haggling]] does not resolve"
contains "$OUT" "vault-lint: 2 notes checked, 2 errors in 1 notes"
run --vault "$FIX" "$FIX/memory/people/sam-rivera.md"
check_exit 1 $?
contains "$OUT" "memory/people/sam-rivera.md:1: duplicate: person identity 'sam r' is also memory/people/sam-r.md"
contains "$OUT" "1 notes checked, 1 errors"

case_new "a clean subset exits 0; _templates/ is never checked"
run --vault "$FIX" notes/fixed-fees-buy-trust.md memory/orgs/acme-corp.md memory/meetings/2026 sources/transcripts
check_exit 1 $?
contains "$OUT" "memory/orgs/acme-corp.md:1: duplicate: org identity 'acme' is also memory/orgs/Bad_Name.md"
cp -R "$FIX" "$WORK/v"
rm -f "$WORK/v/memory/orgs/Bad_Name.md"
run --vault "$WORK/v" notes/fixed-fees-buy-trust.md memory/orgs/acme-corp.md memory/meetings/2026 sources/transcripts
check_exit 0 $?
contains "$OUT" "vault-lint: 4 notes checked, 0 errors in 0 notes"
run --vault "$WORK/v" "$WORK/v"
lacks "$OUT" "_templates"

case_new "usage and a missing vault"
run --help
check_exit 0 $?
contains "$OUT" "vault-lint [--vault DIR] [--json] [PATH...]"
run --vault "$FIX" --bogus
check_exit 2 $?
run --vault "$WORK/no-such-vault"
check_exit 5 $?
run --vault "$FIX" no/such/path.md
check_exit 2 $?

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
