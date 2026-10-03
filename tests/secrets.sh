#!/usr/bin/env bash
# tests/secrets.sh — drive bin/secrets and the sops helpers in lib/common.sh with real sops and
# age, on throwaway keys.
#
# Usage: ./tests/secrets.sh
#
# Every run builds a fake instance under `mktemp -d` (CC_ROOT points at it) and gives each
# machine its own temporary HOME, so the age keys are created there and nothing reads or
# writes ~/.config/sops, a real key, or a real repo. Commands run under `env -i` with a
# hermetic PATH: sops, age-keygen, jq and git are the real tools, `scutil`/`hostname` are stubs
# that name the machine. No value used here is a real secret.
#
# Cases: help · status without a key · init --first (key modes, age_recipient, .sops.yaml,
# encrypted store, commit) · set from stdin and from a file, values never in output, argv-free ·
# reading back (missing → 5, plaintext → 1, another key → 4) · check · import-env (quotes,
# export, comments, well-known names, --map, --dry-run, skip existing) · env and exec · a second
# machine: init, admit, recipients --check, revoke · push not built · sops too old · the paper
# key through a pty, when `script` is available · gitleaks on ciphertext and on a key, when
# gitleaks is installed.
#
# Exit codes: 0 every case passed · 1 a case failed · 3 sops, age-keygen, jq or git missing
#
# bash 3.2: no associative arrays, no mapfile.
# SC2015: `ok` and `bad` never fail, so A && ok || bad is if-then-else here.
# SC2016: the single-quoted scripts run in the case's own shell, which expands them.
# shellcheck disable=SC2015,SC2016
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"

for t in sops age-keygen jq git; do
  command -v "$t" >/dev/null 2>&1 || { echo "tests/secrets.sh: needs $t" >&2; exit 3; }
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/cc-secrets-test.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; sed 's/^/         | /' "$OUT" >&2; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "no '$2' in $(basename "$1")"; fi; }
lacks() { if grep -qF -- "$2" "$1"; then bad "LEAKED/unexpected: '$2' in $(basename "$1")"; else ok "no '$2' in $(basename "$1")"; fi; }
n=0
case_new() { n=$((n + 1)); printf '\n(%s) %s\n' "$n" "$1"; }

# ---- hermetic PATH ----------------------------------------------------------
SYSBIN="$WORK/sysbin"
mkdir -p "$SYSBIN"
for t in sh bash env cat ls mkdir rmdir rm cp mv chmod touch mktemp date jq awk sed grep cut tr \
  head tail sort uniq wc stat find dirname basename id uname printf test true false expr paste \
  fold sleep sops age-keygen git od; do
  p="$(command -v "$t" 2>/dev/null)"
  case "$p" in /*) ln -sf "$p" "$SYSBIN/$t" ;; esac
done
# git needs its helpers next to it on some systems; let it find them through its exec-path.
GIT_EXEC_PATH="$(git --exec-path)"

# A fake instance: the real bin/secrets and lib/, an example file, one machine file per host.
INST="$WORK/instance"
mkdir -p "$INST/bin" "$INST/lib" "$INST/secrets" "$INST/docs/machines"
cp "$REPO/bin/secrets" "$INST/bin/"
cp "$REPO/lib/common.sh" "$INST/lib/"
cp "$REPO/secrets/secrets.example.yaml" "$INST/secrets/"
for h in alpha beta; do
  sed -e "s/^host: .*/host: $h/" "$REPO/docs/machines/_example.md" > "$INST/docs/machines/$h.md"
done
cp "$REPO/docs/machines/_example.md" "$INST/docs/machines/"
STORE="$INST/secrets/secrets.yaml"

# per-machine stubs: scutil and hostname answer the host's name
mkbin() { # mkbin <host> → $WORK/bin-<host>
  local d="$WORK/bin-$1"
  mkdir -p "$d"
  printf '#!/bin/sh\necho %s\n' "$1" > "$d/scutil"
  printf '#!/bin/sh\necho %s\n' "$1" > "$d/hostname"
  chmod +x "$d/scutil" "$d/hostname"
}
mkbin alpha; mkbin beta
mkdir -p "$WORK/home-alpha" "$WORK/home-beta"

