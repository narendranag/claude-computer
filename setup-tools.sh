#!/usr/bin/env bash
# setup-tools.sh — the tools Homebrew can't install. Run by /setup right after `brew bundle`.
#
# Usage: ./setup-tools.sh [--dry-run] [--only NAME[,NAME…]]
#   names: oh-my-zsh, runtimes, playwright, macparakeet, vscode, autoupdate
#
#   oh-my-zsh    curl installer, keeping the linked ~/.zshrc
#   runtimes     mise → Python + Node LTS (uv and pnpm come from the Brewfile)
#   playwright   Playwright CLI (uv tool, version pinned to match bin/browse) + its bundled Chromium.
#                Headless browsing is Playwright's Chromium, never Google Chrome --headless;
#                the Chrome cask stays for the human and for Claude in Chrome.
#   macparakeet  link macparakeet-cli from the app bundle into ~/.local/bin if it isn't on PATH
#   vscode       extensions from vscode-extensions.txt
#   autoupdate   daily `brew autoupdate` agent (upgrade + cleanup)
#
# Idempotent: each step checks before installing. Exit codes: 0 ok · 1 a step failed · 2 usage
set -euo pipefail
cd "$(dirname "$0")"

PLAYWRIGHT_VERSION="1.63.0"   # keep in step with the header of bin/browse

dry=0; only=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry=1; shift ;;
    --only) only=",${2:?},"; shift 2 ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,"");print;next}{exit}' "$0"; exit 0 ;;
    *) echo "setup-tools: unknown argument $1" >&2; exit 2 ;;
  esac
done

want() { [ -z "$only" ] || case "$only" in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
run() { if [ "$dry" -eq 1 ]; then echo "  $*"; else "$@"; fi; }
step() { echo "→ $*"; }
fail=0

if want oh-my-zsh; then
  step "oh-my-zsh"
  if [ -d "$HOME/.oh-my-zsh" ]; then echo "  present"
  else run env RUNZSH=no KEEP_ZSHRC=yes CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || fail=1; fi
fi

if want runtimes; then
  step "mise: Python + Node LTS"
  if command -v mise >/dev/null; then run mise use --global python@3.13 node@lts || fail=1
  else echo "  mise missing — run brew bundle first" >&2; fail=1; fi
fi

if want playwright; then
  step "Playwright $PLAYWRIGHT_VERSION + bundled Chromium"
  if command -v uv >/dev/null; then
    run uv tool install --force "playwright==$PLAYWRIGHT_VERSION" || fail=1
    run "$HOME/.local/bin/playwright" install chromium || fail=1
  else echo "  uv missing — run brew bundle first" >&2; fail=1; fi
  # Profiles may hold logged-in sessions: private to this user, never in a repo.
  run mkdir -p "$HOME/.config/browse/profiles"
  run chmod 700 "$HOME/.config/browse" "$HOME/.config/browse/profiles"
fi

if want macparakeet; then
  step "macparakeet-cli on PATH"
  bundle_cli="/Applications/MacParakeet.app/Contents/MacOS/macparakeet-cli"
  if command -v macparakeet-cli >/dev/null; then echo "  present: $(command -v macparakeet-cli)"
  elif [ -x "$bundle_cli" ]; then
    run mkdir -p "$HOME/.local/bin"
    run ln -sf "$bundle_cli" "$HOME/.local/bin/macparakeet-cli"
    echo "  Human steps, in the MacParakeet app: grant Microphone; grant Screen Recording (system audio for"
    echo "  meeting capture); download the Parakeet v3 model when onboarding offers it."
  else echo "  MacParakeet.app not installed — brew bundle first (Apple silicon only)" >&2; fi
fi

if want vscode; then
  step "VS Code extensions"
  if command -v code >/dev/null; then
    installed="$(code --list-extensions | tr '[:upper:]' '[:lower:]')"
    # Read from a process substitution, not the right-hand side of a pipe: a loop in a
    # subshell cannot set fail, so every failed extension used to exit 0.
    while read -r ext; do
      if echo "$installed" | grep -qx "$(echo "$ext" | tr '[:upper:]' '[:lower:]')"; then continue; fi
      run code --install-extension "$ext" >/dev/null || { echo "  failed: $ext" >&2; fail=1; }
    done < <(grep -v '^[[:space:]]*#' vscode-extensions.txt | grep -v '^[[:space:]]*$')
  else echo "  code not on PATH — open VS Code once, run 'Shell Command: Install code in PATH'" >&2; fi
fi

if want autoupdate; then
  step "brew autoupdate (daily, upgrade + cleanup)"
  if brew autoupdate status 2>/dev/null | grep -qi "installed and running"; then echo "  running"
  else
    run brew tap domt4/autoupdate
    # Current Homebrew asks you to trust third-party tap commands before they run.
    if brew help trust >/dev/null 2>&1; then run brew trust --command domt4/autoupdate/autoupdate || fail=1; fi
    run brew autoupdate start 86400 --upgrade --cleanup || fail=1
  fi
fi

exit "$fail"
