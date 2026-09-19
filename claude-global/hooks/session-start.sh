#!/usr/bin/env bash
# SessionStart hook: sync the fleet brain, report the secrets state, refresh vault task copies.
# Stdout becomes session context, so keep it to a few lines. Never fail the session.
SM="${CC_HOME:-$HOME/claude-computer}"
# timeout is GNU coreutils; fall back to gtimeout, or run unguarded.
to() { local s="$1"; shift; if command -v timeout >/dev/null; then timeout "$s" "$@"; elif command -v gtimeout >/dev/null; then gtimeout "$s" "$@"; else "$@"; fi; }
[ -d "$SM/.git" ] || { echo "claude-computer: no repo at $SM — run /setup"; exit 0; }

if out="$(to 20 git -C "$SM" pull --rebase --autostash -q 2>&1)"; then
  echo "claude-computer: pulled ($(git -C "$SM" log -1 --format='%h %s' | cut -c1-72))"
else
  echo "claude-computer: pull FAILED — working from local copy. Resolve before editing docs/. ${out:0:200}"
fi

case "$("$SM/bin/secrets-unlock" --status 2>/dev/null)" in
  unlocked) echo "bitwarden: unlocked" ;;
  locked) echo "bitwarden: locked — wrappers that need keys will fail. Ask the user to run \`secrets-unlock\` in a terminal." ;;
  *) echo "bitwarden: not logged in or not installed" ;;
esac

if [ -d "$HOME/vault" ]; then
  # New MacParakeet transcripts first, so the task map below reflects anything already routed.
  [ -f "$HOME/Library/Application Support/MacParakeet/macparakeet.db" ] && to 30 "$SM/bin/transcripts-sync" 2>&1 | head -1
  to 30 "$SM/bin/tasks-sync" 2>&1 | head -1
fi
exit 0
