#!/usr/bin/env python3
"""PreToolUse hook for Bash: let `rm` run without a prompt inside temporary folders; ask for every other `rm`.

It replaces the `Bash(rm:*)` ask rule. An ask rule can't have exceptions: Claude Code checks ask rules
before allow rules and before hook decisions, so `rm` in /tmp could never be allowed while it existed.

A safe `rm`: flags from -r -R -f -v -d, and every target a literal path (no `$`, globs or `~`) that is
absolute, or relative after a literal `cd /absolute/path` earlier in the same chain, and lies strictly
inside /tmp or $TMPDIR after resolving symlinks, with no `..`.

  - The whole command is one safe `rm`             → "allow"
  - A chain (`&&`, `;`, `||`, `|`, newlines) whose every `rm` is safe → no decision: the rest of the
    chain goes through the normal permission checks, so one safe `rm` never waves through the rest
  - Any other `rm` — unsafe, inside `$( )` or backticks, after `sudo`/`xargs`, in a heredoc → "ask"
  - No `rm` in command position                   → no decision

Any error asks: it fails closed. Exit 0 always; the decision is the JSON on stdout.
"""

import json
import os
import re
import shlex
import sys

# rm in command position: at the start, after ; & | ( $( a backtick or a newline, or after a wrapper (sudo, xargs …)
RM_WORD = re.compile(r"(?:^|[;&|(`\n]|\$\()\s*(?:(?:sudo|xargs|env|nice|time|exec|command|nohup)\s+(?:-\S+\s+)*)*(?:\S*/)?rm(?=\s|$)")
WRAPPERS = {"sudo", "xargs", "env", "nice", "time", "exec", "command", "nohup", "doas"}
SEPARATORS = {"&&", "||", ";", "|", "&", ";;"}
FLAGS = re.compile(r"^-[rRfvd]+$")
ASSIGN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")


def decide(decision: str, reason: str) -> None:
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                             "permissionDecisionReason": reason}}))


def temp_roots() -> list[str]:
    roots = {os.path.realpath("/tmp")}
    if os.environ.get("TMPDIR"):
        roots.add(os.path.realpath(os.environ["TMPDIR"]))
    return [r.rstrip("/") + "/" for r in roots if r not in ("/", "")]


def literal(word: str) -> bool:
    return not re.search(r"[$*?\[\]{}~`]", word)


def in_temp(path: str, cwd: str | None) -> bool:
    if not literal(path) or ".." in path.split("/"):
        return False
    if not path.startswith("/"):
        if cwd is None:
            return False
        path = os.path.join(cwd, path)
    real = os.path.realpath(path)
    return any(real.startswith(r) and len(real) > len(r) for r in temp_roots())


def safe_rm(args: list[str], cwd: str | None) -> bool:
    paths = [a for a in args if not FLAGS.match(a)]
    if not paths or any(a.startswith("-") for a in paths):
        return False
    return all(in_temp(p, cwd) for p in paths)


def segments(command: str) -> list[list[str]] | None:
    """Split a command into simple commands, or None when it can't be read reliably."""
    if "<<" in command or "$(" in command or "`" in command:
        return None
    lex = shlex.shlex(command.replace("\n", " ; "), posix=True, punctuation_chars=";&|")
    lex.whitespace_split = True
    lex.commenters = ""
    out, cur = [], []
    for tok in lex:
        if tok in SEPARATORS:
            out.append(cur)
            cur = []
        elif set(tok) <= set(";&|()<>"):
            return None  # redirections and subshell punctuation: don't guess
        else:
            cur.append(tok)
    out.append(cur)
    return [s for s in out if s]


def main() -> None:
    if os.environ.get("CC_RM_GUARD") == "off":
        return  # turned off on this machine (~/.claude/settings.local.json env)
    try:
        data = json.load(sys.stdin)
        if data.get("tool_name") != "Bash":
            return
        command = str(data.get("tool_input", {}).get("command", ""))
        if not RM_WORD.search(command):
            return
        segs = segments(command)
        if segs is None:
            decide("ask", "rm inside a heredoc, $( ) or backticks: not checked")
            return
        cwd, rms, safe = None, 0, True
        for words in segs:
            while words and ASSIGN.match(words[0]):
                words = words[1:]  # VAR=value prefixes
            if not words:
                continue
            name = os.path.basename(words[0])
            if words[0] in WRAPPERS:
                if any(os.path.basename(w) == "rm" for w in words[1:]):
                    rms, safe = rms + 1, False
                continue
            if name == "cd":
                target = words[1] if len(words) > 1 else ""
                cwd = target if target.startswith("/") and literal(target) else None
            elif name == "rm":
                rms += 1
                safe = safe and words[0] == "rm" and safe_rm(words[1:], cwd)
        if rms == 0:
            return  # `rm` appeared only as an argument (git rm, echo rm)
        if not safe:
            decide("ask", "rm outside a temporary folder, or of paths that can't be checked")
        elif len(segs) == 1:
            decide("allow", "rm inside a temporary folder")
        # a chain whose every rm is safe: no decision, the rest of the chain is checked as usual
    except Exception as e:  # fail closed
        decide("ask", f"rm-guard could not check this command ({type(e).__name__})")


if __name__ == "__main__":
    main()
