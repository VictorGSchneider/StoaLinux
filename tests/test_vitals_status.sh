#!/bin/bash
# Behavioural test for scripts/stoa-vitals-status and stoa-doctor-status.
#
# The widget decodes the vitals output with a JSON parser, so every doctor-log
# shape must yield valid JSON with the right counts. Regression: with no
# [FAIL]/[WARN] lines `grep -c ... || echo 0` printed "0" twice, splitting the
# value across two lines and breaking the whole document.
#
#   V1  log with no FAIL/WARN   -> valid JSON, issues 0, warnings 0
#   V2  log with FAIL and WARN  -> valid JSON, counts match
#   V3  no log                  -> valid JSON, issues -1
#   V4  stoa-doctor-status agrees with the vitals doctor block

cd "$(dirname "$0")/.." || exit 1
command -v jq >/dev/null || { echo "jq missing — skipped"; exit 0; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}
_run() { XDG_CONFIG_HOME="$TMP" "$@" 2>/dev/null; }
_doctor() { _run scripts/stoa-vitals-status | jq -r '"\(.doctor.issues) \(.doctor.warnings)"' 2>/dev/null || echo INVALID; }

mkdir -p "$TMP/stoa"
rm -f "$TMP/stoa/doctor.log"
_check "V3 no log"          "-1 0" "$(_doctor)"

printf '[OK]   a\n[INFO] b\n' > "$TMP/stoa/doctor.log"
_check "V1 clean log"       "0 0"  "$(_doctor)"

printf '[OK]   a\n[FAIL] x\n[FAIL] y\n[WARN] z\n' > "$TMP/stoa/doctor.log"
_check "V2 fail and warn"   "2 1"  "$(_doctor)"

_check "V4 doctor-status"   "2 1" \
    "$(_run scripts/stoa-doctor-status | jq -r '"\(.issues) \(.warnings)"' 2>/dev/null || echo INVALID)"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "vitals-status: all checks passed"
