#!/usr/bin/env bash
# tests/vault-setup.sh — drive bin/vault-setup through eight simulated machines.
#
# Usage: ./tests/vault-setup.sh
#
# Every case gets its own temporary HOME and CC_VAULT and a PATH of stub executables over a
# hermetic $SYSBIN — symlinks to a named list of system tools and nothing else — so no tool
# the runner happens to have can leak in, and nothing outside the temporary directory is read
# or written. `curl` and `gh` are stubs: no case reaches the network, and each stub appends its
# own invocation to $CC_STUB_LOG, which carries the assertions that matter most — a dry run
# downloads nothing, and a refusal creates nothing.
#
# `git` and `gitleaks` are the exceptions: git is real, because the point of the first case is
# that the vault really becomes a repo, and gitleaks is a stub that passes, so the pre-commit
# hook the script installs can run on a machine without it.
#
# Cases: (i) a fresh vault · (ii) running it again is a no-op · (iii) a directory that is not a
# vault is refused · (iv) an existing community-plugins.json is merged and an existing app.json
# kept · (v) a manifest whose id is wrong installs nothing · (vi) --dry-run touches nothing ·
# (vii) --create-remote refuses a public repo · (viii) --upgrade re-fetches.
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/vault-setup"
[ -x "$SCRIPT" ] || { echo "bin/vault-setup is not executable" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cc-vault-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

# ---- the hermetic system PATH ---------------------------------------------
SYSBIN="$WORK/sysbin"
mkdir -p "$SYSBIN"

# Everything vault-setup, lib/common.sh and the pre-commit hook actually run. `curl`, `gh` and
# `gitleaks` are deliberately absent: they are stubbed per case.
SYS_TOOLS="sh bash env cat ls mkdir rmdir rm cp mv ln chmod touch mktemp date jq git
awk sed grep cut tr head tail sort uniq wc tee stat find dirname basename
id uname printf test true false expr"

for t in $SYS_TOOLS; do
  p="$(command -v "$t" 2>/dev/null)"
  case "$p" in
    /*) ln -sf "$p" "$SYSBIN/$t" ;;
    ?*) : ;;   # a shell builtin: always there, nothing to link
    *)  printf 'tests/vault-setup.sh: required system tool not found: %s\n' "$t" >&2; exit 1 ;;
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
is_file() { if [ -f "$1" ]; then ok "wrote $2"; else bad "no $2 at $1"; fi; }
no_file() { if [ -e "$1" ]; then bad "should not exist: $2"; else ok "absent: $2"; fi; }
json_is() { # json_is <file> <jq filter> <want> <what>
  local got; got="$(jq -c "$2" "$1" 2>/dev/null)"
  if [ "$got" = "$3" ]; then ok "$4"; else bad "$4: want $3, got ${got:-<nothing>}"; fi
}

# stub <dir> <name>, body on stdin. Every stub logs itself first.
stub() {
  local d="$1" n="$2"
  mkdir -p "$d"
  {
    echo '#!/bin/sh'
    # Single quotes on purpose: this is the stub's source, expanded when it runs.
    # shellcheck disable=SC2016
    printf 'printf %s %s >> "$CC_STUB_LOG"\n' "'%s %s\\n'" "'$n' \"\$*\""
    cat
  } > "$d/$n"
  chmod +x "$d/$n"
}

# The registry every case is served, cut down to the three ids the script asks for plus one
# other, so "match by id" is doing real work.
cat > "$WORK/community-plugins.json" <<'EOF'
[
  {"id":"omnisearch","name":"Omnisearch","repo":"scambier/obsidian-omnisearch"},
  {"id":"dataview","name":"Dataview","repo":"blacksmithgu/obsidian-dataview"},
  {"id":"obsidian-git","name":"Git","repo":"Vinzent03/obsidian-git"},
  {"id":"templater-obsidian","name":"Templater","repo":"SilentVoid13/Templater"}
]
EOF

# curl: the registry, a latest-release tag, and the three release assets. It answers from
# $CC_TEST_TAG and $CC_TEST_BAD_ID, so a case can vary what GitHub says without a new stub.
stub_curl() {
  stub "$1" curl <<'EOF'
url=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
emit() { if [ -n "$out" ]; then cat > "$out"; else cat; fi; }
id_of() {
  case "$1" in
    *obsidian-git*) echo obsidian-git ;;
    *dataview*)     echo dataview ;;
    *Templater*)    echo templater-obsidian ;;
    *)              echo unknown ;;
  esac
}
case "$url" in
  *community-plugins.json)
    cat "$CC_TEST_REGISTRY" | emit ;;
  */releases/latest)
    printf '{"tag_name":"%s"}\n' "${CC_TEST_TAG:-1.2.3}" | emit ;;
  */releases/download/*/main.js)
    printf '// stub plugin code\n' | emit ;;
  */releases/download/*/manifest.json)
    id="$(id_of "$url")"
    [ "$id" = "${CC_TEST_BAD_ID:-}" ] && id="not-what-you-asked-for"
    printf '{"id":"%s","name":"%s","version":"%s","minAppVersion":"1.5.0"}\n' \
      "$id" "$id" "${CC_TEST_TAG:-1.2.3}" | emit ;;
  */releases/download/*/styles.css)
    printf '/* stub */\n' | emit ;;
  *)
    echo "curl: unexpected URL: $url" >&2; exit 22 ;;