OUT="$WORK/out.txt"
# on <host> <cmd…> — run in that machine's world; output in $OUT, status in $rc
on() {
  local h="$1"; shift
  env -i PATH="$WORK/bin-$h:$SYSBIN" HOME="$WORK/home-$h" TMPDIR="$WORK" CC_ROOT="$INST" \
    GIT_EXEC_PATH="$GIT_EXEC_PATH" GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
    GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com \
    "$@" > "$OUT" 2>&1
  rc=$?
}
# get <host> <name> <field> — read one value through cc_sops_get; value in $OUT
get() { on "$1" bash -c '. "$CC_ROOT/lib/common.sh"; cc_sops_get "$1" "$2"' _ "$2" "$3"; }
S="$INST/bin/secrets"
mode_of() { if [ "$(uname -s)" = Darwin ]; then stat -f '%Lp' "$1"; else stat -c '%a' "$1"; fi; }

git -C "$INST" init -q
on alpha git -C "$INST" add -A && on alpha git -C "$INST" commit -q -m init

# =========================================================================
case_new "--help, and status before anything exists"
on alpha "$S" --help
check_exit 0 "$rc"
on alpha "$S" status
check_exit 4 "$rc"
contains "$OUT" "none at"
on alpha "$S" bogus
check_exit 2 "$rc"

# =========================================================================
case_new "init --first on a machine with no machine file is refused"
mv "$INST/docs/machines/alpha.md" "$WORK/alpha.md"
on alpha "$S" init --first
check_exit 5 "$rc"
mv "$WORK/alpha.md" "$INST/docs/machines/alpha.md"

case_new "init --first: key, age_recipient, .sops.yaml, an encrypted empty store, one commit"
on alpha "$S" init --first
check_exit 0 "$rc"
KA="$WORK/home-alpha/.config/sops/age/keys.txt"
[ "$(mode_of "$KA")" = 600 ] && ok "key mode 600" || bad "key mode $(mode_of "$KA")"
[ "$(mode_of "$(dirname "$KA")")" = 700 ] && ok "key dir mode 700" || bad "key dir mode"
PA="$(age-keygen -y "$KA")"
grep -qx "age_recipient: $PA" "$INST/docs/machines/alpha.md" && ok "age_recipient recorded" || bad "age_recipient missing"
grep -qF "$PA" "$INST/.sops.yaml" && ok ".sops.yaml names alpha's key" || bad ".sops.yaml"
grep -q '^sops:' "$STORE" && ok "store is a sops file" || bad "store not encrypted"
git -C "$INST" log -1 --format=%s | grep -qx '\[alpha\] secrets: init alpha' && ok "commit [alpha] secrets: init alpha" || bad "commit subject: $(git -C "$INST" log -1 --format=%s)"
on alpha "$S" status
check_exit 0 "$rc"
contains "$OUT" "recipient:  yes"
on alpha "$S" init --first
check_exit 2 "$rc"

# =========================================================================
case_new "set from stdin and from a file: encrypted, committed, never printed"
on alpha sh -c 'printf "fake-tavily-0001" | "$0" set tavily.api_key --stdin' "$S"
check_exit 0 "$rc"
lacks "$OUT" "fake-tavily-0001"
lacks "$STORE" "fake-tavily-0001"
grep -q '^    api_key: ENC\[' "$STORE" && ok "value is ENC[…]" || bad "value not ENC"
printf 'fake-chat-42\n' > "$WORK/chat.txt"
on alpha "$S" set telegram.chat_id --from-file "$WORK/chat.txt"
check_exit 0 "$rc"
if git -C "$INST" log -p | grep -q 'fake-tavily-0001\|fake-chat-42'; then bad "value in git history"; else ok "no value in git history"; fi
get alpha tavily api_key
check_exit 0 "$rc"
[ "$(cat "$OUT")" = "fake-tavily-0001" ] && ok "reads back exactly" || bad "read back: $(cat "$OUT")"
get alpha telegram chat_id
[ "$(od -c < "$OUT" | head -1)" = "$(printf 'fake-chat-42' | od -c | head -1)" ] && ok "trailing newline from the file dropped" || bad "file value: $(od -c < "$OUT" | head -2)"
on alpha bash -c '. "$CC_ROOT/lib/common.sh"; cc_secret tavily api_key'
[ "$(cat "$OUT")" = "fake-tavily-0001" ] && ok "cc_secret (the wrappers' reader) reads it" || bad "cc_secret: $(cat "$OUT")"
on alpha bash -c '. "$CC_ROOT/lib/common.sh"; cc_secret tavily'
check_exit 2 "$rc"
if PY="$(command -v python3)"; then
  cp "$REPO/lib/cc.py" "$INST/lib/"
  on alpha "$PY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import cc; sys.stdout.write(cc.secret("telegram", "chat_id"))' "$INST/lib"
  [ "$(cat "$OUT")" = "fake-chat-42" ] && ok "cc.secret (the Python reader) reads it" || bad "cc.secret: $(cat "$OUT")"
  on alpha "$PY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import cc
