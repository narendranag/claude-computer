#!/usr/bin/env bash
# Stop hook (end of every turn):
#   1. commit and push any docs/ changes in the fleet brain as "[<host>] <what>"
#   2. tg-send if the turn ran longer than CC_LONG_TURN_MIN minutes (default 10)
# Never blocks Claude; failures are reported on stderr and ignored.
ROOT="${CC_HOME:-$HOME/claude-computer}"
# timeout is GNU coreutils; fall back to gtimeout, or run unguarded.
to() { local s="$1"; shift; if command -v timeout >/dev/null; then timeout "$s" "$@"; elif command -v gtimeout >/dev/null; then gtimeout "$s" "$@"; else "$@"; fi; }
input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
host="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"

if [ -d "$ROOT/.git" ] && [ ! -f "$ROOT/.template" ] && [ -n "$(git -C "$ROOT" status --porcelain -- docs 2>/dev/null)" ]; then
  files="$(git -C "$ROOT" status --porcelain -- docs | awk '{print $NF}' | sed 's|^docs/||' | head -5 | paste -sd ', ' -)"
  git -C "$ROOT" add -- docs
  if out="$(git -C "$ROOT" commit -q -m "[$host] update $files" -- docs 2>&1)"; then
    # Machine files are private: never push them to a public repository.
    vis="$(cd "$ROOT" && to 15 gh repo view --json visibility --jq .visibility 2>/dev/null)"
    if [ "$vis" = "PUBLIC" ]; then
      echo "claude-computer: committed docs locally but NOT pushed — origin is a public repo" >&2
    else
      to 30 git -C "$ROOT" push -q 2>/dev/null || echo "claude-computer: committed docs but push failed (offline?)" >&2
    fi
  else
    echo "claude-computer: could not commit docs/ — ${out:0:200}" >&2
  fi
fi

start_file="${TMPDIR:-/tmp}/claude-turn-$sid"
if [ -f "$start_file" ]; then
  elapsed=$(( $(date +%s) - $(cat "$start_file") ))
  rm -f "$start_file"
  if [ "$elapsed" -ge $(( ${CC_LONG_TURN_MIN:-10} * 60 )) ]; then
    "$ROOT/bin/tg-send" "done after $((elapsed / 60)) min in ${cwd/#$HOME/~}" >/dev/null 2>&1 || true
  fi
fi
exit 0
