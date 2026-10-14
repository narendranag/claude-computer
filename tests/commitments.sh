#!/usr/bin/env bash
# tests/commitments.sh — drive bin/commitments against a throwaway vault.
#
# Usage: ./tests/commitments.sh
#
# Cases: (1) the owner is the person note with `me: true`: their commitments list first and count as
# "yours" · (2) without `me: true`, the note named after `git config user.name` · (3) with neither,
# no commitment is "yours" and nothing fails · (4) `set done` writes status and done_on, a dated log
# bullet in the owner's name citing the day's confirmation note, and commits the vault · (5) a second
# `set` the same day appends to that confirmation note · (6) usage errors exit 2 and change nothing ·
# (7) `list --overdue` and `--due-within N`, counted from `--date` · (8) `brief`: overdue, due in the next
# 7 days, and the people met the day before (flow and block attendee lists, the owner left out, other days
# ignored) · (9) a bad --date exits 2
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/commitments"
[ -x "$SCRIPT" ] || { echo "bin/commitments is not executable" >&2; exit 1; }
command -v uv > /dev/null || { echo "uv is required (bin/commitments is a uv script)" >&2; exit 1; }

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cc-commitments-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
banner() { printf '\n%s\n' "== $1"; }

export GIT_CONFIG_NOSYSTEM=1 HOME="$WORK/home"
mkdir -p "$HOME"
git config --global user.name "Alex Example"
git config --global user.email alex@example.com
git config --global init.defaultBranch main

# On a cold cache uv prints "Installed n packages" to stderr; install the script's environment first.
"$SCRIPT" --help > /dev/null 2>&1

