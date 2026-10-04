#!/usr/bin/env bash
# tests/dashboard.sh — drive bin/dashboard against temporary projects with a stub designer.
#
# Usage: ./tests/dashboard.sh
#
# No case calls a model. DASHBOARD_DESIGNER points at a stub that prints a canned reply chosen by
# $STUB_REPLY and logs each call; one case puts a fake `claude` on the PATH instead, to check the
# flags and folder the real designer would run with. XDG_CONFIG_HOME is per case, so the user's
# saved style is never read or written.
#
# Cases: (1) no saved style → exit 5, nothing written · (2) style validation and saving ·
# (3) init renders a self-contained page: slots filled, data escaped, CSP with the clock's hash,
# 10 s reload · (4) a row keeps its timestamp when its contents don't change · (5) a layout with a
# script, an outside resource or unknown markup is rejected after one retry, and no page is faked ·
# (6) a failed redesign keeps the last good page · (7) a corrupt saved layout keeps the last good
# page · (8) the validator's rules one by one · (9) the real designer runs with no tools, no settings,
# no MCP, from an empty folder outside the project · (10) writes stay in .dashboard/ and the style
# file · (11) a snapshot is labelled and does not reload · (12) init refuses to overwrite; --replace
# archives · (13) links are http(s) or files only
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
ROOT="$PWD"
SCRIPT="$ROOT/bin/dashboard"
[ -x "$SCRIPT" ] || { echo "bin/dashboard is not executable" >&2; exit 1; }
command -v uv > /dev/null || { echo "uv is required (bin/dashboard is a uv script)" >&2; exit 1; }

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cc-dashboard-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
lacks() { if grep -qF -- "$2" "$1"; then bad "$(basename "$1") has '$2'"; else ok "no: $2"; fi; }
exists() { if [ -e "$1" ]; then ok "exists: ${1#"$CASE"/}"; else bad "missing: ${1#"$CASE"/}"; fi; }
absent() { if [ -e "$1" ]; then bad "should not exist: ${1#"$CASE"/}"; else ok "absent: ${1#"$CASE"/}"; fi; }
same() { if cmp -s "$1" "$2"; then ok "unchanged: $3"; else bad "changed: $3"; fi; }

# Canned designer replies. good: every slot, allowed markup only.
write_replies() {
  R="$WORK/replies"
  mkdir -p "$R"
  cat > "$R/good" <<'EOF'
Here is the design.
```css
:root { --accent: #2a6df4; --bg: #fff; --fg: #111; }
[data-theme="dark"] { --bg: #111; --fg: #eee; }
body { background: var(--bg); color: var(--fg); font: 16px/1.5 system-ui, sans-serif; }
@media (max-width: 600px) { main { padding: 8px; } }
.dash-task[data-status="blocked"] { border-left: 4px solid var(--accent); }
```
```html
<header><h1 data-slot="title"></h1><p data-slot="goal"></p>
<p>Now <span data-slot="clock"></span> · Last update <span data-slot="updated"></span></p></header>
<main><div data-slot="summary"></div>
<section aria-label="Waiting for you"><h2>Waiting for you</h2><div data-slot="questions"></div></section>
<section><h2>Tasks</h2><div data-slot="tasks"></div></section>
<section><h2>Deliverables</h2><div data-slot="deliverables"></div></section>
<section><h2>Blockers</h2><div data-slot="blockers"></div><hr></section></main>
```
EOF
  sed 's#<main>#<main><script>alert(1)</script>#' "$R/good" > "$R/script"
  sed 's#--fg: \#111; }#--fg: \#111; background: url(https://example.com/x.png); }#' "$R/good" > "$R/url"
  sed 's#<header>#<header><img src="x.png">#' "$R/good" > "$R/img"
  sed 's#<h2>Tasks</h2>#<h2 onclick="x()">Tasks</h2>#' "$R/good" > "$R/onclick"
  sed 's#--fg: \#111; }#--fg: \#111; } .dash-badge + .dash-time { grid-row: 2; }#' "$R/good" > "$R/neighbour"
  sed 's#<h2>Tasks</h2>#<h2 style="color:red">Tasks</h2>#' "$R/good" > "$R/style-attr"
  sed 's#<div data-slot="blockers"></div>##' "$R/good" > "$R/missing-slot"
  sed 's#<div data-slot="tasks"></div>#<div data-slot="tasks">fake rows</div>#' "$R/good" > "$R/filled-slot"
  sed 's#<div data-slot="summary"></div>#<div data-slot="tasks"></div>#' "$R/good" > "$R/twice"
  perl -pe 's#^:root#\@import "https://example.com/a.css";\n:root#' "$R/good" > "$R/import"
  perl -pe 's#^\[data-theme#\@font-face { font-family: x; }\n[data-theme#' "$R/good" > "$R/font-face"
  sed 's#--accent: \#2a6df4;#--accent: \\75 rl(x);#' "$R/good" > "$R/backslash"
  sed 's#<h2>Tasks</h2>#<h2><a href="https://example.com">Tasks</a></h2>#' "$R/good" > "$R/link"
  # shellcheck disable=SC2016 # the backticks are a Markdown fence, not a command
  sed '/^```css$/,/^```$/d' "$R/good" > "$R/no-css"
  echo "I could not design this." > "$R/prose"
}

