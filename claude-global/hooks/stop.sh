#!/usr/bin/env bash
# Stop hook (end of every turn):
#   1. commit and push any docs/ changes in the fleet brain as "[<host>] <what>", with
#      secrets/ and .sops.yaml — but those only when every value in them is encrypted
#   2. tg-send if the turn ran longer than CC_LONG_TURN_MIN minutes (default 10)
# Never blocks Claude; failures are reported on stderr and ignored.
ROOT="${CC_HOME:-$HOME/claude-computer}"
# timeout is GNU coreutils; fall back to gtimeout, or run unguarded.
to() { local s="$1"; shift; if command -v timeout >/dev/null; then timeout "$s" "$@"; elif command -v gtimeout >/dev/null; then gtimeout "$s" "$@"; else "$@"; fi; }
input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // "default"' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
host="$(scutil --get LocalHostName 2>/dev/null || hostname -s)"

# The secrets store rides along only when every non-empty value in it is ENC[…]; a plaintext
# value is never committed by a hook, it is reported instead.
paths="docs"
if [ -d "$ROOT/.git" ] && [ ! -f "$ROOT/.template" ] && [ -n "$(git -C "$ROOT" status --porcelain -- secrets .sops.yaml 2>/dev/null)" ]; then
  plain="$(
    # shellcheck source=/dev/null
    . "$ROOT/lib/common.sh" 2>/dev/null || exit 0
    for f in "$ROOT"/secrets/secrets.yaml "$ROOT"/secrets/hosts/*.yaml; do
      [ -f "$f" ] || continue
      grep -q '^sops:' "$f" || { echo "${f#"$ROOT"/} (not a sops file)"; continue; }
      cc_secrets_list "$f" | awk -F '\t' -v f="${f#"$ROOT"/}" '$2 == "plain" {print f ": " $1}'
    done
  )"
  if [ -n "$plain" ]; then
    echo "claude-computer: NOT committing secrets/ — plaintext values: $(printf '%s' "$plain" | head -3 | paste -sd ';' -)" >&2
  else
    paths="docs secrets"
    # a pathspec that matches nothing fails the commit: name .sops.yaml only if it is there or tracked
    { [ -e "$ROOT/.sops.yaml" ] || git -C "$ROOT" ls-files --error-unmatch .sops.yaml >/dev/null 2>&1; } && paths="$paths .sops.yaml"
  fi
fi

# shellcheck disable=SC2086
if [ -d "$ROOT/.git" ] && [ ! -f "$ROOT/.template" ] && [ -n "$(git -C "$ROOT" status --porcelain -- $paths 2>/dev/null)" ]; then
  files="$(git -C "$ROOT" status --porcelain -- $paths | awk '{print $NF}' | sed 's|^docs/||' | head -5 | paste -sd ', ' -)"
  git -C "$ROOT" add -- $paths 2>/dev/null
  if out="$(git -C "$ROOT" commit -q -m "[$host] update $files" -- $paths 2>&1)"; then
    # Machine files are private: never push them to a public repository.
    vis="$(cd "$ROOT" && to 15 gh repo view --json visibility --jq .visibility 2>/dev/null)"
    if [ "$vis" = "PUBLIC" ]; then
      echo "claude-computer: committed locally but NOT pushed — origin is a public repo" >&2
    else
      to 30 git -C "$ROOT" push -q 2>/dev/null || echo "claude-computer: committed but push failed (offline?)" >&2
    fi
  else
    echo "claude-computer: could not commit — ${out:0:200}" >&2
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
