#!/usr/bin/env bash
# tests/capture.sh — drive bin/capture offline: no Telegram, no Gmail, no transcription model.
#
# Usage: ./tests/capture.sh
#
# The command line is run for real; the sources are checked by loading bin/capture as a module with
# its outside calls replaced: Bot.call and urlopen for Telegram, gmail() for Gmail, and a fake
# macparakeet-cli under a throwaway HOME.
#
# Cases: (1) --help, an unknown source, no vault inbox · (2) no secrets store → exit 5 (3 without
# sops), nothing written · (3) a voice note named .oga by Telegram is saved as .ogg; photos and
# documents keep their suffix · (4) transcription reads rawTranscript from JSON, and a failure is
# reported with the CLI's error, not silently · (5) a Gmail message becomes one note dated by this
# machine's day, with one heading, and is relabelled vault → vault/filed · (6) Telegram: only the
# configured chat is saved, /start is skipped, the offset advances, one "saved" reply
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/capture"
[ -x "$SCRIPT" ] || { echo "bin/capture is not executable" >&2; exit 1; }
command -v uv > /dev/null || { echo "uv is required (bin/capture is a uv script)" >&2; exit 1; }

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cc-capture-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
banner() { printf '\n%s\n' "== $1"; }

# On a cold cache uv prints "Installed n packages" to stderr; install the script's environment first.
"$SCRIPT" --help > /dev/null 2>&1

VAULT="$WORK/vault"
mkdir -p "$VAULT/inbox"

# --------------------------------------------------------------------------
banner "(1) the command line"
"$SCRIPT" --help > "$WORK/out" 2>&1; check_exit 0 $?
contains "$WORK/out" "Run it on one machine only"
"$SCRIPT" bogus --vault "$VAULT" > "$WORK/out" 2>&1; check_exit 2 $?
"$SCRIPT" gmail --vault "$WORK/no-vault" > "$WORK/out" 2>&1; check_exit 5 $?
contains "$WORK/out" "no vault inbox"

# --------------------------------------------------------------------------
banner "(2) no secrets store"
want=5; command -v sops > /dev/null || want=3
CC_SECRETS_FILE="$WORK/none.yaml" "$SCRIPT" telegram --vault "$VAULT" > "$WORK/out" 2>&1; check_exit "$want" $?
if [ "$(grep -c . "$WORK/out")" = 1 ]; then ok "one error line"; else bad "error printed $(grep -c . "$WORK/out") times"; fi
if [ -z "$(ls -A "$VAULT/inbox")" ]; then ok "nothing written"; else bad "wrote: $(ls -A "$VAULT/inbox")"; fi

# --------------------------------------------------------------------------
# A fake macparakeet-cli where bin/capture looks for it: JSON on stdout like the real one, a
# transcript for *.ogg, the real CLI's refusal for anything else.
mkdir -p "$WORK/home/.local/bin"
cat > "$WORK/home/.local/bin/macparakeet-cli" <<'EOF'
#!/bin/sh
case "$2" in
  *.ogg) printf '{"ok": true, "rawTranscript": "  call the plumber on Friday  ", "wordTimestamps": []}\n' ;;
  *)     printf '{"ok": false, "error": "Unsupported format: .oga. Supported: ogg, opus"}\n'
         echo "Converting audio..." >&2; exit 1 ;;
esac
EOF
chmod +x "$WORK/home/.local/bin/macparakeet-cli"

# Cases 3-6 in one Python process: bin/capture loaded as a module, its outside calls replaced.
# Each check prints "ok <what>" or "FAIL <what>"; the loop below counts them.
# PYTHONDONTWRITEBYTECODE: loading bin/capture as a module must not leave bin/__pycache__ behind.
export VAULT WORK SCRIPT
HOME="$WORK/home" TZ="Asia/Tokyo" PYTHONDONTWRITEBYTECODE=1 python3 - > "$WORK/py" 2>&1 <<'PY'
import importlib.machinery, importlib.util, io, json, os, subprocess, sys
from pathlib import Path

loader = importlib.machinery.SourceFileLoader("capture", os.environ["SCRIPT"])
spec = importlib.util.spec_from_loader("capture", loader)
m = importlib.util.module_from_spec(spec)
loader.exec_module(m)
vault, work = Path(os.environ["VAULT"]), Path(os.environ["WORK"])
m.STATE = work / "state.json"