try: cc.secret("exa", "api_key")
except cc.CCError as e: sys.exit(e.code)' "$INST/lib"
  check_exit 5 "$rc"
fi
on alpha sh -c 'printf "fake-typed" | "$0" set tavily.api_key' "$S"
check_exit 2 "$rc"
contains "$OUT" "no terminal to prompt on"
on alpha "$S" set tavily
check_exit 2 "$rc"
on alpha "$S" set 'x"].y'
check_exit 2 "$rc"

# =========================================================================
case_new "reading: not set → 5, plaintext → 1"
get alpha exa api_key
check_exit 5 "$rc"
cp "$STORE" "$WORK/store.bak"
printf 'leaked:\n    api_key: plaintext-value\n' > "$WORK/plain.yaml"
cat "$WORK/plain.yaml" "$STORE" > "$WORK/mixed.yaml" && cp "$WORK/mixed.yaml" "$STORE"
get alpha leaked api_key
check_exit 1 "$rc"
on alpha "$S" status
check_exit 1 "$rc"
contains "$OUT" "NOT encrypted"
cp "$WORK/store.bak" "$STORE"

# =========================================================================
case_new "check: names only"
on alpha "$S" check
check_exit 5 "$rc"
contains "$OUT" "set      tavily.api_key"
contains "$OUT" "missing  exa.api_key"
lacks "$OUT" "fake-tavily-0001"

# =========================================================================
case_new "import-env --dry-run: mapping only, nothing written"
cat > "$WORK/fake.env" <<'EOF'
# a fake dotenv file — nothing here is a real secret
export TAVILY_API_KEY=fake-tavily-0002
TELEGRAM_BOT_TOKEN="fake:bot \"quoted\" token"
STRIPE_SECRET_KEY='sk_fake_single $NOT_EXPANDED'
RESEND_API_KEY=fake-resend   # a trailing comment
  export   SPACED_NAME = fake-spaced
EMPTY_ONE=
CUSTOM_THING=fake-custom
EOF
before="$(cat "$STORE")"
on alpha "$S" import-env "$WORK/fake.env" --dry-run --map CUSTOM_THING=custom.value
check_exit 0 "$rc"
contains "$OUT" "TAVILY_API_KEY → tavily.api_key (already set"
contains "$OUT" "TELEGRAM_BOT_TOKEN → telegram.token"
contains "$OUT" "STRIPE_SECRET_KEY → env.stripe_secret_key"
contains "$OUT" "CUSTOM_THING → custom.value"
contains "$OUT" "EMPTY_ONE → env.empty_one (skipped)"
for v in fake-tavily-0002 fake:bot sk_fake fake-resend fake-spaced fake-custom; do lacks "$OUT" "$v"; done
[ "$before" = "$(cat "$STORE")" ] && ok "store unchanged" || bad "dry run changed the store"