V="$WORK/vault"
person() { # person <slug> <name> [me]
  printf -- '---\ntype: person\ncreated: 2026-10-01\nname: %s\n%s---\n# %s\n' "$2" "${3:+me: true
}" "$2" > "$V/memory/people/$1.md"
}
commitment() { # commitment <id> <from slug> <to slug> <due>
  printf -- '---\ntype: commitment\ncreated: 2026-10-01\nfrom: "[[memory/people/%s]]"\nto: "[[memory/people/%s]]"\nstatus: open\nmade_in: "[[memory/meetings/2026/2026-10-01-kickoff]]"\ndue: %s\n---\n# %s\n' \
    "$2" "$3" "$4" "$1" > "$V/memory/commitments/$1.md"
}
fresh() {
  rm -rf "$V" && mkdir -p "$V/memory/people" "$V/memory/commitments" "$V/memory/meetings/2026"
  printf -- '---\ntype: meeting\ncreated: 2026-10-01\ndate: 2026-10-01\n---\n# Kickoff — 2026-10-01\n' > "$V/memory/meetings/2026/2026-10-01-kickoff.md"
  person sam-rivera "Sam Rivera"
  commitment send-proposal sam-rivera owner-slot 2026-10-05
  commitment share-deck owner-slot sam-rivera 2026-10-20
  git -C "$V" init -q && git -C "$V" add -A && git -C "$V" commit -q -m init
}
own() { # own <slug>: point the owner-slot links at <slug>
  sed -i.bak "s/owner-slot/$1/" "$V"/memory/commitments/*.md && rm -f "$V"/memory/commitments/*.bak
  git -C "$V" add -A && git -C "$V" commit -q -m owner
}
run() { "$SCRIPT" --vault "$V" "$@" > "$WORK/out" 2> "$WORK/err"; RC=$?; }
first_id() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[0]["id"])' "$WORK/out"; }
mine_ids() { python3 -c 'import json,sys; print(" ".join(c["id"] for c in json.load(open(sys.argv[1])) if c["mine"]))' "$WORK/out"; }

# --------------------------------------------------------------------------
banner "(1) the owner by me: true"
fresh; person jordan "Jordan Lee" me; own jordan
run list --json
check_exit 0 "$RC"
if [ "$(first_id)" = "share-deck" ]; then ok "the owner's commitment first"; else bad "first: $(first_id)"; fi
if [ "$(mine_ids)" = "share-deck" ]; then ok "only the owner's is mine"; else bad "mine: $(mine_ids)"; fi

# --------------------------------------------------------------------------
banner "(2) the owner by git user.name"
fresh; person alex-example "Alex Example"; own alex-example
run list --json
if [ "$(mine_ids)" = "share-deck" ]; then ok "the note named after git user.name"; else bad "mine: $(mine_ids)"; fi

# --------------------------------------------------------------------------
banner "(3) no owner note"
fresh; own nobody
run list --json
check_exit 0 "$RC"
if [ -z "$(mine_ids)" ]; then ok "nothing is mine"; else bad "mine: $(mine_ids)"; fi
run list
contains "$WORK/out" "0 of them yours"

# --------------------------------------------------------------------------
banner "(4) set done"
fresh; person jordan "Jordan Lee" me; own jordan
today="$(date +%Y-%m-%d)"
run set share-deck "done"
check_exit 0 "$RC"
f="$V/memory/commitments/share-deck.md"
contains "$f" "status: done"
contains "$f" "done_on: $today"
contains "$f" "- $today — Jordan Lee confirmed it done. ([[sources/confirmations/$today-cli]])"
c="$V/sources/confirmations/$today-cli.md"
contains "$c" 'author: "Jordan Lee"'
contains "$c" "Jordan Lee's own word is the evidence"
contains "$c" "done: share-deck"
if [ -z "$(git -C "$V" status --porcelain)" ]; then ok "the vault is committed"; else bad "uncommitted: $(git -C "$V" status --porcelain | tr '\n' ' ')"; fi

banner "(5) a second change the same day"
run set send-proposal dropped
check_exit 0 "$RC"
if [ "$(grep -c '^- ' "$c")" = 2 ]; then ok "appended to the confirmation note"; else bad "confirmation lines: $(grep -c '^- ' "$c")"; fi
contains "$V/memory/commitments/send-proposal.md" "Jordan Lee dropped it: no longer needed."

# --------------------------------------------------------------------------
banner "(6) usage"
head_before="$(git -C "$V" rev-parse HEAD)"
run set share-deck finished
check_exit 2 "$RC"
run set no-such-id "done"
check_exit 2 "$RC"
if [ "$(git -C "$V" rev-parse HEAD)" = "$head_before" ]; then ok "nothing committed"; else bad "HEAD moved"; fi

# --------------------------------------------------------------------------
ids() { python3 -c 'import json,sys; print(" ".join(c["id"] for c in json.load(open(sys.argv[1]))))' "$WORK/out"; }
banner "(7) list --overdue, --due-within"
fresh; person jordan "Jordan Lee" me; own jordan
run list --json --overdue --date 2026-10-14
if [ "$(ids)" = "send-proposal" ]; then ok "overdue on 10-14"; else bad "overdue: $(ids)"; fi
run list --json --due-within 7 --date 2026-10-14
if [ "$(ids)" = "share-deck send-proposal" ]; then ok "due within 7 days, overdue included"; else bad "within: $(ids)"; fi
run list --json --due-within 7 --date 2026-10-10
if [ "$(ids)" = "send-proposal" ]; then ok "10-20 is not within 7 days of 10-10"; else bad "within: $(ids)"; fi

# --------------------------------------------------------------------------
banner "(8) brief"
person casey-ng "Casey Ng"
printf -- '---\ntype: meeting\ncreated: 2026-10-13\ndate: 2026-10-13\nattendees: ["[[memory/people/jordan]]", "[[memory/people/sam-rivera]]"]\n---\n# Pricing call — 2026-10-13\n' > "$V/memory/meetings/2026/2026-10-13-pricing.md"
printf -- '---\ntype: meeting\ncreated: 2026-10-13\ndate: 2026-10-13\nattendees:\n  - "[[memory/people/sam-rivera]]"\n  - "[[memory/people/casey-ng|Casey]]"\ntranscript: "[[sources/transcripts/x]]"\n---\n# Design review — 2026-10-13\n' > "$V/memory/meetings/2026/2026-10-13-design.md"
printf -- '---\ntype: meeting\ncreated: 2026-10-12\ndate: 2026-10-12\nattendees: ["[[memory/people/casey-ng]]"]\n---\n# Earlier — 2026-10-12\n' > "$V/memory/meetings/2026/2026-10-12-earlier.md"
run brief --json --date 2026-10-14
check_exit 0 "$RC"
got="$(python3 -c '
import json,sys; d=json.load(open(sys.argv[1]))
print(d["met"]["date"], [c["id"] for c in d["overdue"]], [c["id"] for c in d["due_soon"]],
      [(p["name"], [m["title"] for m in p["meetings"]]) for p in d["met"]["people"]])' "$WORK/out")"
want="2026-10-13 ['send-proposal'] ['share-deck'] [('Sam Rivera', ['Design review', 'Pricing call']), ('Casey Ng', ['Design review'])]"
if [ "$got" = "$want" ]; then ok "overdue, due soon, met yesterday"; else bad "brief: $got"; fi
run brief --date 2026-10-12 --days 7
contains "$WORK/out" "Due by 2026-10-19 (0)"
run brief --date 2026-10-15 --days 7
contains "$WORK/out" "Due by 2026-10-22 (1)"
contains "$WORK/out" "Met on 2026-10-14 (0)"

# --------------------------------------------------------------------------
banner "(9) a bad --date"
run brief --date 14-10-2026
check_exit 2 "$RC"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