def check(cond, what):
    print(("ok   " if cond else "FAIL ") + what)

print("== (3) Telegram file suffixes")
m.urllib.request.urlopen = lambda *a, **k: io.BytesIO(b"OggS")
bot = m.Bot("not-a-token")
for fp, want in (("voice/file_1.oga", ".ogg"), ("photos/file_2.jpg", ".jpg"), ("documents/f.pdf", ".pdf")):
    bot.call = lambda method, fp=fp, **p: {"file_path": fp, "file_size": 4}
    got = bot.download("id", work / "dl" / "base.ogg")
    check(got.suffix == want, f"{fp} saved as {got.name}")

print("== (4) transcription")
(work / "a.ogg").write_bytes(b"OggS")
(work / "a.oga").write_bytes(b"OggS")
check(m.transcribe(work / "a.ogg") == "call the plumber on Friday", "rawTranscript, trimmed")
err = io.StringIO()
sys.stderr, real = err, sys.stderr
said = m.transcribe(work / "a.oga")
sys.stderr = real
check(said == "", "a refused file gives no transcript")
check("Unsupported format: .oga" in err.getvalue(), "the CLI's error is reported")

print("== (5) Gmail")
calls = []
def fake_gmail(*args):
    calls.append(args)
    if args[0] == "search":
        out = [{"id": "abc123", "from": "A Person <a@example.com>", "subject": "Lease renewal",
                "date": "Mon, 12 Oct 2026 22:16:28 -0700"}]
        return subprocess.CompletedProcess(args, 0, json.dumps(out), "")
    if args[0] == "get":
        return subprocess.CompletedProcess(args, 0, "# Lease renewal\n\nFrom: A Person\n\nThe body.", "")
    return subprocess.CompletedProcess(args, 0 if args[0] == "label" else 1, "", "")
m.gmail = fake_gmail
saved = m.capture_gmail(vault, False)
names = [p.name for p in saved]
check(names == ["2026-10-13-email-lease-renewal.md"], f"named by this machine's day: {names}")
text = (vault / "inbox" / "2026-10-13-email-lease-renewal.md").read_text()
check(text.count("# Lease renewal") == 1, "one heading")
check("date: 2026-10-13" in text and "kind: email" in text, "front matter")
check(("label", "abc123", "--remove", "vault", "--add", "vault/filed", "--create") in calls, "relabelled")

print("== (6) Telegram")
replies = []
def fake_call(method, **p):
    if method == "getUpdates":
        return [
            {"update_id": 10, "message": {"message_id": 1, "date": 1792000000, "chat": {"id": 42}, "text": "keep this"}},
            {"update_id": 11, "message": {"message_id": 2, "date": 1792000000, "chat": {"id": 99}, "text": "a stranger"}},
            {"update_id": 12, "message": {"message_id": 3, "date": 1792000000, "chat": {"id": 42}, "text": "/start"}},
        ]
    if method == "sendMessage":
        replies.append(p)
        return {}
    raise AssertionError(method)
m.Bot.call = lambda self, method, **p: fake_call(method, **p)
m.cc.secret = lambda name, field: {"token": "not-a-token", "chat_id": "42"}[field]
state = {}
got = m.capture_telegram(vault, False, state)
check(len(got) == 1 and "keep this" in got[0].read_text(), "the configured chat's message saved")
check(not any("a stranger" in p.read_text() for p in (vault / "inbox").glob("*.md")), "a stranger's message never saved")
check(state.get("telegram_offset") == 12, f"offset advanced to 12: {state.get('telegram_offset')}")
check(len(replies) == 1 and replies[0]["chat_id"] == "42", "one reply, to the configured chat")
PY
rc=$?
while IFS= read -r line; do
  case "$line" in
    "== "*) banner "${line#== }" ;;
    "ok   "*) ok "${line#ok   }" ;;
    "FAIL "*) bad "${line#FAIL }" ;;
    *) printf '    %s\n' "$line" ;;
  esac
done < "$WORK/py"
[ "$rc" = 0 ] || bad "the Python cases exited $rc"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
