#!/usr/bin/env bash
# tests/vault-nightly.sh — drive bin/vault-nightly end to end with a stand-in `claude` on the PATH.
#
# Usage: ./tests/vault-nightly.sh
#
# Everything happens under a throwaway HOME: a vault (a git repo with one capture in inbox/), and one
# brain, ~/projects/demo, with a TASKS.md. The stand-in claude does what the real one is told to do in the
# worktree it is started in — files the capture, writes .nightly/tasks.jsonl, commits — in one of a few
# modes (FAKE_CLAUDE_MODE), and prints claude's JSON result. No network, no model, no tg-send (--quiet).
#
# Cases: (1) --help, a bad flag, a missing vault · (2) an empty inbox is a no-op · (3) --dry-run lists the
# work, the brains and the hubs to write (a bare one, a catalogue `hub` without one) and changes nothing · (4) a run: the capture is filed in ~/vault, the worktree and
# branch are gone, the task is under the brain's ## Next in its own commit, a bad task line is reported,
# ## Overnight is in today's daily note · (5) the gate: a note that fails vault-lint leaves ~/vault and its
# inbox as they were and keeps the worktree · (6) the gate: a deleted note outside inbox/ · (7) --no-route
# leaves every brain alone · (8) claude failing is exit 1, ~/vault untouched
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/vault-nightly"
[ -x "$SCRIPT" ] || { echo "bin/vault-nightly is not executable" >&2; exit 1; }
command -v uv > /dev/null || { echo "uv is required" >&2; exit 1; }

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cc-vault-nightly-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
UV_CACHE_DIR="$(uv cache dir)"
export UV_CACHE_DIR
export HOME="$WORK/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
unset CC_VAULT
TODAY="$(date +%Y-%m-%d)"
V="$HOME/vault"
B="$HOME/projects/demo"

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1" 2> /dev/null; then ok "$(basename "$1") says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
lacks() { if grep -qF -- "$2" "$1" 2> /dev/null; then bad "$(basename "$1") has '$2'"; else ok "$(basename "$1") lacks: $2"; fi; }
exists() { if [ -e "$1" ]; then ok "exists: ${1#"$HOME"/}"; else bad "missing: ${1#"$HOME"/}"; fi; }
gone() { if [ -e "$1" ]; then bad "still there: ${1#"$HOME"/}"; else ok "gone: ${1#"$HOME"/}"; fi; }

# The stand-in claude. It runs in the worktree, like the real one.
STUB="$WORK/stub"
mkdir -p "$STUB"
cat > "$STUB/claude" << 'EOF'
#!/usr/bin/env bash
set -u
case "${FAKE_CLAUDE_MODE:-file}" in
  fail) echo '{"type":"result","is_error":true,"result":"boom"}'; exit 1 ;;
esac
grep -q 'inbox/clip.md' .nightly/run.md || { echo '{"is_error":true,"result":"run.md lacks the capture"}'; exit 1; }
mkdir -p sources
git mv inbox/clip.md sources/a-clip.md
[ -f "inbox/Lepore ‘Harvard’.md" ] && git mv "inbox/Lepore ‘Harvard’.md" "sources/lepore-harvard.md" \
  && printf -- '---\ntype: source\ncreated: 2026-10-13\nkind: clip\n---\n# Lepore\n\nAn essay.\n' > sources/lepore-harvard.md
printf -- '---\ntype: source\ncreated: 2026-10-13\nkind: clip\n---\n# A clip\n\nWords.\n' > sources/a-clip.md
case "${FAKE_CLAUDE_MODE:-file}" in
  lintfail)
    mkdir -p memory/people
    printf -- '---\ntype: person\ncreated: 2026-10-13\n---\n# Nobody\n' > memory/people/no-name.md ;;
  delete)
    git rm -q notes/keep.md ;;
esac
printf '%s\n' '{"brain": "demo", "task": "Read the clip", "due": "2026-10-20", "source": "sources/a-clip"}' \
  '{"brain": "nope", "task": "Lost", "source": "sources/a-clip"}' > .nightly/tasks.jsonl
git add -A && git commit -q -m "inbox: filed 1"
echo '{"type":"result","is_error":false,"total_cost_usd":1.234,"num_turns":42,"result":"inbox/clip.md → sources/a-clip.md; 1 task for demo"}'
EOF
chmod +x "$STUB/claude"
printf '#!/bin/sh\nexit 0\n' > "$STUB/gh" && chmod +x "$STUB/gh"  # find_hubs only looks when gh exists
export PATH="$STUB:$PATH"