esac
exit 0
EOF
}

# gh: <dir> <authed: yes|no> <visibility of the repo it is asked about: PUBLIC|PRIVATE|none>
stub_gh() {
  local d="$1" authed="$2" vis="$3"
  stub "$d" gh <<EOF
case "\$*" in
  "auth status") [ "$authed" = yes ] && exit 0 || exit 1 ;;
  "api user"*) echo "you"; exit 0 ;;
  "api repos/"*) exit 1 ;;   # fall through to curl, which every case stubs
  *"repo view"*visibility*) [ "$vis" = none ] && exit 1 || { echo "$vis"; exit 0; } ;;
  *"repo view"*sshUrl*) echo "git@github.com:you/vault.git"; exit 0 ;;
  *"repo create"*) exit 0 ;;
esac
exit 0
EOF
}

stub_gitleaks() { stub "$1" gitleaks <<'EOF'
exit 0
EOF
}

# ---- one case ------------------------------------------------------------
# case <name>: sets $CASE (its own directory), $HOME, $CC_VAULT, $BIN (its stubs), $OUT, $LOG.
n=0
case_new() {
  n=$((n + 1))
  printf '\n(%s) %s\n' "$n" "$1"
  CASE="$WORK/case$n"
  BIN="$CASE/bin"
  HOME="$CASE/home"
  OUT="$CASE/out.txt"
  LOG="$CASE/stub.log"
  mkdir -p "$BIN" "$HOME"
  : > "$LOG"
  stub_curl "$BIN"
  stub_gitleaks "$BIN"
  stub_gh "$BIN" no none
  VAULT="$HOME/vault"
}

run() { # run [args…] — vault-setup in this case's world; exit status in $rc
  ( PATH="$BIN:$SYSBIN" \
    HOME="$HOME" \
    CC_VAULT="$VAULT" \
    CC_STUB_LOG="$LOG" \
    CC_TEST_REGISTRY="$WORK/community-plugins.json" \
    CC_TEST_TAG="${CC_TEST_TAG:-1.2.3}" \
    CC_TEST_BAD_ID="${CC_TEST_BAD_ID:-}" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME="A Person" GIT_AUTHOR_EMAIL="you@example.com" \
    GIT_COMMITTER_NAME="A Person" GIT_COMMITTER_EMAIL="you@example.com" \
    "$SCRIPT" "$@" ) > "$OUT" 2>&1
  rc=$?
}

