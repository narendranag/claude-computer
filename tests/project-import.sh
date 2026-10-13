#!/usr/bin/env bash
# tests/project-import.sh — drive bin/project-import offline against recorded GitHub responses.
#
# Usage: ./tests/project-import.sh
#
# PROJECT_IMPORT_FIXTURE points at tests/fixtures/project-import/, so no case calls gh or the network.
# The fixture is three made-up repos: acme/widget (250 commits over three pages, README, CLAUDE.md,
# docs/DECISIONS.md, an adr folder), acme/spoon (a fork with none of acme's commits) and acme/stub
# (three commits, no README), plus a two-page GraphQL listing for --catalogue.
#
# Cases: (1) usage, a missing vault, a missing gh · (2) --dry-run prints the tiers and writes nothing ·
# (3) a snapshot: properties, activity without noise, tree, files with headings pushed down, docs ·
# (4) a re-import of the same sha is a true no-op; `created` survives and `updated` moves only with
# `as_of` · (5) --json · (6) --catalogue: order, tiers, escaped cells, hub links, and the result passes
# vault-lint · (7) CC_VAULT · (8) a repo GitHub does not have is exit 1 · (9) the owner's commits: someone
# else's code is skip, --me and PROJECT_IMPORT_ME make it the owner's, no authors means unknown, and a repo
# the vault already has a hub for is hub
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/project-import"
[ -x "$SCRIPT" ] || { echo "bin/project-import is not executable" >&2; exit 1; }
command -v uv > /dev/null || { echo "uv is required" >&2; exit 1; }

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cc-project-import-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
export PROJECT_IMPORT_FIXTURE="$ROOT/tests/fixtures/project-import"
unset CC_VAULT PROJECT_IMPORT_RECORD
TODAY="$(date +%Y-%m-%d)"

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
lacks() { if grep -qF -- "$2" "$1"; then bad "$(basename "$1") has '$2'"; else ok "no: $2"; fi; }

n=0
case_new() { n=$((n + 1)); printf '\n(%s) %s\n' "$n" "$1"; V="$WORK/vault$n"; OUT="$WORK/out$n.txt"; mkdir -p "$V"; }
run() { "$SCRIPT" "$@" > "$OUT" 2>&1; }

case_new "usage, missing vault, missing gh"
run --help
check_exit 0 $?
contains "$OUT" "project-import <owner/repo>..."
run --vault "$V"
check_exit 2 $?
run acme/widget --catalogue --vault "$V"
check_exit 2 $?
run 'acme/wid get' --vault "$V"
check_exit 2 $?
contains "$OUT" "not owner/repo"
run acme/widget --owner acme --vault "$V"
check_exit 2 $?
run acme/widget --vault "$WORK/no-such-vault"
check_exit 5 $?
mkdir -p "$WORK/empty-path"
(unset PROJECT_IMPORT_FIXTURE; PATH="$WORK/empty-path" "$(command -v uv)" run --quiet --script "$SCRIPT" acme/widget --vault "$V" > "$OUT" 2>&1)
check_exit 3 $?
contains "$OUT" "missing dependency: gh"

case_new "--dry-run prints the tiers and writes nothing"
run acme/widget acme/spoon acme/stub --vault "$V" --dry-run
check_exit 0 $?
contains "$OUT" "would import acme/widget @ 1111111 (250 commits, hub)"
contains "$OUT" "would import acme/spoon @ 2222222 (2 commits, skip)"
contains "$OUT" "would import acme/stub @ 3333333 (3 commits, catalogue)"
if [ -z "$(find "$V" -mindepth 1 -print -quit)" ]; then ok "vault untouched"; else bad "dry run wrote: $(find "$V" -mindepth 1)"; fi

case_new "a snapshot"
run acme/widget acme/spoon acme/stub --vault "$V"
check_exit 0 $?
contains "$OUT" "imported acme/widget @ 1111111 (250 commits, hub)"
contains "$OUT" "imported acme/stub @ 3333333 (3 commits, catalogue)"
S="$V/sources/repos/widget.md"
if [ -f "$S" ]; then ok "wrote sources/repos/widget.md"; else bad "no $S"; fi
if head -1 "$S" | grep -qx -- "---"; then ok "opens with front matter"; else bad "no front matter"; fi
contains "$S" "type: source"
contains "$S" "kind: repo"
contains "$S" "generated: project-import"
contains "$S" "created: $TODAY"
contains "$S" "repo: acme/widget"
contains "$S" "as_of: '1111111111111111111111111111111111111111'"
contains "$S" "languages: {Python: 75.0, Shell: 20.0, Makefile: 5.0}"
contains "$S" "repo_topics: [cli, widgets]"
contains "$S" "commits: 250"
contains "$S" "pushed_at: 2026-09-30"
contains "$S" "- First commit: 2025-01-05 — Initial commit (\`fffffff\`)"
contains "$S" "- Last commit: 2026-09-30 — feat: ship the widget CLI (\`1111111\`)"
contains "$S" "(the counts below cover the most recent 7)"
contains "$S" "- 2026 (5): Aug 2 · Sep 3"
contains "$S" "- 2026-08-01 — fix: widgets no longer wobble"
lacks "$S" "vault backup"
lacks "$S" "Merge pull request"
lacks "$S" "chore: bump deps"
contains "$S" "## File: README.md"
contains "$S" "### Widget"
contains "$S" "#### Install"
contains "$S" "# not a heading"
contains "$S" "## File: docs/DECISIONS.md"
contains "$S" "- \`docs/adr/0001-cli.md\`"
contains "$V/sources/repos/spoon.md" "parent: upstream/spoon"
contains "$V/sources/repos/spoon.md" "own_commits: 0"
lacks "$V/sources/repos/stub.md" "description:"
lacks "$V/sources/repos/stub.md" "## File:"

