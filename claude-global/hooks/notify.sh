#!/usr/bin/env bash
# Notification hook: Claude is waiting for you (permission prompt or idle input) → Telegram.
ROOT="${CC_HOME:-$HOME/claude-computer}"
input="$(cat)"
msg="$(printf '%s' "$input" | jq -r '.message // "waiting for input"' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
"$ROOT/bin/tg-send" "⏳ $msg — ${cwd/#$HOME/~}" >/dev/null 2>&1 || true
exit 0
