#!/usr/bin/env bash
# tests/analytics.sh — drive bin/analytics offline (ANALYTICS_OFFLINE=1): no Google call is made.
#
# Usage: ./tests/analytics.sh
#
# Cases: (1) init writes a starter analytics.yaml and refuses to overwrite it · (2) setup and sync plan
# the right GA and GTM objects, write nothing, and never publish · (3) the spec is validated: event
# names, funnel steps, custom dimensions, report metrics, missing project/domain · (4) snippet prints the
# GTM tags and one dataLayer.push per event · (5) a missing analytics.yaml is a clear error
#
# Exit codes: 0 every case passed · 1 a case failed
#
# bash 3.2: no arrays, no mapfile, no ${x^^}.
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/bin/analytics"
[ -x "$SCRIPT" ] || { echo "bin/analytics is not executable" >&2; exit 1; }
command -v uv > /dev/null || { echo "uv is required" >&2; exit 1; }

WORK="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cc-analytics-test.XXXXXX")" && pwd -P)"
trap 'rm -rf "$WORK"' EXIT
export ANALYTICS_OFFLINE=1
# Account defaults come from a throwaway root, so the test needs no real analytics.defaults.yaml.
mkdir -p "$WORK/root"
cp analytics.defaults.example.yaml "$WORK/root/analytics.defaults.yaml"
export CC_ROOT="$WORK/root"

PASS=0
FAIL=0
ok()  { printf '    ok   %s\n' "$*"; PASS=$((PASS + 1)); }
bad() { printf '    FAIL %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
check_exit() { if [ "$1" = "$2" ]; then ok "exit $2"; else bad "exit: want $1, got $2"; fi; }
contains() { if grep -qF -- "$2" "$1"; then ok "says: $2"; else bad "$(basename "$1") has no '$2'"; fi; }
lacks() { if grep -qF -- "$2" "$1"; then bad "$(basename "$1") has '$2'"; else ok "no: $2"; fi; }

n=0
case_new() { n=$((n + 1)); printf '\n(%s) %s\n' "$n" "$1"; D="$WORK/case$n"; OUT="$WORK/out$n.txt"; mkdir -p "$D"; }
run() { "$SCRIPT" "$@" > "$OUT" 2>&1; }

case_new "init writes a starter and refuses to overwrite"
run init "$D" --project "Test Site" --domain test.example.com
check_exit 0 $?
contains "$D/analytics.yaml" "project: Test Site"
contains "$D/analytics.yaml" "domain: test.example.com"
contains "$D/analytics.yaml" "Marketing events only"
run init "$D" --project X --domain y.com
check_exit 2 $?
contains "$OUT" "already exists"
run init "$WORK/other"
check_exit 2 $?

case_new "setup and sync plan, write nothing, never publish"
run init "$D" --project "Test Site" --domain test.example.com
cp "$D/analytics.yaml" "$WORK/before.yaml"
run setup "$D"
check_exit 0 $?
contains "$OUT" "would create GA property 'Test Site'"
contains "$OUT" "would create web stream https://test.example.com"
contains "$OUT" "would create GTM web container 'Test Site'"
run sync "$D"
check_exit 0 $?
contains "$OUT" "would GA custom dimension 'method'"
contains "$OUT" "would GA key event 'sign_up'"
contains "$OUT" "would GTM data-layer variable 'method'"
contains "$OUT" "would GTM trigger on dataLayer event 'generate_lead'"
contains "$OUT" "would GTM GA4 event tag for 'sign_up' with method"
contains "$OUT" "would create a GTM container version (not published)"
lacks "$OUT" "publish "
if cmp -s "$WORK/before.yaml" "$D/analytics.yaml"; then ok "analytics.yaml unchanged"; else bad "analytics.yaml changed"; fi

case_new "the spec is validated"
cat > "$D/analytics.yaml" <<'EOF'
project: Bad
domain: bad.example.com
events:
  - name: Sign-Up
  - name: purchase
    params: [value]
  - name: purchase
custom_dimensions:
  - parameter: plan
funnels:
  one: {steps: [page_view]}
  ghost: {steps: [page_view, checkout]}
reports:
  empty: {dimensions: [country]}
EOF
run setup "$D"
check_exit 2 $?
contains "$OUT" "event name 'Sign-Up'"
contains "$OUT" "event names repeat"
contains "$OUT" "custom dimension 'plan' is not a parameter of any event"
contains "$OUT" "funnel one: needs at least two steps"
contains "$OUT" "funnel ghost: step 'checkout' is not an event in this file"
contains "$OUT" "report empty: needs metrics"
printf 'domain: x.com\n' > "$D/analytics.yaml"
run sync "$D"
check_exit 2 $?
contains "$OUT" "\`project\` is required"

case_new "snippet: GTM tags and one push per event"
run init "$D" --project "Snip" --domain snip.example.com
run snippet "$D"
check_exit 0 $?
contains "$OUT" "googletagmanager.com/gtm.js"
contains "$OUT" "GoogleTagManager gtmId="
contains "$OUT" "window.dataLayer.push({ event: 'sign_up', method: … })"
contains "$OUT" "window.dataLayer.push({ event: 'generate_lead' })"

case_new "no analytics.yaml"
run setup "$D"
check_exit 5 $?
contains "$OUT" "analytics init"

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
