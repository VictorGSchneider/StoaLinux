#!/bin/bash
# Behavioural test for scripts/stoa-snapshot.sh, the logic behind the
# System (Btrfs) section of the stoa-health panel.
#
# snapper, findmnt, pacman, systemctl, pkexec and notify-send are stubbed;
# jq is real, because the JSON the panel parses is the point. Properties:
#
#   S1  ext4 root → available:false with the reason
#   S2  Btrfs root without Limine → available:false, reason names Limine
#   S3  Btrfs + Limine, no Snapper config → available, not configured
#   S4  configured and readable → count skips snapper's "current" (0), and
#       latest is the newest date
#   S5  configured but snapper refuses this user → readable:false, count -1
#   S6  create falls back to pkexec when snapper refuses the user, with the
#       same arguments
#   S7  create does not touch pkexec when the user may snapshot directly
#   S8  create without a Snapper config fails and calls nothing

cd "$(dirname "$0")/.." || exit 1

SCRIPT="$PWD/scripts/stoa-snapshot.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
LOG="$TMP/calls.log"
CFG="$TMP/snapper-root"

_stub() { printf '#!/bin/bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
_stub findmnt     '[ "$*" = "-no FSTYPE /" ] && echo "${FAKE_ROOT_FS:-btrfs}"'
_stub pacman      '[ "$1 $2" = "-Qq limine" ] && [ "${FAKE_LIMINE:-yes}" = yes ]'
_stub systemctl   '[ "${FAKE_LSS_ENABLED:-no}" = yes ]'
_stub notify-send 'exit 0'
_stub pkexec      'echo "pkexec $*" >> "$STUB_LOG"; exit 0'
_stub snapper '
echo "snapper $*" >> "$STUB_LOG"
[ "${FAKE_SNAPPER_DENY:-no}" = yes ] && { echo "No permissions." >&2; exit 1; }
if [ "$1" = "--jsonout" ]; then
cat <<JSON
{"root":[{"number":0,"date":"","description":"current"},
         {"number":1,"date":"2026-10-18 09:00:00","description":"a"},
         {"number":2,"date":"2026-10-19 08:30:00","description":"b"}]}
JSON
fi'

FAILS=0
_run() { # <args...> with FAKE_* in the environment
    : > "$LOG"
    env PATH="$BIN:/usr/bin:/bin" STUB_LOG="$LOG" SNAPPER_ROOT_CONFIG="$CFG" HOME="$TMP" \
        "${ENVV[@]}" bash "$SCRIPT" "$@"
}
_check() { # <name> <want> <got>
    [ "$2" = "$3" ] && return 0
    echo "FAIL $1"; echo "   want: $2"; echo "   got:  $3"; FAILS=$((FAILS + 1))
}
_status() { _run status | jq -c "$1"; }

rm -f "$CFG"
ENVV=(FAKE_ROOT_FS=ext4)
_check "S1 ext4"        '[false,"root is not Btrfs"]' "$(_status '[.available,.reason]')"
ENVV=(FAKE_LIMINE=no)
_check "S2 no limine"   '[false,"Limine is not the bootloader"]' "$(_status '[.available,.reason]')"
ENVV=()
_check "S3 not set up"  '[true,false]' "$(_status '[.available,.configured]')"

: > "$CFG"
ENVV=(FAKE_LSS_ENABLED=yes)
_check "S4 readable"    '[true,true,2,"2026-10-19 08:30:00"]' \
    "$(_status '[.configured,.bootMenu,.count,.latest]')"
ENVV=(FAKE_SNAPPER_DENY=yes)
_check "S5 not readable" '[true,false,-1]' "$(_status '[.configured,.readable,.count]')"

ENVV=(FAKE_SNAPPER_DENY=yes)
_run create my snap >/dev/null
_check "S6 pkexec fallback" "pkexec snapper -c root create --cleanup-algorithm number -d my snap" \
    "$(grep '^pkexec' "$LOG")"
ENVV=()
_run create my snap >/dev/null
_check "S7 no pkexec when allowed" "" "$(grep '^pkexec' "$LOG")"

rm -f "$CFG"
ENVV=()
_run create x >/dev/null; rc=$?
_check "S8 not configured" "1:" "${rc}:$(cat "$LOG")"

[ "$FAILS" -eq 0 ] || { echo "$FAILS check(s) failed"; exit 1; }
echo "stoa-snapshot: all checks passed"
