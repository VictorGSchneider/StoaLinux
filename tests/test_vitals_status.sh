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
#   V5  the doctor's "[hw]" lines are left out of the doctor counts (the
#       hardware block reports those live — counting both doubles an issue)
#   V6  the "hardware" key is an object, and the JSON stays valid
#   V7  without stoa-hardware next to it, "hardware" is null and nothing breaks

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

printf '[OK]   a\n[FAIL] [hw] ssd\n[WARN] [hw] gpu\n[WARN] real\n[FAIL]   [hw] spaced\n' > "$TMP/stoa/doctor.log"
_check "V5 hw lines excluded" "0 1" "$(_doctor)"

export XDG_CACHE_HOME="$TMP/cache"   # keep the SMART cache out of the real one
_check "V6 hardware object"  "object" \
    "$(_run scripts/stoa-vitals-status | jq -r '.hardware | type' 2>/dev/null || echo INVALID)"

mkdir -p "$TMP/lone"
cp scripts/stoa-vitals-status "$TMP/lone/"; cp -r scripts/lib "$TMP/lone/lib"
_check "V7 hardware absent"  "null" \
    "$(_run "$TMP/lone/stoa-vitals-status" | jq -r '.hardware | type' 2>/dev/null || echo INVALID)"

# V8 the boot-cleanup flag sees every way it can be scheduled — the systemd
# --user timer included (--schedule --user), which the flag used to miss.
mkdir -p "$TMP/stubs"
printf '#!/bin/bash\ncase "$*" in\n  "--user is-enabled "*) [ -e "$STUB_USER_TIMER" ] ;;\n  --failed*) exit 0 ;;\n  *) exit 1 ;;\nesac\n' > "$TMP/stubs/systemctl"
printf '#!/bin/bash\nexit 1\n' > "$TMP/stubs/crontab"
chmod +x "$TMP/stubs/systemctl" "$TMP/stubs/crontab"
_sched() { PATH="$TMP/stubs:$PATH" STUB_USER_TIMER="$TMP/user_timer" XDG_CONFIG_HOME="$TMP" \
    scripts/stoa-vitals-status 2>/dev/null | jq -r '.scheduled' 2>/dev/null || echo INVALID; }
rm -f "$TMP/user_timer"
_check "V8 not scheduled"            "false" "$(_sched)"
touch "$TMP/user_timer"
_check "V8 systemd --user timer"     "true"  "$(_sched)"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "vitals-status: all checks passed"