case_new "import-env: every value through sops set, names and counts only"
on alpha "$S" import-env "$WORK/fake.env" --map CUSTOM_THING=custom.value
check_exit 0 "$rc"
contains "$OUT" "5 set, 2 skipped, 0 unreadable"
for v in fake-tavily-0002 fake:bot sk_fake fake-resend fake-spaced fake-custom; do lacks "$OUT" "$v"; lacks "$STORE" "$v"; done
get alpha telegram token
[ "$(cat "$OUT")" = 'fake:bot "quoted" token' ] && ok "double quotes unescaped" || bad "telegram.token: $(cat "$OUT")"
get alpha env stripe_secret_key
[ "$(cat "$OUT")" = 'sk_fake_single $NOT_EXPANDED' ] && ok "single quotes literal" || bad "stripe: $(cat "$OUT")"
get alpha env resend_api_key
[ "$(cat "$OUT")" = 'fake-resend' ] && ok "inline comment dropped" || bad "resend: $(cat "$OUT")"
get alpha env spaced_name
[ "$(cat "$OUT")" = 'fake-spaced' ] && ok "spaces around = tolerated" || bad "spaced: $(cat "$OUT")"
get alpha tavily api_key
[ "$(cat "$OUT")" = 'fake-tavily-0001' ] && ok "existing value kept without --overwrite" || bad "tavily overwritten"
printf 'BROKEN="no end\n' > "$WORK/bad.env"
on alpha "$S" import-env "$WORK/bad.env"
check_exit 1 "$rc"
contains "$OUT" "unterminated quote"
lacks "$OUT" "no end"

# =========================================================================
case_new "env and exec: chosen secrets in the environment"
on alpha "$S" exec --only TAVILY_API_KEY,STRIPE_SECRET_KEY,MY_CHAT=telegram.chat_id -- \
  sh -c '[ "$TAVILY_API_KEY" = fake-tavily-0001 ] && [ "$STRIPE_SECRET_KEY" = "sk_fake_single \$NOT_EXPANDED" ] && [ "$MY_CHAT" = fake-chat-42 ] && [ -z "${RESEND_API_KEY:-}" ]'
check_exit 0 "$rc"
on alpha "$S" exec --all-env -- sh -c '[ "$RESEND_API_KEY" = fake-resend ] && [ "$SPACED_NAME" = fake-spaced ] && [ -z "${TAVILY_API_KEY:-}" ]'
check_exit 0 "$rc"
on alpha "$S" exec --only EXA_API_KEY -- true
check_exit 5 "$rc"
contains "$OUT" "EXA_API_KEY (exa.api_key)"
on alpha "$S" exec --only TAVILY_API_KEY
check_exit 2 "$rc"
on alpha "$S" exec -- true
check_exit 2 "$rc"
on alpha "$S" env --only TAVILY_API_KEY
check_exit 0 "$rc"
contains "$OUT" "export TAVILY_API_KEY='fake-tavily-0001'"

# =========================================================================
case_new "a second machine: init, not yet a recipient, admit, read, recipients --check"
on beta "$S" init
check_exit 0 "$rc"
contains "$OUT" "secrets admit beta"
get beta tavily api_key
check_exit 4 "$rc"
on beta "$S" status
check_exit 4 "$rc"
on alpha "$S" recipients --check
check_exit 1 "$rc"
on alpha "$S" admit beta
check_exit 0 "$rc"
get beta tavily api_key
[ "$(cat "$OUT")" = fake-tavily-0001 ] && ok "beta reads the store after admit" || bad "beta: $(cat "$OUT")"
on alpha "$S" recipients --check
check_exit 0 "$rc"
on beta sh -c 'printf "fake-exa-0003" | "$0" set exa.api_key --stdin' "$S"
check_exit 0 "$rc"

case_new "revoke beta: recipient gone, data key rotated, list of what to rotate"
on alpha "$S" revoke beta
check_exit 0 "$rc"
contains "$OUT" "tavily.api_key"
contains "$OUT" "env.stripe_secret_key"
grep -q '^age_recipient:' "$INST/docs/machines/beta.md" && bad "beta still has age_recipient" || ok "age_recipient removed from beta.md"
get beta tavily api_key
check_exit 4 "$rc"
get alpha exa api_key
[ "$(cat "$OUT")" = fake-exa-0003 ] && ok "alpha still reads everything" || bad "alpha after revoke"
on alpha "$S" revoke alpha
check_exit 2 "$rc"

