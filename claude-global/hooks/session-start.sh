#!/usr/bin/env bash
# SessionStart hook: sync the fleet brain, report the secrets state, refresh vault task copies.
# Stdout becomes session context, so keep it to a few lines. Never fail the session.
ROOT="${CC_HOME:-$HOME/claude-computer}"
# timeout is GNU coreutils; fall back to gtimeout, or run unguarded.
to() { local s="$1"; shift; if command -v timeout >/dev/null; then timeout "$s" "$@"; elif command -v gtimeout >/dev/null; then gtimeout "$s" "$@"; else "$@"; fi; }
[ -d "$ROOT/.git" ] || { echo "claude-computer: no repo at $ROOT — run /setup"; exit 0; }

if out="$(to 20 git -C "$ROOT" pull --rebase --autostash -q 2>&1)"; then
  echo "claude-computer: pulled ($(git -C "$ROOT" log -1 --format='%h %s' | cut -c1-72))"
else
  echo "claude-computer: pull FAILED — working from local copy. Resolve before editing docs/. ${out:0:200}"
fi

# Names and key state only: `secrets status` never decrypts.
if [ -x "$ROOT/bin/secrets" ]; then
  st="$("$ROOT/bin/secrets" status 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "secrets: ok — $(printf '%s\n' "$st" | sed -n 's/^store: *//p' | head -1)"
    printf '%s\n' "$st" | grep -q '^backup key: none' && echo "secrets: no paper backup key yet — the user runs \`secrets backup-key\` in a terminal"
  else
    printf '%s\n' "$st" | grep -E 'none|no —|NOT|should|not installed' | head -3 | sed 's/^/secrets: /'
    echo "secrets: wrappers that need keys will fail until this is fixed (a human runs the command shown)."
  fi
fi

if [ -d "$HOME/vault" ]; then
  # New MacParakeet transcripts first, so the task map below reflects anything already routed.
  [ -f "$HOME/Library/Application Support/MacParakeet/macparakeet.db" ] && to 30 "$ROOT/bin/transcripts-sync" 2>&1 | head -1
  to 30 "$ROOT/bin/tasks-sync" 2>&1 | head -1
fi
exit 0