fresh() {
  rm -rf "$HOME" && mkdir -p "$V/inbox" "$V/notes" "$V/memory/people" "$V/daily" "$B"
  printf -- '---\ntype: person\ncreated: 2026-10-01\nname: Alex Example\nme: true\n---\n# Alex Example\n' > "$V/memory/people/alex-example.md"
  printf -- '---\ntype: note\ncreated: 2026-10-01\n---\n# Keep me\n' > "$V/notes/keep.md"
  printf '# vault\n' > "$V/CLAUDE.md"
  printf '# Tasks\n\n## Now\n\n## Unassigned\n' > "$V/TASKS.md"
  [ "${1:-}" = empty ] || printf -- '---\ntype: source\n---\nA clipped page.\n' > "$V/inbox/clip.md"
  [ "${1:-}" = empty ] || printf 'An essay.\n' > "$V/inbox/Lepore ‘Harvard’.md"
  git -C "$V" init -q -b main && git -C "$V" add -A && git -C "$V" commit -q -m init
  printf '# demo — a test brain\n' > "$B/CLAUDE.md"
  printf '# Tasks\n\n## Now\n\n## Next\n\n- [ ] Existing\n\n## Later\n\n## Done\n' > "$B/TASKS.md"
  git -C "$B" init -q -b main && git -C "$B" add -A && git -C "$B" commit -q -m init
}
run() { "$SCRIPT" --quiet "$@" > "$WORK/out" 2>&1; echo $?; }

echo "1. usage"
check_exit 0 "$("$SCRIPT" --help > /dev/null 2>&1; echo $?)"
check_exit 2 "$("$SCRIPT" --bogus > /dev/null 2>&1; echo $?)"
check_exit 5 "$("$SCRIPT" --vault "$WORK/none" > /dev/null 2>&1; echo $?)"

echo "2. empty inbox"
fresh empty
H0="$(git -C "$V" rev-parse HEAD)"
check_exit 0 "$(run)"
contains "$WORK/out" "nothing in the inbox"
if [ "$(git -C "$V" rev-parse HEAD)" = "$H0" ]; then ok "vault unchanged"; else bad "vault changed"; fi

echo "3. --dry-run"
fresh
mkdir -p "$V/memory/projects"
printf -- '---\ntype: project\ncreated: 2026-10-13\nstatus: active\nrepo: acme/demo\n---\n\n# demo\n\n<!-- tasks-sync:start -->\n## Tasks\n<!-- tasks-sync:end -->\n' > "$V/memory/projects/demo.md"
printf -- '---\ntype: project\ncreated: 2026-10-13\nstatus: active\nrepo: acme/full\n---\n# full\n\nWritten.\n' > "$V/memory/projects/full.md"
printf -- '---\ntype: map\ngenerated: project-import\nowner: acme\n---\n| Repo | Created | Last push | Language | Size | Commits | Tier | Description | Hub |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n| old-thing (archived) | 2015 | 2016-01-01 | Go | 1 KB | 40 | hub | A \\| piped thing |  |\n| tiny | 2015 | 2016-01-01 | Go | 1 KB | 2 | catalogue |  |  |\n| demo | 2026 | 2026-10-01 | Go | 1 KB | 90 | hub |  | [[memory/projects/demo]] |\n' > "$V/memory/projects/_catalogue.md"
check_exit 0 "$(run --dry-run)"
contains "$WORK/out" "inbox/clip.md"
# shellcheck disable=SC2016 # the backticks are Markdown, not a command
contains "$WORK/out" '`demo` — ~/projects/demo — demo — a test brain'
exists "$V/inbox/clip.md"
contains "$WORK/out" "memory/projects/demo.md\` — bare — \`acme/demo\`"
contains "$WORK/out" "memory/projects/old-thing.md\` — new — \`acme/old-thing\`"
lacks "$WORK/out" "memory/projects/full.md"
lacks "$WORK/out" "tiny"
contains "$WORK/out" "2 capture(s), 2 hub(s)"