# =========================================================================
if [ -n "${PY:-}" ]; then
  case_new "Google token: refreshed in memory; written back (and committed) only for a new refresh token"
  # Fake google-auth modules: an always-expired token whose refresh hands out the refresh token
  # named in FAKE_NEW_REFRESH (or keeps the old one).
  F="$WORK/pyfake"
  mkdir -p "$F/google/auth/transport" "$F/google/oauth2" "$F/google_auth_oauthlib"
  : > "$F/google/__init__.py"; : > "$F/google/auth/__init__.py"; : > "$F/google/auth/transport/__init__.py"
  : > "$F/google/oauth2/__init__.py"; : > "$F/google_auth_oauthlib/__init__.py"
  echo 'class Request: pass' > "$F/google/auth/transport/requests.py"
  echo 'class InstalledAppFlow: pass' > "$F/google_auth_oauthlib/flow.py"
  cat > "$F/google/oauth2/credentials.py" <<'PY'
import json, os
class Credentials:
    valid, expired = False, True
    def __init__(self, info): self.refresh_token = info["refresh_token"]
    @classmethod
    def from_authorized_user_info(cls, info, scopes): return cls(info)
    def refresh(self, request): self.refresh_token = os.environ.get("FAKE_NEW_REFRESH") or self.refresh_token
    def to_json(self): return json.dumps({"refresh_token": self.refresh_token})
PY
  cp "$REPO/lib/google_auth.py" "$INST/lib/"
  printf '{"refresh_token": "fake-refresh-1"}' > "$WORK/tok.json"
  on alpha "$S" set google.token --from-file "$WORK/tok.json"
  c0="$(git -C "$INST" rev-list --count HEAD)"
  gauth() { on alpha env ${1:+FAKE_NEW_REFRESH="$1"} "$PY" -c 'import sys; sys.path[:0] = sys.argv[1:3]; import google_auth; google_auth.credentials()' "$INST/lib" "$F"; }
  gauth ""
  check_exit 0 "$rc"
  [ "$(git -C "$INST" rev-list --count HEAD)" = "$c0" ] && ok "same refresh token: nothing written, nothing committed" || bad "a refresh with no new token committed"
  gauth fake-refresh-2
  check_exit 0 "$rc"
  [ "$(git -C "$INST" rev-list --count HEAD)" = "$((c0 + 1))" ] && ok "new refresh token: one commit" || bad "new refresh token not committed"
  git -C "$INST" log -1 --format=%s | grep -qx '\[alpha\] secrets: set google.token' && ok "commit [alpha] secrets: set google.token" || bad "commit subject"
  get alpha google token
  grep -q fake-refresh-2 "$OUT" && ok "store holds the new refresh token" || bad "store not updated"
  lacks "$STORE" "fake-refresh-2"
fi

# =========================================================================
case_new "no value is ever an argument: every sops and jq call logged"
mkdir -p "$WORK/argvlog"
for t in sops jq; do
  printf '#!/bin/sh\nprintf "%%s\\n" "%s $*" >> "%s"\nexec "%s" "$@"\n' "$t" "$WORK/argv.log" "$(command -v "$t")" > "$WORK/argvlog/$t"
  chmod +x "$WORK/argvlog/$t"
done
: > "$WORK/argv.log"
on alpha env PATH="$WORK/argvlog:$WORK/bin-alpha:$SYSBIN" sh -c 'printf "fake-argv-0004" | "$0" set jina.api_key --stdin' "$S"
check_exit 0 "$rc"
printf 'EXA_API_KEY=fake-argv-0005\n' > "$WORK/argv.env"
on alpha env PATH="$WORK/argvlog:$WORK/bin-alpha:$SYSBIN" "$S" import-env "$WORK/argv.env" --overwrite
check_exit 0 "$rc"
on alpha env PATH="$WORK/argvlog:$WORK/bin-alpha:$SYSBIN" "$S" exec --only JINA_API_KEY -- sh -c :
check_exit 0 "$rc"
grep -q '^sops set --value-stdin' "$WORK/argv.log" && ok "sops set was called" || bad "argv log is empty"
lacks "$WORK/argv.log" "fake-argv-0004"
lacks "$WORK/argv.log" "fake-argv-0005"

