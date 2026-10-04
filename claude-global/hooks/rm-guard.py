#!/usr/bin/env python3
"""PreToolUse hook for Bash: let `rm` run without a prompt inside temporary folders; ask for every other `rm`.

It replaces the `Bash(rm:*)` ask rule. An ask rule can't have exceptions: Claude Code checks ask rules
before allow rules and before hook decisions, so `rm` in /tmp could never be allowed while it existed.

Allowed without a prompt: one plain `rm` command (no `;`, `&&`, `|`, `$`, globs, `~`, quotes or
redirects), its flags from -r -R -f -v -d, and every target an absolute path strictly inside /tmp or
$TMPDIR after resolving symlinks, with no `..`. Anything else that runs `rm` gets "ask". Commands
without `rm` get no decision. Any error asks: it fails closed.

Exit 0 always; the decision is the JSON on stdout.
"""

import json
import os
import re
import sys

# rm in command position: at the start, after ; & | ( $( a backtick or a newline, or after a wrapper (sudo, xargs …)
RM_WORD = re.compile(r"(?:^|[;&|(`\n]|\$\()\s*(?:(?:sudo|xargs|env|nice|time|exec|command|nohup)\s+(?:-\S+\s+)*)*(?:\S*/)?rm(?=\s|$)")
UNSAFE = re.compile(r"[;&|`$(){}<>*?\[\]~'\"\\\n]")
FLAGS = re.compile(r"^-[rRfvd]+$")


def decide(decision: str, reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                             "permissionDecisionReason": reason}}))


def temp_roots() -> list[str]:
    roots = {os.path.realpath("/tmp")}
    if os.environ.get("TMPDIR"):
        roots.add(os.path.realpath(os.environ["TMPDIR"]))
    return [r.rstrip("/") + "/" for r in roots if r not in ("/", "")]


def safe(command: str) -> bool:
    command = command.strip()
    if UNSAFE.search(command):
        return False
    words = command.split()
    if not words or words[0] != "rm":
        return False
    paths = [w for w in words[1:] if not FLAGS.match(w)]
    if not paths or any(w.startswith("-") for w in paths):
        return False
    roots = temp_roots()
    for p in paths:
        if not p.startswith("/") or ".." in p.split("/") or os.path.normpath(p) != p.rstrip("/"):
            return False
        real = os.path.realpath(p)
        if not any(real.startswith(r) and len(real) > len(r) for r in roots):
            return False
    return True


def main() -> None:
    try:
        data = json.load(sys.stdin)
        if data.get("tool_name") != "Bash":
            return
        command = str(data.get("tool_input", {}).get("command", ""))
        if not RM_WORD.search(command):
            return
        if safe(command):
            decide("allow", "rm inside a temporary folder")
        else:
            decide("ask", "rm outside a temporary folder, or not a plain rm of literal paths")
    except Exception as e:  # fail closed
        decide("ask", f"rm-guard could not check this command ({type(e).__name__})")


if __name__ == "__main__":
    main()