# =========================================================================
case_new "a fresh vault: created, three plugins installed, one commit"
run
check_exit 0 "$rc"
contains "$OUT" "create the vault at $VAULT"
contains "$OUT" "obsidian-git 1.2.3 ←"
contains "$OUT" "Turn on community plugins"
contains "$OUT" "https://obsidian.md/clipper"
is_file "$VAULT/CLAUDE.md" "the vault brain"
is_file "$VAULT/_templates/daily.md" "the Templater templates"
for p in obsidian-git dataview templater-obsidian; do
  is_file "$VAULT/.obsidian/plugins/$p/main.js" "$p/main.js"
  is_file "$VAULT/.obsidian/plugins/$p/manifest.json" "$p/manifest.json"
  is_file "$VAULT/.obsidian/plugins/$p/.source.json" "$p provenance"
done
is_file "$VAULT/.obsidian/plugins/VERSIONS.md" "VERSIONS.md"
contains "$VAULT/.obsidian/plugins/VERSIONS.md" "Vinzent03/obsidian-git"
json_is "$VAULT/.obsidian/community-plugins.json" '.' \
  '["obsidian-git","dataview","templater-obsidian"]' "community-plugins.json holds the three ids"
json_is "$VAULT/.obsidian/plugins/templater-obsidian/data.json" '.templates_folder' \
  '"_templates"' "Templater points at _templates"
json_is "$VAULT/.obsidian/daily-notes.json" '.folder' '"daily"' "daily notes land in daily/"
json_is "$VAULT/.obsidian/app.json" '.newFileFolderPath' '"inbox"' "new notes land in inbox/"
json_is "$VAULT/.obsidian/plugins/obsidian-git/data.json" '.autoSaveInterval' '0' \
  "Obsidian Git does not commit on a timer"
if [ -x "$VAULT/.git/hooks/pre-commit" ]; then ok "the gitleaks pre-commit hook is installed"
else bad "no executable .git/hooks/pre-commit in the vault"; fi
if [ "$(git -C "$VAULT" rev-list --count HEAD 2>/dev/null)" = "1" ]; then ok "one commit"
else bad "expected exactly one commit in the vault"; fi
tracked="$(git -C "$VAULT" ls-files)"
case "$tracked" in
  *main.js*) bad "plugin main.js was committed to the vault repo" ;;
  *) ok "no plugin binary in the repo" ;;
esac
case "$tracked" in
  *.obsidian/plugins/obsidian-git/manifest.json*) ok "plugin manifest.json is committed" ;;
  *) bad "manifest.json is not tracked" ;;
esac
# The work directory lives inside the vault, so `git add -A` used to commit a temporary file
# and then delete it: junk in the history, a dirty tree on a brand-new vault.
if [ -z "$(git -C "$VAULT" status --porcelain)" ]; then ok "the tree is clean after the first commit"
else bad "dirty after the first commit: $(git -C "$VAULT" status --porcelain | tr '\n' ' ')"; fi
case "$tracked" in
  *.vault-setup.*) bad "a work-directory file was committed" ;;
  *) ok "nothing from the work directory is tracked" ;;
esac

# Keep this vault: the next two cases build on it.
FIRST_VAULT="$VAULT"; FIRST_HOME="$HOME"

# =========================================================================
case_new "running it again changes nothing"
VAULT="$FIRST_VAULT"; HOME="$FIRST_HOME"
before="$(cd "$VAULT" && find . -path ./.git -prune -o -type f -print | sort)"
sum_before="$(cat "$VAULT/.obsidian/app.json" "$VAULT/.obsidian/community-plugins.json")"
commits_before="$(git -C "$VAULT" rev-list --count HEAD)"
run
check_exit 0 "$rc"
contains "$OUT" "already installed"
contains "$OUT" "keeping the app.json you already have"
log_lacks "$LOG" "main.js"
after="$(cd "$VAULT" && find . -path ./.git -prune -o -type f -print | sort)"
if [ "$before" = "$after" ]; then ok "the same files"; else bad "the file list changed"; fi
if [ "$sum_before" = "$(cat "$VAULT/.obsidian/app.json" "$VAULT/.obsidian/community-plugins.json")" ]
then ok "app.json and community-plugins.json unchanged"; else bad "config was rewritten"; fi
if [ "$commits_before" = "$(git -C "$VAULT" rev-list --count HEAD)" ]; then ok "no new commit"
else bad "it committed again"; fi

