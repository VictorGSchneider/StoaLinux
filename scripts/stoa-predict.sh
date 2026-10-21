#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Text Prediction Controller                    ║
# ║  "Words have power." — Marcus Aurelius                      ║
# ║                                                              ║
# ║  Toggle, select, and manage the prediction daemon.           ║
# ║  The popup is the Noctalia stoa/predict plugin; its service   ║
# ║  runs `stoa-predict run` and reads suggestions from stdout.   ║
# ║  Requires: python-evdev, wtype                               ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-predict toggle              — start/stop prediction (Super+Shift+S)
#   stoa-predict start | stop        — same, one direction
#   stoa-predict select <index>      — accept suggestion at index (0-4)
#   stoa-predict select-emoji <idx>  — accept emoji at index
#   stoa-predict run                 — the daemon itself; started by the plugin
#   stoa-predict kill                — stop the daemon; used by the plugin

# Prefer the per-user XDG_RUNTIME_DIR (typically /run/user/$UID) over
# world-writable /tmp. Falls back to /tmp only when unset (non-systemd).
_STOA_RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="${_STOA_RUNTIME}/stoa-predict.pid"
SUGGEST_FILE="${_STOA_RUNTIME}/stoa-predict.json"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PREDICT_PY="${SCRIPT_DIR}/stoa-predict.py"

PLUGIN_SERVICE="stoa/predict:service"

_notify() { notify-send -t 2500 "Text Predict" "$1" 2>/dev/null; }

# start/stop/toggle are owned by the plugin service: it is the process that
# reads the daemon's stdout, so it has to be the one that launches it.
_plugin() {
    if ! command -v noctalia &>/dev/null; then
        _notify "Text prediction needs the Noctalia shell (stoa/predict plugin)."
        return 1
    fi
    noctalia msg plugin "$PLUGIN_SERVICE" all "$1"
}

_is_running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

# Run by the plugin service through noctalia.runStream: stdout carries one
# JSON object per line. A failed precondition is reported the same way, as
# {"error": "..."}, so the service can show it.
_run() {
    # The service is the daemon's only owner. One still alive here was
    # orphaned (the shell restarted under it), and nothing reads its stdout.
    _kill
    if ! groups 2>/dev/null | grep -qw input; then
        echo '{"error":"Add yourself to the input group: sudo usermod -aG input $USER, then log out and back in."}'
        return 1
    fi
    if ! python3 -c "import evdev" 2>/dev/null; then
        echo '{"error":"python-evdev is not installed: sudo pacman -S python-evdev"}'
        return 1
    fi
    exec python3 "$PREDICT_PY"
}

# Called by the plugin service when prediction is switched off.
_kill() {
    if _is_running; then
        kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
    fi
    rm -f "$PIDFILE" "$SUGGEST_FILE"
}

# The suggestion was typed with wtype, which evdev never sees: tell the
# daemon to drop the prefix (it answers with an empty, hidden update).
_reset_daemon() {
    _is_running && kill -USR1 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

_select() {
    local index="${1:-0}"
    [ ! -f "$SUGGEST_FILE" ] && return

    local data
    data=$(cat "$SUGGEST_FILE" 2>/dev/null)
    [ -z "$data" ] && return

    local prefix word
    prefix=$(echo "$data" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('prefix',''))" 2>/dev/null)
    word=$(echo "$data" | python3 -c "import sys,json; d=json.load(sys.stdin); w=d.get('words',[]); print(w[$index] if $index<len(w) else '')" 2>/dev/null)

    [ -z "$word" ] && return

    # Erase the typed prefix with backspaces, then type the full word.
    # Build a single wtype invocation so all keystrokes land in one batch
    # — looping one `wtype -k BackSpace` per char dropped events on fast typers.
    local prefix_len=${#prefix}
    if [ "$prefix_len" -gt 0 ] && command -v wtype &>/dev/null; then
        local wtype_args=()
        local i
        for ((i = 0; i < prefix_len; i++)); do
            wtype_args+=(-k BackSpace)
        done
        wtype_args+=(-s 30 -- "${word} ")
        wtype "${wtype_args[@]}"
    fi

    _reset_daemon
}

_select_emoji() {
    local index="${1:-0}"
    [ ! -f "$SUGGEST_FILE" ] && return

    local data
    data=$(cat "$SUGGEST_FILE" 2>/dev/null)
    [ -z "$data" ] && return

    local emoji
    emoji=$(echo "$data" | python3 -c "import sys,json; d=json.load(sys.stdin); e=d.get('emojis',[]); print(e[$index]['emoji'] if $index<len(e) else '')" 2>/dev/null)

    [ -z "$emoji" ] && return

    if command -v wtype &>/dev/null; then
        wtype -- "$emoji"
    fi

    _reset_daemon
}

case "${1:-}" in
    toggle|start|stop) _plugin "$1" ;;
    run)          _run ;;
    kill)         _kill ;;
    select)       _select "${2:-0}" ;;
    select-emoji) _select_emoji "${2:-0}" ;;
    *)
        echo "Usage: stoa-predict {toggle|start|stop|select N|select-emoji N|run|kill}"
        exit 1
        ;;
esac