n=0
case_new() {
  n=$((n + 1))
  printf '\n(%s) %s\n' "$n" "$1"
  CASE="$WORK/case$n"
  PROJ="$CASE/project"
  OUT="$CASE/out.txt"
  LOG="$CASE/designer.log"
  mkdir -p "$PROJ" "$CASE/xdg" "$CASE/home"
  : > "$LOG"
  cat > "$CASE/designer" <<EOF
#!/bin/sh
echo "call cwd=\$(pwd) sp=\$DASHBOARD_SYSTEM_PROMPT_FILE" >> "$LOG"
cat > "$CASE/last-prompt.txt"
cat "$WORK/replies/\$STUB_REPLY"
EOF
  chmod +x "$CASE/designer"
  export XDG_CONFIG_HOME="$CASE/xdg" DASHBOARD_DESIGNER="$CASE/designer" DASHBOARD_DESIGN_GUIDANCE=""
  export STUB_REPLY=good
}
dash() { (cd "$PROJ" && "$SCRIPT" --dir "$PROJ" "$@") > "$OUT" 2>&1; }
style() { dash style --theme dark --density dense --accent '#2a6df4' > /dev/null; }
calls() { wc -l < "$LOG" | tr -d ' '; }
since() { jq -r --arg id "$2" ".${1}[] | select(.id == \$id) | .since" "$PROJ/.dashboard/state.json"; }

write_replies

case_new "no saved style → exit 5, nothing written"
dash init "A task"
check_exit 5 $?
contains "$OUT" "light, dark, or auto"
absent "$PROJ/.dashboard"
if [ "$(calls)" = 0 ]; then ok "designer not called"; else bad "designer called without a style"; fi

case_new "style: validation and saving"
dash style --theme dark --accent 'blue'
check_exit 2 $?
contains "$OUT" "hex colour"
dash style --theme dark
check_exit 2 $?
dash style --theme auto --accent '#000000'
check_exit 0 $?
contains "$CASE/xdg/claude-dashboard/style.json" '"theme": "auto"'
dash style --theme dark --density dense --accent '#2a6df4'
check_exit 0 $?
exists "$CASE/xdg/claude-dashboard/style.json"
if [ "$(jq -r '.theme + " " + .density + " " + .accent' "$CASE/xdg/claude-dashboard/style.json")" = "dark dense #2a6df4" ]; then
  ok "style saved"; else bad "style.json: $(cat "$CASE/xdg/claude-dashboard/style.json")"; fi
echo "Brand: navy and cream, serif headings." > "$CASE/brand.md"
dash style --brand "$CASE/brand.md"
check_exit 0 $?
dash init "Brand task"
contains "$CASE/last-prompt.txt" "navy and cream"
contains "$CASE/last-prompt.txt" "Theme: dark"

case_new "init: a self-contained page with escaped facts"
style
dash init 'Ship <b>v2</b> & "more"' --goal "Goal <i>text</i>" --task a="First <script>x</script>" --task b="Second"
check_exit 0 $?
P="$PROJ/.dashboard/index.html"
exists "$P"
contains "$P" '<meta http-equiv="refresh" content="10" />'
contains "$P" "script-src 'sha256-"
contains "$P" "Ship &lt;b&gt;v2&lt;/b&gt; &amp; &quot;more&quot;"
contains "$P" "First &lt;script&gt;x&lt;/script&gt;"
lacks "$P" "<script>x</script>"
lacks "$P" "{{"
contains "$P" 'data-theme="dark"'
contains "$P" 'class="dash-clock"'
contains "$P" 'class="dash-updated"'
contains "$P" 'data-status="pending"'
contains "$P" 'Nothing waiting for you'
contains "$CASE/last-prompt.txt" "[pending] First"
if [ "$(calls)" = 1 ]; then ok "designer called once"; else bad "designer called $(calls) times"; fi
if [ "$(grep -c '<script>' "$P")" = 1 ]; then ok "exactly one script (the clock)"; else bad "script count: $(grep -c '<script>' "$P")"; fi
# The CSP hash must be the hash of that one script, or the browser blocks the clock.
want="$(python3 - "$P" <<'PY'
import base64, hashlib, re, sys
s = open(sys.argv[1]).read()
print(base64.b64encode(hashlib.sha256(re.findall(r"<script>(.*?)</script>", s, re.S)[0].encode()).digest()).decode())
PY
)"
contains "$P" "sha256-$want"