# =========================================================================
case_new "an existing community-plugins.json is merged, an existing app.json kept"
VAULT="$FIRST_VAULT"; HOME="$FIRST_HOME"
printf '["omnisearch"]\n' > "$VAULT/.obsidian/community-plugins.json"
printf '{"theme":"obsidian","readableLineLength":false}\n' > "$VAULT/.obsidian/app.json"
run
check_exit 0 "$rc"
json_is "$VAULT/.obsidian/community-plugins.json" '.' \
  '["omnisearch","obsidian-git","dataview","templater-obsidian"]' "the user's plugin stays, first"
json_is "$VAULT/.obsidian/app.json" '.readableLineLength' 'false' "the user's app.json is untouched"

# =========================================================================
case_new "a directory that is not a vault is refused"
mkdir -p "$VAULT"
printf 'tax returns\n' > "$VAULT/important.txt"
run
check_exit 2 "$rc"
contains "$OUT" "is not a vault"
no_file "$VAULT/.obsidian" ".obsidian in someone else's directory"
no_file "$VAULT/CLAUDE.md" "a brain in someone else's directory"
is_file "$VAULT/important.txt" "their file, still there"

# =========================================================================
case_new "a manifest whose id is wrong installs nothing"
CC_TEST_BAD_ID=dataview
run
check_exit 1 "$rc"
contains "$OUT" "refusing to install it"
is_file "$VAULT/.obsidian/plugins/obsidian-git/manifest.json" "the plugin before it"
no_file "$VAULT/.obsidian/plugins/dataview" "the bad plugin's directory"
if [ -z "$(ls -d "$VAULT"/.obsidian/.vault-setup.* 2>/dev/null)" ]; then ok "no work directory left behind"
else bad "a half-written work directory survived"; fi
CC_TEST_BAD_ID=""

# =========================================================================
case_new "--dry-run touches nothing"
run --dry-run
check_exit 0 "$rc"
contains "$OUT" "would copy"
contains "$OUT" "1.2.3 ←"            # it still says what it would fetch, and from where
contains "$OUT" "would write"
no_file "$VAULT" "the vault"
log_lacks "$LOG" "releases/download"
log_lacks "$LOG" "repo create"

# =========================================================================
case_new "--create-remote refuses a repo that is already public"
stub_gh "$BIN" yes PUBLIC
run --create-remote
check_exit 1 "$rc"
contains "$OUT" "is PUBLIC"
contains "$LOG" "repo view you/vault"   # owner-qualified: a bare name resolves against a cwd remote
log_lacks "$LOG" "repo create"

# =========================================================================
case_new "--upgrade re-fetches"
run
check_exit 0 "$rc"
CC_TEST_TAG=9.9.9
run --upgrade
check_exit 0 "$rc"
contains "$OUT" "dataview 9.9.9 ←"
json_is "$VAULT/.obsidian/plugins/dataview/manifest.json" '.version' '"9.9.9"' "the new version is on disk"
json_is "$VAULT/.obsidian/plugins/dataview/.source.json" '.tag' '"9.9.9"' "the provenance is the new tag"
contains "$VAULT/.obsidian/plugins/VERSIONS.md" "9.9.9"
# VERSIONS.md and the manifests are tracked, so an upgrade leaves real changes to review —
# but never a work-directory path, in the status or in the index.
if git -C "$VAULT" status --porcelain | grep -q 'vault-setup\.'; then
  bad "the work directory shows up in git status after --upgrade"
else ok "no work directory in git status after --upgrade"; fi
if git -C "$VAULT" ls-files | grep -q 'vault-setup\.'; then
  bad "a work-directory file is tracked after --upgrade"
else ok "nothing from the work directory is tracked after --upgrade"; fi
CC_TEST_TAG=1.2.3

# =========================================================================
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