case_new "a re-import of the same sha is a true no-op"
run acme/widget --vault "$V"
cp "$V/sources/repos/widget.md" "$WORK/first.md"
run acme/widget --vault "$V"
check_exit 0 $?
contains "$OUT" "imported acme/widget @ 1111111 (250 commits, hub) — unchanged"
if cmp -s "$WORK/first.md" "$V/sources/repos/widget.md"; then ok "byte-identical"; else bad "changed on re-import"; fi
sed -e "s/^created: .*/created: 2026-01-01/" -e "s/^updated: .*/updated: 2026-01-02/" "$WORK/first.md" > "$V/sources/repos/widget.md"
run acme/widget --vault "$V"
contains "$V/sources/repos/widget.md" "created: 2026-01-01"
contains "$V/sources/repos/widget.md" "updated: 2026-01-02"
sed -e "s/^as_of: .*/as_of: 'abc'/" "$V/sources/repos/widget.md" > "$WORK/moved.md" && cp "$WORK/moved.md" "$V/sources/repos/widget.md"
run acme/widget --vault "$V"
contains "$V/sources/repos/widget.md" "created: 2026-01-01"
contains "$V/sources/repos/widget.md" "updated: $TODAY"

case_new "--json"
run acme/spoon acme/stub --vault "$V" --json
check_exit 0 $?
contains "$OUT" '"tier": "skip"'
contains "$OUT" '"tier": "catalogue"'
contains "$OUT" '"own_commits": 0'
lacks "$OUT" "imported "

case_new "--catalogue"
mkdir -p "$V/memory/projects"
cat > "$V/memory/projects/widget.md" <<'EOF'
---
type: project
created: 2026-10-01
status: active
repo: acme/widget
snapshot: "[[sources/repos/widget]]"
---
# widget
EOF
run acme/widget --vault "$V"
run --catalogue --vault "$V"
check_exit 0 $?
contains "$OUT" "catalogue acme: 3 repos (1 hub, 1 catalogue, 1 skip)"
C="$V/memory/projects/_catalogue.md"
contains "$C" "type: map"
contains "$C" "generated: project-import"
contains "$C" "| widget | 2025 | 2026-09-30 | Python | 2.0 MB | 250 | hub | Widgets, \\| piped | [[memory/projects/widget]] |"
contains "$C" "| spoon (fork) | 2024 | 2024-05-01 | Go | 30 KB | 2 | skip |  |  |"
contains "$C" "| stub | 2023 | 2023-02-03 | Python | 4 KB | 3 | catalogue |  |  |"
order="$(grep -oE '^\| (widget|spoon|stub)' "$C" | tr -d '| ' | tr '\n' ' ')"
if [ "$order" = "widget spoon stub " ]; then ok "newest push first"; else bad "order: $order"; fi
cp "$C" "$WORK/cat.md"
run --catalogue --owner acme --vault "$V"
contains "$OUT" "unchanged"
if cmp -s "$WORK/cat.md" "$C"; then ok "catalogue re-run is a no-op"; else bad "catalogue changed on re-run"; fi
"$ROOT/bin/vault-lint" --vault "$V" > "$OUT" 2>&1
check_exit 0 $?
contains "$OUT" "3 notes checked, 0 errors"

case_new "CC_VAULT"
CC_VAULT="$V" "$SCRIPT" acme/stub > "$OUT" 2>&1
check_exit 0 $?
if [ -f "$V/sources/repos/stub.md" ]; then ok "wrote into \$CC_VAULT"; else bad "CC_VAULT ignored"; fi

case_new "a repo GitHub does not have"
run acme/ghost --vault "$V"
check_exit 1 $?
contains "$OUT" "no repo acme/ghost"

case_new "the owner's commits"
run acme/copied --vault "$V"
check_exit 0 $?
contains "$OUT" "(12 commits, skip)"
contains "$V/sources/repos/copied.md" "own_commits: 0"
run acme/copied --vault "$V" --me someone
contains "$OUT" "(12 commits, hub)"
contains "$V/sources/repos/copied.md" "own_commits: 12"
PROJECT_IMPORT_ME="Some One" "$SCRIPT" acme/copied --vault "$V" > "$OUT" 2>&1
contains "$OUT" "(12 commits, hub)"
PROJECT_IMPORT_ME="@scrapers.example" "$SCRIPT" acme/copied --vault "$V" > "$OUT" 2>&1
contains "$OUT" "(12 commits, hub)"
run acme/widget --vault "$V"
lacks "$V/sources/repos/widget.md" "own_commits"
mkdir -p "$V/memory/projects"
printf -- '---\ntype: project\ncreated: 2026-10-13\nstatus: active\nrepo: acme/stub\n---\n# Stub\n' > "$V/memory/projects/stub-checkout.md"
run acme/stub --vault "$V"
contains "$OUT" "(3 commits, hub)"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