# =========================================================================
case_new "security-check: age-key, secrets-encrypted, instance-remote"
cp "$REPO/bin/security-check" "$INST/bin/"
sec() { on alpha "$INST/bin/security-check"; grep -E " (age-key|secrets-encrypted|instance-remote) " "$OUT" > "$WORK/sec.txt"; }
sec
contains "$WORK/sec.txt" "PASS age-key"
contains "$WORK/sec.txt" "PASS secrets-encrypted"
contains "$WORK/sec.txt" "PASS instance-remote — local only"
chmod 644 "$KA"
sec
contains "$WORK/sec.txt" "FAIL age-key — $KA is mode 644"
chmod 600 "$KA"
cp "$STORE" "$WORK/store.bak"
cat "$WORK/plain.yaml" "$WORK/store.bak" > "$STORE"
sec
contains "$WORK/sec.txt" "FAIL secrets-encrypted — plaintext in the store: secrets/secrets.yaml: leaked.api_key"
lacks "$WORK/sec.txt" "plaintext-value"
cp "$WORK/store.bak" "$STORE"
cat "$KA" > "$WORK/twokeys"; age-keygen 2>/dev/null >> "$WORK/twokeys"; cp "$KA" "$WORK/ka.bak"; cp "$WORK/twokeys" "$KA"
sec
contains "$WORK/sec.txt" "holds 2 keys"
cp "$WORK/ka.bak" "$KA"
touch "$INST/.template"
sec
contains "$WORK/sec.txt" "SKIP instance-remote — this is the public template"
rm "$INST/.template"

if [ -n "${PY:-}" ]; then
  case_new "map-check secrets: recipient, .sops.yaml and the store agree"
  cp "$REPO/bin/map-check" "$INST/bin/"
  on alpha "$PY" "$INST/bin/map-check" --only secrets
  check_exit 0 "$rc"
  contains "$OUT" "## secrets: ok"
  cp "$INST/docs/machines/alpha.md" "$WORK/alpha.bak"
  sed -e 's/^age_recipient: .*/age_recipient: age1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq/' "$WORK/alpha.bak" > "$INST/docs/machines/alpha.md"
  on alpha "$PY" "$INST/bin/map-check" --only secrets
  check_exit 1 "$rc"
  contains "$OUT" "not this machine's key"
  contains "$OUT" ".sops.yaml: out of date"
  cp "$WORK/alpha.bak" "$INST/docs/machines/alpha.md"
fi

# =========================================================================
case_new "pre-commit hook: plaintext in a sops file, a decrypted store, the template's own rules"
mkdir -p "$INST/.githooks" "$WORK/bin-gl"
cp "$REPO/.githooks/pre-commit" "$INST/.githooks/"
# gitleaks is covered above; here it is a stub that passes, so only the hook's own rules decide.
printf '#!/bin/sh\nexit 0\n' > "$WORK/bin-gl/gitleaks"; chmod +x "$WORK/bin-gl/gitleaks"
hook() { on alpha env PATH="$WORK/bin-gl:$WORK/bin-alpha:$SYSBIN" sh -c 'cd "$0" && .githooks/pre-commit' "$INST"; }
unstage() { on alpha git -C "$INST" reset -q; }
git -C "$INST" add -A >/dev/null 2>&1; on alpha git -C "$INST" commit -q -m "test: settle"
cp "$STORE" "$WORK/store.bak"
printf '"fake-precommit"' | SOPS_AGE_KEY_FILE="$KA" sops set --value-stdin "$STORE" '["jina"]["api_key"]'
git -C "$INST" add secrets/secrets.yaml
hook
check_exit 0 "$rc"
cat "$WORK/plain.yaml" "$STORE" > "$WORK/mixed.yaml"; cp "$WORK/mixed.yaml" "$STORE"; git -C "$INST" add secrets/secrets.yaml
hook
check_exit 1 "$rc"
contains "$OUT" "plaintext values: leaked.api_key"
lacks "$OUT" "plaintext-value"
printf 'tavily:\n  api_key: fake-decrypted\n' > "$STORE"; git -C "$INST" add secrets/secrets.yaml
hook
check_exit 1 "$rc"
contains "$OUT" "is not sops-encrypted"
cp "$WORK/store.bak" "$STORE"; unstage
touch "$INST/.template"
cp "$INST/.sops.yaml" "$WORK/sops.bak"; echo "# changed" >> "$INST/.sops.yaml"
echo "age1fake" > "$INST/secrets/backup.pub"
git -C "$INST" add -f .sops.yaml secrets/backup.pub
hook
check_exit 1 "$rc"
contains "$OUT" "belong in your private instance"
contains "$OUT" "secrets/backup.pub"
unstage; cp "$WORK/sops.bak" "$INST/.sops.yaml"; rm -f "$INST/secrets/backup.pub"
printf 'tavily:\n  api_key: "filled-in"\n' > "$INST/secrets/secrets.example.yaml"; git -C "$INST" add secrets/secrets.example.yaml
hook
check_exit 1 "$rc"
contains "$OUT" "must keep every value empty: tavily.api_key"
git -C "$INST" checkout -q -- secrets/secrets.example.yaml 2>/dev/null || cp "$REPO/secrets/secrets.example.yaml" "$INST/secrets/"
unstage; rm "$INST/.template"