echo "4. a run"
fresh
check_exit 0 "$(run)"
exists "$V/sources/a-clip.md"
gone "$V/inbox/clip.md"
gone "$V/inbox/Lepore ‘Harvard’.md"
contains "$B/TASKS.md" "- [ ] Read the clip 📅 2026-10-20 ← [[sources/a-clip]]"
if awk '/^## Next/{n=1} /^## Later/{n=0} n' "$B/TASKS.md" | grep -qF "Read the clip"; then ok "task is under ## Next"; else bad "task not under ## Next"; fi
if [ "$(git -C "$B" log -1 --format=%s)" = "tasks: from vault a-clip" ]; then ok "brain commit"; else bad "brain commit: $(git -C "$B" log -1 --format=%s)"; fi
if [ -z "$(git -C "$B" status --porcelain)" ]; then ok "brain clean"; else bad "brain dirty"; fi
D="$V/daily/$TODAY.md"
contains "$D" "## Overnight"
contains "$D" "<!-- vault-nightly:start -->"
contains "$D" "inbox: filed 1"
contains "$D" "[[sources/a-clip|A clip]] (clip)"
contains "$D" "- Filed to \`sources/\`:"
contains "$D" " · \$1.23, 42 turns · "
contains "$D" "unknown brain 'nope'"
contains "$D" "inbox/clip.md → sources/a-clip.md"
subjects="$(git -C "$V" log -3 --format=%s)"
if printf '%s\n' "$subjects" | grep -qxF "nightly: overnight report $TODAY"; then ok "report commit"; else bad "report commit: $subjects"; fi
if [ -z "$(git -C "$V" status --porcelain)" ]; then ok "vault clean, tasks-sync output committed"; else bad "vault dirty: $(git -C "$V" status --porcelain -uall | head -3)"; fi
if [ -z "$(git -C "$V" branch --list 'nightly/*')" ]; then ok "branch removed"; else bad "branch left"; fi
if [ "$(git -C "$V" worktree list | wc -l | tr -d ' ')" = 1 ]; then ok "worktree removed"; else bad "worktree left"; fi
# A second run the same day replaces the block, not appends.
mkdir -p "$V/inbox" && printf -- '---\ntype: source\n---\nAnother.\n' > "$V/inbox/clip.md" && git -C "$V" add -A && git -C "$V" commit -q -m more
git -C "$V" rm -q sources/a-clip.md && git -C "$V" commit -q -m "make room"
check_exit 0 "$(run)"
if [ "$(grep -c 'vault-nightly:start' "$D")" = 1 ]; then ok "one Overnight block after two runs"; else bad "blocks: $(grep -c 'vault-nightly:start' "$D")"; fi
if [ "$(grep -c '^_vault-nightly · ' "$D")" = 2 ]; then ok "both runs' reports kept"; else bad "reports: $(grep -c '^_vault-nightly · ' "$D")"; fi

echo "5. the gate: vault-lint"
fresh
H0="$(git -C "$V" rev-parse HEAD)"
check_exit 1 "$(FAKE_CLAUDE_MODE=lintfail run)"
contains "$WORK/out" "gate failed"
landed="$(git -C "$V" log --format=%s "$H0..HEAD")"
if ! printf '%s\n' "$landed" | grep -qvx -e 'tasks: sync' -e ''; then ok "nothing landed but tasks-sync"; else bad "vault moved: $landed"; fi
exists "$V/inbox/clip.md"
lacks "$B/TASKS.md" "Read the clip"
if [ -n "$(git -C "$V" branch --list 'nightly/*')" ]; then ok "branch kept for a look"; else bad "branch removed"; fi

echo "6. the gate: a deletion outside inbox/"
fresh
check_exit 1 "$(FAKE_CLAUDE_MODE=delete run)"
contains "$WORK/out" "deleted outside inbox/: notes/keep.md"
exists "$V/notes/keep.md"

echo "7. --no-route"
fresh
check_exit 0 "$(run --no-route)"
lacks "$B/TASKS.md" "Read the clip"
contains "$V/daily/$TODAY.md" "(trial, not added)"

echo "8. claude fails"
fresh
H0="$(git -C "$V" rev-parse HEAD)"
check_exit 1 "$(FAKE_CLAUDE_MODE=fail run)"
landed="$(git -C "$V" log --format=%s "$H0..HEAD")"
if ! printf '%s\n' "$landed" | grep -qvx -e 'tasks: sync' -e ''; then ok "nothing landed but tasks-sync"; else bad "vault moved: $landed"; fi
exists "$V/inbox/clip.md"

echo
echo "vault-nightly: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
