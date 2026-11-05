#!/bin/bash
# stoa-health cleanup / cleanup-dry-run must open a terminal and run
# stoa-maintain there. stoa-maintain --cleanup refuses to start without a
# terminal (its sudo calls would each be a failed login to pam_faillock), so
# the widget button that ran it in the background always failed.
#
# The terminal is a stub that runs what it is handed; stoa-maintain is a stub
# that records its arguments. Nothing is cleaned.
cd "$(dirname "$0")/.." || exit 1

TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.local/bin" "$TMP/home/.config/stoa"
FAILS=0
_check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then printf '  ✓ %s\n' "$1"
    else printf '  ✗ %s: expected [%s], got [%s]\n' "$1" "$2" "$3"; FAILS=$((FAILS + 1)); fi
}

cat > "$TMP/home/.local/bin/stoa-maintain" <<'STUB'
#!/bin/bash
echo "tty=$([ -t 0 ] && echo yes || echo no) args=$*" > "$STUB_OUT"
STUB
cat > "$TMP/term" <<'STUB'
#!/bin/bash
# <term> --title T -e bash -c CMD  →  run CMD, remember the title
echo "$2" > "$STUB_TITLE"
shift 3
"$@" < /dev/null
STUB
chmod +x "$TMP/home/.local/bin/stoa-maintain" "$TMP/term"

_run() { # <subcommand> → what stoa-maintain saw, "" if it never ran
    rm -f "$TMP/out" "$TMP/title"
    env HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/home/.config" TERMINAL="$TMP/term" \
        STUB_OUT="$TMP/out" STUB_TITLE="$TMP/title" \
        bash scripts/stoa-health.sh "$1" < /dev/null > /dev/null 2>&1
    local i
    for i in $(seq 1 50); do [ -s "$TMP/out" ] && break; sleep 0.1; done
    sed 's/^tty=[a-z]* //' "$TMP/out" 2>/dev/null
}

_check "T1 cleanup goes through the terminal"   "args=--cleanup"            "$(_run cleanup)"
_check "T2 cleanup opened a terminal"                    "Stoa — Cleanup"             "$(cat "$TMP/title" 2>/dev/null)"
_check "T3 dry-run goes through the terminal"   "args=--cleanup --dry-run"   "$(_run cleanup-dry-run)"
_check "T4 dry-run opened a terminal"                    "Stoa — Cleanup preview"     "$(cat "$TMP/title" 2>/dev/null)"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "health-cleanup: all checks passed"