case_new "stop hook commits secrets/ with docs/ only when every value is encrypted"
SH="$REPO/claude-global/hooks/stop.sh"
stop() { on alpha env CC_HOME="$INST" "$SH" < /dev/null; }
git -C "$INST" add -A >/dev/null 2>&1; on alpha git -C "$INST" commit -q -m "test: settle"
printf '"fake-stop"' | SOPS_AGE_KEY_FILE="$KA" sops set --value-stdin "$STORE" '["jina"]["api_key"]'
echo "note" >> "$INST/docs/machines/alpha.md"
c0="$(git -C "$INST" rev-list --count HEAD)"
stop
[ "$(git -C "$INST" rev-list --count HEAD)" = "$((c0 + 1))" ] && ok "one commit" || bad "stop hook did not commit"
[ -z "$(git -C "$INST" status --porcelain -- secrets docs)" ] && ok "docs/ and secrets/ both committed" || bad "left uncommitted: $(git -C "$INST" status --porcelain | head -3)"
cat "$WORK/plain.yaml" "$STORE" > "$WORK/mixed.yaml"; cp "$WORK/mixed.yaml" "$STORE"
echo "note 2" >> "$INST/docs/machines/alpha.md"
stop
contains "$OUT" "NOT committing secrets/"
lacks "$OUT" "plaintext-value"
[ -n "$(git -C "$INST" status --porcelain -- secrets)" ] && ok "plaintext store left uncommitted" || bad "plaintext store was committed"
[ -z "$(git -C "$INST" status --porcelain -- docs)" ] && ok "docs/ still committed" || bad "docs/ not committed"
git -C "$INST" checkout -q -- secrets/secrets.yaml

case_new "session-start hook reports secrets status in a line"
on alpha env CC_HOME="$INST" "$REPO/claude-global/hooks/session-start.sh"
contains "$OUT" "secrets: ok — secrets/secrets.yaml"
mv "$KA" "$WORK/ka.moved"
on alpha env CC_HOME="$INST" "$REPO/claude-global/hooks/session-start.sh"
contains "$OUT" "secrets: key:        none"
mv "$WORK/ka.moved" "$KA"

# =========================================================================
case_new "push is designed, not built"
on alpha "$S" push some-box
check_exit 5 "$rc"

case_new "sops older than $(awk -F'"' '/CC_SOPS_MIN=/ {print $2}' "$REPO/lib/common.sh") is refused for writes"
mkdir -p "$WORK/oldsops"
printf '#!/bin/sh\n[ "$1" = --disable-version-check ] && { echo "sops 3.10.2"; exit 0; }\nexit 1\n' > "$WORK/oldsops/sops"
chmod +x "$WORK/oldsops/sops"
on alpha env PATH="$WORK/oldsops:$WORK/bin-alpha:$SYSBIN" sh -c 'printf x | "$0" set exa.api_key --stdin' "$S"
check_exit 3 "$rc"
contains "$OUT" "too old"

