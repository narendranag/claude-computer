#!/usr/bin/env bash
# tests/template-pull.sh — drive bin/template-pull against a throwaway template and instance.
#
# Usage: ./tests/template-pull.sh
#
# The "template" is a local repo with three release tags; the "instance" is made the way "Use this
# template" makes one — the files of a release, in a new repo with no shared history — with its own
# changes on top. Nothing touches the network.
#
# Cases: (0) this repo's .template-version, install.sh's VERSION and CHANGELOG agree · (1) refuses
# the template itself; no `upstream` remote → 5 · (2) lists releases, marks the instance's, and leaves
# the instance's own tags alone · (3) no .template-version and no --from → 5; an unknown tag → 5;
# uncommitted changes → 2; going backwards → 2 · (4) a clean pull: staged not committed, local
# changes kept, .template-version updated, the CHANGELOG from the new release down to (not
# including) the old one · (5) a file deleted here: skipped and named if the template changed it,
# silent if the template deleted it too · (6) a conflict: exit 1, the file named, markers in it ·
# (7) --dry-run reports the same and leaves the tree, the index and the worktree list as they were ·
# (8) already on that release → 0 · (9) an instance that took part of a release by hand: a rename onto
# a file it already has, a deletion of a file it changed, and a file it already has the same — each
# decided on its own, the rest of the release still applied, the dry run saying the same
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/template-pull"
[ -x "$SCRIPT" ] || { echo "bin/template-pull is not executable" >&2; exit 1; }

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cc-template-pull-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
absent()   { if grep -qF -- "$2" "$1"; then bad "$(basename "$1") has '$2'"; else ok "silent on: $2"; fi; }
banner() { printf '\n%s\n' "== $1"; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
export GIT_CONFIG_NOSYSTEM=1 HOME="$WORK/home"
mkdir -p "$HOME"
git config --global init.defaultBranch main
git config --global advice.detachedHead false

# The script under test, in a copy of bin/ + lib/ whose CC_ROOT is the instance.
run() { # run <instance dir> <args…> → stdout in $WORK/out, stderr in $WORK/err, exit in $RC
  local dir="$1"; shift
  CC_ROOT="$dir" "$SCRIPT" "$@" > "$WORK/out" 2> "$WORK/err"; RC=$?
}

# --------------------------------------------------------------------------
banner "(0) this repo's release markers agree"
tv="$(tr -d '[:space:]' < "$ROOT/.template-version" 2>/dev/null)"
iv="$(sed -n 's/^VERSION="\(.*\)"$/\1/p' "$ROOT/install.sh")"
if [ -n "$tv" ] && [ "$tv" = "v$iv" ]; then ok ".template-version $tv = install.sh VERSION $iv"
else bad ".template-version '$tv' vs install.sh VERSION '$iv'"; fi
if grep -q "^## \[${tv#v}\]" "$ROOT/CHANGELOG.md"; then ok "CHANGELOG has ## [${tv#v}]"; else bad "CHANGELOG has no ## [${tv#v}]"; fi

# --------------------------------------------------------------------------
# The template: three releases. CHANGELOG sections, a file the instance will change, one it will
# delete, one the template deletes, one that will conflict.
T="$WORK/template"
git init -q "$T"
cd "$T" || exit 1
changelog() { # changelog <newest version> …older
  printf '# Changelog\n\n## [Unreleased]\n\n'
  for v in "$@"; do
    printf '## [%s] — 2026-01-01\n\n- change in %s\n\n' "$v" "$v"
    [ "$v" != 0.2.0 ] || printf '### Migrating from 0.1\n\n1. run a step\n\n'
  done
}
printf 'a\nb\nc\n' > shared.txt
printf 'keep\n' > edited-here.txt
printf 'one\n' > deleted-here.txt
printf 'old\n' > dropped.txt
printf 'line\n' > conflict.txt
touch .template
changelog 0.1.0 > CHANGELOG.md
printf 'v0.1.0\n' > .template-version
git add -A && git commit -qm v0.1.0 && git tag v0.1.0

printf 'a\nB\nc\n' > shared.txt
printf 'one\ntwo\n' > deleted-here.txt
git rm -q dropped.txt
printf 'new\n' > added.txt
printf 'theirs\n' > conflict.txt
changelog 0.2.0 0.1.0 > CHANGELOG.md
printf 'v0.2.0\n' > .template-version
git add -A && git commit -qm v0.2.0 && git tag v0.2.0

printf 'more\n' >> added.txt
changelog 0.3.0 0.2.0 0.1.0 > CHANGELOG.md
printf 'v0.3.0\n' > .template-version
git add -A && git commit -qm v0.3.0 && git tag v0.3.0
cd "$ROOT" || exit 1

# make_instance <dir> <tag>: the release's files in a new repo, .template removed (as /setup does).
make_instance() {
  local dir="$1" tag="$2"
  git init -q "$dir"
  git -C "$T" archive "$tag" | tar -x -C "$dir"
  rm -f "$dir/.template"
  git -C "$dir" add -A && git -C "$dir" commit -qm "instance from $tag"
}

# --------------------------------------------------------------------------
banner "(1) refusals before anything is fetched"
run "$T" v0.2.0
check_exit 2 "$RC"
contains "$WORK/err" "this is the template itself"
I="$WORK/inst-noremote"; make_instance "$I" v0.1.0
run "$I" v0.2.0
check_exit 5 "$RC"
contains "$WORK/err" "no 'upstream' remote"

# --------------------------------------------------------------------------
I="$WORK/inst"; make_instance "$I" v0.1.0
git -C "$I" remote add upstream "$T"
git -C "$I" tag mine-v1     # the instance's own tag

banner "(2) listing"
run "$I"
check_exit 0 "$RC"
if [ "$(head -1 "$WORK/out")" = "v0.3.0" ]; then ok "newest first"; else bad "first line: $(head -1 "$WORK/out")"; fi
contains "$WORK/out" "v0.1.0  ← this instance"
if [ "$(git -C "$I" tag)" = "mine-v1" ]; then ok "the instance's tags are its own"; else bad "tags now: $(git -C "$I" tag | tr '\n' ' ')"; fi

banner "(3) refusals after the fetch"
run "$I" v9.9.9
check_exit 5 "$RC"
contains "$WORK/err" "no template release v9.9.9"
run "$I" v0.1.0 --from v0.2.0
check_exit 2 "$RC"
contains "$WORK/err" "is not after"
echo dirty >> "$I/shared.txt"
run "$I" v0.2.0
check_exit 2 "$RC"
contains "$WORK/err" "uncommitted changes"
git -C "$I" checkout -q -- shared.txt
I2="$WORK/inst-nofile"; make_instance "$I2" v0.1.0
git -C "$I2" rm -q .template-version && git -C "$I2" commit -qm "made before the file existed"
git -C "$I2" remote add upstream "$T"
run "$I2" v0.2.0
check_exit 5 "$RC"
contains "$WORK/err" "pass --from"
run "$I2" v0.2.0 --from v0.1.0
check_exit 0 "$RC"   # no local changes here, so nothing conflicts
if [ "$(cat "$I2/.template-version")" = "v0.2.0" ]; then ok "--from: .template-version written"; else bad "no .template-version after --from"; fi

# --------------------------------------------------------------------------
# The instance's own changes: edited-here.txt changed, deleted-here.txt and dropped.txt deleted,
# conflict.txt changed on the same line the template changes.
printf 'keep\nmine\n' > "$I/edited-here.txt"
git -C "$I" rm -q deleted-here.txt dropped.txt
printf 'ours\n' > "$I/conflict.txt"
git -C "$I" commit -qam "the instance's own changes"
head_before="$(git -C "$I" rev-parse HEAD)"

banner "(7) --dry-run"
wt_before="$(git -C "$I" worktree list | wc -l)"
run "$I" v0.2.0 --dry-run
check_exit 1 "$RC"
contains "$WORK/err" "would conflict"
contains "$WORK/err" "conflict.txt"
if [ -z "$(git -C "$I" status --porcelain)" ]; then ok "tree and index untouched"; else bad "dry run changed: $(git -C "$I" status --porcelain | tr '\n' ' ')"; fi
if [ "$(git -C "$I" worktree list | wc -l)" = "$wt_before" ]; then ok "no worktree left behind"; else bad "a worktree was left behind"; fi

banner "(5)+(6) a pull with a deleted file and a conflict"
run "$I" v0.2.0
check_exit 1 "$RC"
if [ "$(git -C "$I" rev-parse HEAD)" = "$head_before" ]; then ok "nothing committed"; else bad "HEAD moved"; fi
if git -C "$I" diff --name-only --diff-filter=U | grep -qx conflict.txt; then ok "conflict.txt unmerged"; else bad "conflict.txt not unmerged"; fi
if grep -q '^<<<<<<<' "$I/conflict.txt"; then ok "conflict markers"; else bad "no conflict markers"; fi
contains "$WORK/err" "Conflicts"
contains "$WORK/err" "Skipped — changed in the template, but deleted here"
contains "$WORK/err" "deleted-here.txt"
absent   "$WORK/err" "dropped.txt"
if [ ! -e "$I/deleted-here.txt" ]; then ok "a file deleted here stays deleted"; else bad "deleted-here.txt came back"; fi

banner "(4) what a pull stages"
if [ "$(cat "$I/shared.txt")" = "$(printf 'a\nB\nc')" ]; then ok "the template's change applied"; else bad "shared.txt: $(cat "$I/shared.txt")"; fi
if [ "$(cat "$I/edited-here.txt")" = "$(printf 'keep\nmine')" ]; then ok "a local change kept"; else bad "edited-here.txt: $(cat "$I/edited-here.txt")"; fi
if git -C "$I" diff --cached --name-only | grep -qx added.txt; then ok "a new file staged"; else bad "added.txt not staged"; fi
if [ "$(cat "$I/.template-version")" = "v0.2.0" ]; then ok ".template-version is v0.2.0"; else bad ".template-version: $(cat "$I/.template-version")"; fi
contains "$WORK/out" "## [0.2.0]"
contains "$WORK/out" "### Migrating from 0.1"
absent   "$WORK/out" "## [0.1.0]"
absent   "$WORK/out" "## [Unreleased]"

banner "(4) a clean pull, two releases at once"
printf 'theirs\n' > "$I/conflict.txt"   # resolved: the template's side
git -C "$I" add -A && git -C "$I" commit -qm "template: v0.1.0 → v0.2.0"
run "$I" v0.3.0
check_exit 0 "$RC"
if [ "$(cat "$I/added.txt")" = "$(printf 'new\nmore')" ]; then ok "v0.3.0 applied"; else bad "added.txt: $(cat "$I/added.txt")"; fi
contains "$WORK/out" "## [0.3.0]"
absent   "$WORK/out" "## [0.2.0]"
git -C "$I" commit -qm "template: v0.2.0 → v0.3.0"

banner "(8) already there"
run "$I" v0.3.0
check_exit 0 "$RC"
contains "$WORK/err" "already on v0.3.0"

# --------------------------------------------------------------------------
banner "(9) part of a release already taken by hand"
T2="$WORK/template2"
git init -q "$T2"
printf 'p\n' > "$T2/plain.txt"
printf 'x\n' > "$T2/oldname.txt"
printf 'r\n' > "$T2/removed.txt"
touch "$T2/.template"
printf '# Changelog\n\n## [1.0.0] — 2026-01-01\n\n- first\n' > "$T2/CHANGELOG.md"
printf 'v1.0.0\n' > "$T2/.template-version"
git -C "$T2" add -A && git -C "$T2" commit -qm v1.0.0 && git -C "$T2" tag v1.0.0
git -C "$T2" mv oldname.txt newname.txt
git -C "$T2" rm -q removed.txt
printf 'p2\n' > "$T2/plain.txt"
printf 'same\n' > "$T2/added-same.txt"
printf '# Changelog\n\n## [1.1.0] — 2026-01-02\n\n- second\n\n## [1.0.0] — 2026-01-01\n\n- first\n' > "$T2/CHANGELOG.md"
printf 'v1.1.0\n' > "$T2/.template-version"
git -C "$T2" add -A && git -C "$T2" commit -qm v1.1.0 && git -C "$T2" tag v1.1.0
I3="$WORK/inst-partial"
git init -q "$I3"
git -C "$T2" archive v1.0.0 | tar -x -C "$I3"
rm -f "$I3/.template"
printf 'mine\n' > "$I3/newname.txt"
printf 'r, changed here\n' > "$I3/removed.txt"
printf 'same\n' > "$I3/added-same.txt"
git -C "$I3" add -A && git -C "$I3" commit -qm "instance, part of 1.1.0 by hand"
git -C "$I3" remote add upstream "$T2"
run "$I3" v1.1.0 --dry-run
check_exit 1 "$RC"
contains "$WORK/err" "already here with other contents"
contains "$WORK/err" "  newname.txt"
contains "$WORK/err" "Deleted in the template, but changed here"
contains "$WORK/err" "  removed.txt"
if [ -z "$(git -C "$I3" status --porcelain)" ]; then ok "dry run left the tree alone"; else bad "dry run changed the tree"; fi
run "$I3" v1.1.0
check_exit 1 "$RC"
if [ "$(cat "$I3/plain.txt")" = p2 ]; then ok "the rest of the release applied"; else bad "plain.txt not updated"; fi
if [ ! -e "$I3/oldname.txt" ]; then ok "the rename's old name removed"; else bad "oldname.txt still there"; fi
if [ "$(cat "$I3/newname.txt")" = mine ]; then ok "a file already here kept as yours"; else bad "newname.txt overwritten"; fi
if [ "$(cat "$I3/removed.txt")" = "r, changed here" ]; then ok "a changed file the template deleted kept"; else bad "removed.txt lost"; fi
absent "$WORK/err" "added-same.txt"
if [ "$(cat "$I3/.template-version")" = v1.1.0 ]; then ok ".template-version is v1.1.0"; else bad ".template-version not updated"; fi
if git -C "$I3" diff --cached --name-only | grep -qx plain.txt; then ok "staged, not committed"; else bad "plain.txt not staged"; fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