case_new "a row keeps its timestamp when nothing changes; routine updates never call the designer"
style
dash init "Timestamps" --task a="Alpha" --task b="Beta"
a0="$(since tasks a)"; u0="$(jq -r .updated "$PROJ/.dashboard/state.json")"
cp "$PROJ/.dashboard/index.html" "$CASE/before.html"
sleep 1
dash task a pending
contains "$OUT" "no change"
if [ "$(since tasks a)" = "$a0" ]; then ok "row time kept"; else bad "row time moved on no change"; fi
if [ "$(jq -r .updated "$PROJ/.dashboard/state.json")" = "$u0" ]; then ok "last update kept"; else bad "last update moved on no change"; fi
same "$CASE/before.html" "$PROJ/.dashboard/index.html" "page on no change"
dash task b in_progress --note "half way"
check_exit 0 $?
if [ "$(since tasks b)" != "$a0" ]; then ok "changed row gets a new time"; else bad "changed row kept its old time"; fi
if [ "$(since tasks a)" = "$a0" ]; then ok "other rows keep theirs"; else bad "an unchanged row moved"; fi
dash question q1 "Publish the post?" --default "Wait for you" --hold
dash question q1 --applied
q1="$(since questions q1)"
dash question q1 --applied
if [ "$(since questions q1)" = "$q1" ]; then ok "question time kept"; else bad "question time moved"; fi
dash blocker b1 "Token expired"
dash deliverable d1 "Report" https://example.com/report
dash blocker b1 --clear
lacks "$PROJ/.dashboard/index.html" "Token expired"
dash question q1 --answer "yes"
lacks "$PROJ/.dashboard/index.html" "Publish the post?"
if [ "$(calls)" = 1 ]; then ok "designer called once in all"; else bad "designer called $(calls) times"; fi

case_new "rejected layouts: one retry, then a clear failure and no page"
style
for bad_reply in script url neighbour img onclick style-attr missing-slot filled-slot twice import font-face backslash link no-css prose; do
  rm -rf "$PROJ/.dashboard"
  : > "$LOG"
  STUB_REPLY=$bad_reply dash init "Rejected"
  rc=$?
  if [ "$rc" = 1 ] && [ ! -e "$PROJ/.dashboard/index.html" ] && [ "$(calls)" = 2 ]; then
    ok "$bad_reply: rejected after a retry, no page"
  else
    bad "$bad_reply: exit $rc, $(calls) calls, page $([ -e "$PROJ/.dashboard/index.html" ] && echo exists || echo absent)"
  fi
done
STUB_REPLY=script dash init "Rejected" --replace
contains "$OUT" "<script> is not an allowed element"
contains "$OUT" "rejected twice"
contains "$CASE/last-prompt.txt" "Your previous answer was rejected"
STUB_REPLY=missing-slot dash init "Rejected" --replace
contains "$OUT" "required slot 'blockers' is missing"
STUB_REPLY=url dash init "Rejected" --replace
contains "$OUT" "CSS contains 'url('"
STUB_REPLY=neighbour dash init "Rejected" --replace
contains "$OUT" ".dash-badge + .dash-time never matches"

case_new "a failed redesign keeps the last good page"
style
dash init "Keep me"
cp "$PROJ/.dashboard/index.html" "$CASE/good.html"
cp "$PROJ/.dashboard/layout.json" "$CASE/good-layout.json"
STUB_REPLY=onclick dash redesign
check_exit 1 $?
contains "$OUT" "attribute 'onclick' on <h2> is not allowed"
same "$CASE/good.html" "$PROJ/.dashboard/index.html" "index.html"
same "$CASE/good-layout.json" "$PROJ/.dashboard/layout.json" "layout.json"

