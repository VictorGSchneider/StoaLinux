#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Text Prediction Controller                    ║
# ║  "Words have power." — Marcus Aurelius                      ║
# ║                                                              ║
# ║  Toggle, select, and manage the prediction daemon.           ║
# ║  Requires: python-evdev, eww, wtype                          ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-predict toggle              — start/stop daemon + popup
#   stoa-predict select <index>      — accept suggestion at index (0-4)
#   stoa-predict select-emoji <idx>  — accept emoji at index
#   stoa-predict stop                — stop daemon

PIDFILE="/tmp/stoa-predict.pid"
SUGGEST_FILE="/tmp/stoa-predict.json"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PREDICT_PY="${SCRIPT_DIR}/stoa-predict.py"

_notify() { dunstify -t 2500 "Text Predict" "$1" 2>/dev/null; }

_is_running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

_start() {
    if _is_running; then
        _notify "Already running"
        return
    fi

    # Check input group
    if ! groups 2>/dev/null | grep -qw input; then
        _notify "Add yourself to input group:\nsudo usermod -aG input \$USER\nThen log out and back in."
        return 1
    fi

    # Check python-evdev
    if ! python3 -c "import evdev" 2>/dev/null; then
        _notify "python-evdev not installed:\nsudo pacman -S python-evdev"
        return 1
    fi

    python3 "$PREDICT_PY" &
    disown
    _notify "Text prediction ON"
}

_stop() {
    if _is_running; then
        kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
        rm -f "$PIDFILE" "$SUGGEST_FILE"
        eww close predict 2>/dev/null
        _notify "Text prediction OFF"
    fi
}

_toggle() {
    if _is_running; then
        _stop
    else
        _start
    fi
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

    # Clear suggestions
    eww update 'predict-data={"prefix":"","words":[],"emojis":[],"visible":false}' 2>/dev/null
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

    # Clear suggestions
    eww update 'predict-data={"prefix":"","words":[],"emojis":[],"visible":false}' 2>/dev/null
}

case "${1:-}" in
    toggle)       _toggle ;;
    start)        _start ;;
    stop)         _stop ;;
    select)       _select "${2:-0}" ;;
    select-emoji) _select_emoji "${2:-0}" ;;
    *)
        echo "Usage: stoa-predict {toggle|start|stop|select N|select-emoji N}"
        exit 1
        ;;
esac