# =========================================================================
case_new "backup-key and backup-verify refuse without a terminal"
on alpha "$S" backup-key </dev/null
check_exit 2 "$rc"
on alpha "$S" backup-verify </dev/null
check_exit 2 "$rc"

# script(1) gives the command a pty. BSD and util-linux spell it differently.
pty() { # pty <input file> <cmd…>
  # stdin stays open after the input, or script(1) hangs up on the command at EOF.
  local in="$1"; shift
  if script -q /dev/null true >/dev/null 2>&1 </dev/null; then
    { cat "$in"; sleep 3; } | script -q /dev/null "$@"
  else
    { cat "$in"; sleep 3; } | script -qec "$(printf '%q ' "$@")" /dev/null
  fi
}
if command -v script >/dev/null 2>&1; then
  case_new "paper key through a pty: backup-key, then backup-verify with the written-down key"
  printf '\n' > "$WORK/enter"
  pty "$WORK/enter" env -i PATH="$WORK/bin-alpha:$SYSBIN" HOME="$WORK/home-alpha" TMPDIR="$WORK" CC_ROOT="$INST" \
    GIT_EXEC_PATH="$GIT_EXEC_PATH" GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com \
    GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com "$S" backup-key > "$WORK/paper.txt" 2>&1; cp "$WORK/paper.txt" "$OUT"
  rc=$?
  check_exit 0 "$rc"
  # the "paper": the grouped lines, as a person would copy them
  tr -d '\r' < "$WORK/paper.txt" | grep -E '^    AGE-SE' -A3 | grep -E '^    [A-Z0-9-]{1,6}( [A-Z0-9-]{1,6})*$' > "$WORK/written.txt"
  [ -s "$WORK/written.txt" ] && ok "key printed in groups" || bad "no grouped key in output"
  grep -q '^age1' "$INST/secrets/backup.pub" && ok "backup.pub written" || bad "no backup.pub"
  grep -qF "$(grep '^age1' "$INST/secrets/backup.pub")" "$STORE" && ok "store encrypted to the backup key" || bad "backup not a recipient"
  grep -rq "AGE-SECRET-KEY-1" "$INST/secrets" "$INST/docs" "$INST/.sops.yaml" && bad "private paper key on disk in the instance" || ok "private paper key not on disk"
  { tr '\n' ' ' < "$WORK/written.txt" | tr '[:upper:]' '[:lower:]'; echo; } > "$WORK/typed"
  pty "$WORK/typed" env -i PATH="$WORK/bin-alpha:$SYSBIN" HOME="$WORK/home-alpha" TMPDIR="$WORK" CC_ROOT="$INST" "$S" backup-verify > "$OUT" 2>&1
  rc=$?
  check_exit 0 "$rc"
  contains "$OUT" "the paper key opens"
  # a well-formed key that isn't the paper key, split so gitleaks doesn't flag the test itself
  printf '%s%s\n' 'AGE-SECRET-' 'KEY-1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ' > "$WORK/wrong"
  pty "$WORK/wrong" env -i PATH="$WORK/bin-alpha:$SYSBIN" HOME="$WORK/home-alpha" TMPDIR="$WORK" CC_ROOT="$INST" "$S" backup-verify > "$OUT" 2>&1
  rc=$?
  check_exit 1 "$rc"
  on alpha "$S" recipients --check
  check_exit 0 "$rc"
fi

# =========================================================================
if command -v gitleaks >/dev/null 2>&1; then
  case_new "gitleaks: ciphertext passes, an age private key is caught"
  G="$WORK/gl"
  mkdir -p "$G/secrets"
  git -C "$G" init -q
  cp "$STORE" "$G/secrets/secrets.yaml"
  git -C "$G" add -A
  if (cd "$G" && gitleaks git --pre-commit --staged --redact --no-banner >/dev/null 2>&1); then ok "no finding on the encrypted store"; else bad "gitleaks flags the encrypted store"; fi
  cp "$KA" "$G/keys.txt"
  git -C "$G" add -f keys.txt
  if (cd "$G" && gitleaks git --pre-commit --staged --redact --no-banner >/dev/null 2>&1); then bad "gitleaks missed an age key"; else ok "age key caught"; fi
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