case_new "a corrupt saved layout keeps the last good page"
style
dash init "Corrupt"
cp "$PROJ/.dashboard/index.html" "$CASE/good.html"
jq '.layout = "<div><script>x</script></div>"' "$PROJ/.dashboard/layout.json" > "$CASE/l.json" && cp "$CASE/l.json" "$PROJ/.dashboard/layout.json"
dash task t1 pending "New task"
check_exit 1 $?
contains "$OUT" "the saved layout fails validation"
same "$CASE/good.html" "$PROJ/.dashboard/index.html" "index.html"
echo "{not json" > "$PROJ/.dashboard/layout.json"
dash render
check_exit 1 $?
contains "$OUT" "last good page is unchanged"
same "$CASE/good.html" "$PROJ/.dashboard/index.html" "index.html"

case_new "the real designer: no tools, no settings, no MCP, an empty folder outside the project"
style
unset DASHBOARD_DESIGNER
mkdir -p "$CASE/bin"
cat > "$CASE/bin/claude" <<EOF
#!/bin/sh
for a in "\$@"; do printf '[%s]\n' "\$a"; done > "$CASE/argv.txt"
pwd > "$CASE/cwd.txt"
ls -A > "$CASE/ls.txt"
cat "$WORK/replies/good"
EOF
chmod +x "$CASE/bin/claude"
PATH="$CASE/bin:$PATH" dash init "Real flags"
check_exit 0 $?
for want in "[-p]" "[--model]" "[sonnet]" "[--effort]" "[medium]" "[--tools]" "[]" "[--strict-mcp-config]" \
            "[--setting-sources]" "[--disable-slash-commands]" "[--no-session-persistence]" "[--system-prompt-file]"; do
  contains "$CASE/argv.txt" "$want"
done
if grep -A1 -- '\[--tools\]' "$CASE/argv.txt" | tail -1 | grep -qx '\[\]'; then ok "--tools is empty"; else bad "--tools is not empty"; fi
if grep -A1 -- '\[--setting-sources\]' "$CASE/argv.txt" | tail -1 | grep -qx '\[\]'; then ok "--setting-sources is empty"; else bad "--setting-sources is not empty"; fi
case "$(cat "$CASE/cwd.txt")" in "$PROJ"*) bad "designer ran inside the project" ;; *) ok "designer ran outside the project" ;; esac
if [ ! -s "$CASE/ls.txt" ]; then ok "its folder is empty"; else bad "its folder holds: $(cat "$CASE/ls.txt")"; fi
sp="$(grep -A1 -- '\[--system-prompt-file\]' "$CASE/argv.txt" | tail -1 | tr -d '[]')"
if [ ! -e "$sp" ]; then ok "system prompt file removed afterwards"; else bad "system prompt file left behind"; fi

case_new "writes stay in .dashboard/ and the style file"
style
echo "keep" > "$PROJ/README.md"
dash init "Confined" --task a="A"
dash task a "done"
dash deliverable d "Readme" README.md
dash snapshot
found="$(cd "$CASE" && find project xdg -type f | sort | tr '\n' ' ')"
case "$found" in
  "project/.dashboard/index.html project/.dashboard/layout.json project/.dashboard/snapshot-"*".html project/.dashboard/state.json project/README.md xdg/claude-dashboard/style.json ")
    ok "only .dashboard/ and the style file" ;;
  *) bad "files: $found" ;;
esac
contains "$PROJ/.dashboard/index.html" "href=\"file://$PROJ/README.md\""

case_new "a snapshot is labelled and does not reload"
style
dash init "Snap"
dash snapshot
S="$(cat "$OUT")"
contains "$S" "this copy does not update"
contains "$S" "<title>Snapshot — Snap</title>"
lacks "$S" 'http-equiv="refresh"'

case_new "init refuses to overwrite; --replace archives"
style
dash init "First task"
dash init "Second task"
check_exit 2 $?
contains "$OUT" "already here"
dash init "Second task" --replace
check_exit 0 $?
if ls "$PROJ/.dashboard/archive/"*/state.json > /dev/null 2>&1; then ok "old state archived"; else bad "no archived state"; fi
contains "$PROJ/.dashboard/index.html" "Second task"

case_new "links: http(s) or files only"
style
dash init "Links"
dash deliverable d1 "Bad" "javascript:alert(1)"
check_exit 2 $?
dash deliverable d2 "Data" "data:text/html,hi"
check_exit 2 $?
dash deliverable d3 "Good" "https://example.com/x?a=1&b=2"
check_exit 0 $?
contains "$PROJ/.dashboard/index.html" 'href="https://example.com/x?a=1&amp;b=2"'
dash task bad-status "done!" "x"
check_exit 2 $?
dash task "../x" "done" "x"
check_exit 2 $?

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
