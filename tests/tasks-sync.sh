#!/usr/bin/env bash
# tests/tasks-sync.sh — bin/tasks-sync against a throwaway home: where hubs go and what the map shows.
#
# Usage: ./tests/tasks-sync.sh
#
# The home has three brains: projects/alpha (a GitHub origin, no hub yet), clients/beta (a GitHub origin
# and a hub Claude wrote, with a ## Log) and archive (no remote). Nothing reaches the network.
#
# Cases: (1) a new hub in memory/projects/ with type, status, repo and local, and the Tasks block ·
# (2) an existing hub keeps its properties and text, and gets the block above ## Log; a second run
# replaces it, not adds one · (2b) a hub whose start line an edit cut, with a second block, heals to one · (3) a brain with no remote gets no hub, and its tasks are still in the
# map · (4) the map: Now everywhere, one line per brain linking its hub, no old projects/ folder ·
# (4b) a hub whose checkout is gone has its block frozen and is listed under Hubs to close until its
# status is set; a hub with no `local` is left alone · (5) the hubs pass vault-lint · (6) --json
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
command -v uv > /dev/null || { echo "uv is required" >&2; exit 1; }

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cc-tasks-sync-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
H="$WORK/home"
V="$H/vault"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset CC_VAULT

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
contains() { if grep -qF -- "$2" "$1" 2> /dev/null; then ok "$(basename "$1") says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
lacks() { if grep -qF -- "$2" "$1" 2> /dev/null; then bad "$(basename "$1") has '$2'"; else ok "$(basename "$1") lacks: $2"; fi; }

brain() {  # <dir> <remote or -> <tasks>
  mkdir -p "$1" && printf '# %s\n' "$(basename "$1")" > "$1/CLAUDE.md" && printf '%b' "$3" > "$1/TASKS.md"
  git -C "$1" init -q
  [ "$2" = - ] || git -C "$1" remote add origin "$2"
}
mkdir -p "$V/memory/projects" "$V/maps"
brain "$H/projects/alpha" git@github.com:acme/alpha.git '## Now\n\n- [ ] Ship alpha\n\n## Next\n\n- [ ] Write docs\n'
brain "$H/clients/beta" https://github.com/acme/client-beta.git '## Now\n\n## Next\n\n- [ ] Invoice beta\n'
brain "$H/archive" - '## Now\n\n- [ ] Push the 2025 photos\n'
cat > "$V/memory/projects/beta.md" << 'EOF'
---
type: project
created: 2026-10-01
status: active
repo: acme/client-beta
---
# Beta

Claude's summary of beta.

## Log
- 2026-10-01 — Kicked off. ([[memory/projects/beta]])
EOF

# gamma: a hub an edit damaged — the summary took the start line's head, and a later run added a second block.
brain "$H/projects/gamma" git@github.com:acme/gamma.git '## Now\n\n- [ ] Ship gamma\n'
cat > "$V/memory/projects/gamma.md" << 'EOF'
---
type: project
created: 2026-10-01
status: active
repo: acme/gamma
---
# Gamma

Gamma's summary.

 — generated, edit the brain's TASKS.md instead -->
## Tasks

- [ ] Stale gamma
<!-- tasks-sync:end -->

<!-- tasks-sync:start — generated, edit the brain's TASKS.md instead -->
## Tasks

- [ ] Stale gamma
<!-- tasks-sync:end -->

## Log
- 2026-10-01 — Kicked off. ([[memory/projects/gamma]])
EOF

# delta: a hub whose brain has gone (its checkout is not on disk); zeta: a hub with a block and no `local`.
gone_hub() {  # <name> <local line or ->
  {
    printf -- '---\ntype: project\ncreated: 2026-10-01\nstatus: active\nrepo: acme/%s\n' "$1"
    [ "$2" = - ] || printf '%s\n' "$2"
    printf -- '---\n# %s\n\n<!-- tasks-sync:start — generated, edit the brain'"'"'s TASKS.md instead -->\n## Tasks\n\n- [ ] Last %s task\n<!-- tasks-sync:end -->\n\n## Log\n- 2026-10-01 — Kicked off. ([[memory/projects/%s]])\n' "$1" "$1" "$1"
  } > "$V/memory/projects/$1.md"
}
gone_hub delta 'local: "~/projects/delta"'
gone_hub zeta -

"$ROOT/bin/tasks-sync" --home "$H" > "$WORK/out" 2>&1 || bad "tasks-sync failed: $(cat "$WORK/out")"
"$ROOT/bin/tasks-sync" --home "$H" > /dev/null 2>&1

echo "1. a new hub"
A="$V/memory/projects/alpha.md"
contains "$A" "type: project"
contains "$A" "status: active"
contains "$A" "repo: acme/alpha"
contains "$A" 'local: "~/projects/alpha"'
contains "$A" "- [ ] Ship alpha"
contains "$A" "- [ ] Write docs"

echo "2. an existing hub"
B="$V/memory/projects/beta.md"
contains "$B" "Claude's summary of beta."
contains "$B" "repo: acme/client-beta"
lacks "$B" "local:"
contains "$B" "- [ ] Invoice beta"
if awk '/tasks-sync:end/{e=NR} /^## Log/{l=NR} END{exit !(e && l && e < l)}' "$B"; then ok "block above ## Log"; else bad "block not above ## Log"; fi
if [ "$(grep -c 'tasks-sync:start' "$B")" = 1 ]; then ok "one block after two runs"; else bad "blocks: $(grep -c 'tasks-sync:start' "$B")"; fi

echo "2b. a damaged hub heals"
G="$V/memory/projects/gamma.md"
contains "$G" "Gamma's summary."
contains "$G" "- [ ] Ship gamma"
lacks "$G" "Stale gamma"
if [ "$(grep -c 'tasks-sync:start' "$G")" = 1 ] && [ "$(grep -c 'tasks-sync:end' "$G")" = 1 ]; then ok "one whole block"; else bad "markers: $(grep -c 'tasks-sync:' "$G")"; fi
if grep -q '^ — generated' "$G"; then bad "cut start line left"; else ok "cut start line gone"; fi
contains "$G" "## Log"

echo "3. no remote, no hub"
if [ -e "$V/memory/projects/archive.md" ]; then bad "archive got a hub"; else ok "archive has no hub"; fi
contains "$V/maps/tasks.md" "Push the 2025 photos"

echo "4. the map"
M="$V/maps/tasks.md"
contains "$M" "## Now, everywhere"
contains "$M" "- [ ] Ship alpha — [[memory/projects/alpha|alpha]]"
contains "$M" "- [[memory/projects/alpha|alpha]] — 1 now, 1 next"
contains "$M" "- archive — 1 now"
lacks "$M" "Write docs"
if [ -e "$V/projects" ]; then bad "old projects/ written"; else ok "no projects/ folder"; fi

echo "4b. a hub whose brain has gone"
D="$V/memory/projects/delta.md"
contains "$WORK/out" "froze 1 gone brain(s): delta"
lacks "$D" "tasks-sync:"
contains "$D" "## Open at close (brain gone by $(date +%Y-%m-%d))"
contains "$D" "- [ ] Last delta task"
contains "$D" "status: active"
contains "$M" "## Hubs to close (1)"
contains "$M" "- [[memory/projects/delta|delta]] — status: active"
contains "$V/memory/projects/zeta.md" "<!-- tasks-sync:start"
lacks "$M" "zeta|zeta]] — status"
sed -i.bak 's/^status: active$/status: abandoned/' "$D" && rm -f "$D.bak"
"$ROOT/bin/tasks-sync" --home "$H" > /dev/null 2>&1
lacks "$M" "## Hubs to close"

echo "5. vault-lint"
if "$ROOT/bin/vault-lint" --vault "$V" > "$WORK/lint" 2>&1; then ok "hubs pass vault-lint"; else bad "vault-lint: $(tail -3 "$WORK/lint")"; fi

echo "6. --json"
if "$ROOT/bin/tasks-sync" --home "$H" --json | grep -qF '"Ship alpha"'; then ok "json lists tasks"; else bad "json"; fi

echo
echo "tasks-sync: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
