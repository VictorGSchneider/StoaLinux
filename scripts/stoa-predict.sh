#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Text Prediction Controller                    ║
# ║  "Words have power." — Marcus Aurelius                      ║
# ║                                                              ║
# ║  Turns the prediction input method on and off. The daemon    ║
# ║  (stoa-predict.py) is a Wayland input method: its popup sits ║
# ║  next to the text cursor and it types the chosen word        ║
# ║  itself. The Noctalia stoa/predict plugin owns it — its      ║
# ║  service runs `stoa-predict run` and reads its stdout.       ║
# ║  Requires: python-pywayland, python-cairo, python-gobject    ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-predict toggle              — start/stop prediction (Super+Shift+S)
#   stoa-predict start | stop        — same, one direction
#   stoa-predict run                 — the daemon itself; started by the plugin
#   stoa-predict kill                — stop the daemon; used by the plugin

# Prefer the per-user XDG_RUNTIME_DIR (typically /run/user/$UID) over
# world-writable /tmp. Falls back to /tmp only when unset (non-systemd).
_STOA_RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="${_STOA_RUNTIME}/stoa-predict.pid"
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

# Stop the daemon and wait until it is gone: the compositor hands the input
# method to one client at a time, and a new instance started while the old
# one is still connected is refused ("unavailable").
_kill() {
    local pid tries=40
    pid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null
        while [ "$tries" -gt 0 ] && kill -0 "$pid" 2>/dev/null; do
            sleep 0.05
            tries=$((tries - 1))
        done
    fi
    rm -f "$PIDFILE"
}

# Run by the plugin service through noctalia.runStream. stdout carries one
# JSON object per line ({"ready": true} or {"error": "..."}); the daemon
# checks its own dependencies and reports them the same way.
_run() {
    # The service is the daemon's only owner. One still alive here was
    # orphaned (the shell restarted under it), and nothing reads its stdout.
    _kill
    exec python3 "$PREDICT_PY"
}

case "${1:-}" in
    toggle|start|stop) _plugin "$1" ;;
    run)          _run ;;
    kill)         _kill ;;
    *)
        echo "Usage: stoa-predict {toggle|start|stop|run|kill}"
        exit 1
        ;;
esac
