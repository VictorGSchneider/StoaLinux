#!/bin/bash
# Behavioural test for setup/lib/greetd-prestart.sh (greetd's ExecStartPre).
#
# The helper holds greetd back until Plymouth has let go of the GPU and pins
# the greeter's compositor to the panel's card. It runs on every boot as
# root, so what matters is that it is bounded, never fails the unit, and
# only pins when that is right. /dev/dri, sysfs and /proc are fakes under a
# temp dir; pgrep, fuser, logger and systemctl are stubs. Properties:
#
#   G1  two cards, eDP connected on card1: pins card1 (not a number fixed at
#       install time — the second case moves it to card0)
#   G2  same machine, eDP on card0: pins card0
#   G3  a single card: no env file, and a stale one from a past boot is removed
#   G4  two cards but no connected eDP: no env file
#   G5  greetd.service already sets WLR_DRM_DEVICES: we do not pin (CachyOS /
#       an admin outranks us on GPU configuration)
#   G6  plymouthd alive for the first polls: the helper waits for it
#   G7  plymouthd that never exits: bounded by STOA_WAIT_TICKS, exit 0
#   G8  a non-system process holding a card: waited on; systemd/logind alone
#       are ignored
#   G9  every case above exits 0 (a hiccup must never stop the login screen)

cd "$(dirname "$0")/.." || exit 1

SCRIPT="$PWD/setup/lib/greetd-prestart.sh"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"

_stub() { # <name> <body>
    printf '#!/bin/bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"
}
# pgrep: succeeds (prints a pid) for the first $PLY_ALIVE_CALLS calls.
_stub pgrep   'n=$(cat "$CALLS/pgrep" 2>/dev/null || echo 0); echo $((n + 1)) > "$CALLS/pgrep"
               [ "$n" -lt "${PLY_ALIVE_CALLS:-0}" ] && { echo 247; exit 0; }; exit 1'
# fuser: lists $HOLDER_PIDS for the first $HOLD_CALLS calls.
_stub fuser   'n=$(cat "$CALLS/fuser" 2>/dev/null || echo 0); echo $((n + 1)) > "$CALLS/fuser"
               [ "$n" -lt "${HOLD_CALLS:-0}" ] && echo "$DRI/card1: ${HOLDER_PIDS:-}"; exit 0'
_stub logger  'echo "$*" >> "$LOG"'
_stub systemctl 'echo "${FAKE_UNIT_ENV:-}"'

FAILS=0
_case() { # <name> <want-rc> <env file: yes|no> [VAR=val ...]
    local name="$1" want_rc="$2" want_env="$3"; shift 3
    local d="$TMP/$name"; rm -rf "$d"; mkdir -p "$d/dri" "$d/sys" "$d/proc" "$d/calls" "$d/run"
    : > "$d/log"
    # Fake machine: CARDS="card0 card1", EDP="card1" (connected eDP owner).
    local c
    for c in ${CARDS:-card0 card1}; do : > "$d/dri/$c"; done
    if [ -n "${EDP:-}" ]; then
        mkdir -p "$d/sys/${EDP}-eDP-1"; echo connected > "$d/sys/${EDP}-eDP-1/status"
    fi
    mkdir -p "$d/proc/1" "$d/proc/777" "$d/proc/4242"
    echo systemd > "$d/proc/1/comm"; echo systemd-logind > "$d/proc/777/comm"
    echo plymouthd > "$d/proc/4242/comm"
    [ -n "${STALE_ENV:-}" ] && echo "WLR_DRM_DEVICES=stale" > "$d/run/greetd-gpu.env"

    local rc
    env PATH="$BIN:/usr/bin:/bin" CALLS="$d/calls" LOG="$d/log" DRI="$d/dri" \
        STOA_DRI_DEV="$d/dri" STOA_DRM_SYSFS="$d/sys" STOA_PROC="$d/proc" \
        STOA_GREETD_ENV="$d/run/greetd-gpu.env" STOA_WAIT_STEP=0.01 \
        "$@" bash "$SCRIPT" >/dev/null 2>&1; rc=$?
    LAST_DIR="$d"
    if [ "$rc" -ne "$want_rc" ]; then
        echo "FAIL $name: exit $rc, want $want_rc"; FAILS=$((FAILS + 1)); return 1
    fi
    if [ "$want_env" = yes ] && [ ! -f "$d/run/greetd-gpu.env" ]; then
        echo "FAIL $name: expected an env file, none written"; FAILS=$((FAILS + 1)); return 1
    fi
    if [ "$want_env" = no ] && [ -f "$d/run/greetd-gpu.env" ]; then
        echo "FAIL $name: env file exists, should not:"; sed 's/^/   /' "$d/run/greetd-gpu.env"
        FAILS=$((FAILS + 1)); return 1
    fi
    echo "ok   $name"
}
_expect() { # <name> <file> <pattern>
    grep -q -- "$3" "$2" || { echo "FAIL $1: '$3' not in $(basename "$2")"; FAILS=$((FAILS + 1)); }
}

# G1 / G2 — the card is read from the machine, not assumed.
EDP=card1 _case G1-pins-card1 0 yes && _expect G1 "$LAST_DIR/run/greetd-gpu.env" "WLR_DRM_DEVICES=$LAST_DIR/dri/card1$"
EDP=card0 _case G2-pins-card0 0 yes && _expect G2 "$LAST_DIR/run/greetd-gpu.env" "WLR_DRM_DEVICES=$LAST_DIR/dri/card0$"
# G3 — one GPU: nothing to pin; a leftover from a two-GPU boot goes.
CARDS="card0" EDP=card0 STALE_ENV=1 _case G3-single-gpu 0 no
# G4 — two cards, no connected eDP.
EDP="" _case G4-no-panel 0 no
# G5 — someone else already chose; they win.
EDP=card1 _case G5-defers-to-existing 0 no FAKE_UNIT_ENV="WLR_DRM_DEVICES=/dev/dri/card0 FOO=1" \
    && _expect G5 "$LAST_DIR/log" "already sets WLR_DRM_DEVICES"

# G6 — waits while plymouthd is alive (pgrep is also called for the log line).
EDP=card1 _case G6-waits-for-plymouthd 0 yes PLY_ALIVE_CALLS=6 \
    && { [ "$(cat "$LAST_DIR/calls/pgrep")" -gt 6 ] || { echo "FAIL G6: did not poll past plymouthd"; FAILS=$((FAILS + 1)); }
         _expect G6 "$LAST_DIR/log" "clear after"; }
# G7 — plymouthd never exits: bounded.
EDP=card1 _case G7-bounded 0 yes PLY_ALIVE_CALLS=100000 STOA_WAIT_TICKS=4 \
    && _expect G7 "$LAST_DIR/log" "gave up after 4 polls"
# G8 — a real holder is waited on; systemd/logind alone are not.
EDP=card1 _case G8a-waits-for-holder 0 yes HOLD_CALLS=6 HOLDER_PIDS="1 777 4242" \
    && { [ "$(cat "$LAST_DIR/calls/fuser")" -gt 6 ] || { echo "FAIL G8a: did not wait for the holder"; FAILS=$((FAILS + 1)); }; }
EDP=card1 _case G8b-ignores-systemd 0 yes HOLD_CALLS=100000 HOLDER_PIDS="1 777" \
    && _expect G8b "$LAST_DIR/log" "clear after 0 polls"

[ "$FAILS" -eq 0 ] && echo "all greetd-prestart properties hold" && exit 0
echo "$FAILS failure(s)"; exit 1
