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
#   stoa-predict languages           — catalog: code, name, enabled, downloaded
#   stoa-predict set-languages CODE… — download what is missing, save the
#                                      choice, restart prediction if running

# Prefer the per-user XDG_RUNTIME_DIR (typically /run/user/$UID) over
# world-writable /tmp. Falls back to /tmp only when unset (non-systemd).
_STOA_RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="${_STOA_RUNTIME}/stoa-predict.pid"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PREDICT_PY="${SCRIPT_DIR}/stoa-predict.py"

PLUGIN_SERVICE="stoa/predict:service"

# ── Prediction languages ──
# Word lists are FrequencyWords (Hermit Dave; OpenSubtitles 2018, content
# CC BY-SA 4.0): the 50 000 commonest words per language with their counts,
# so suggestions come most-frequent first. Downloaded on demand (~600 KB
# each) into LANG_DIR; the daemon reads the codes listed in LANG_FILE.
LANG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/predict-languages"
LANG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/stoa/predict"
LANG_URL="https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018"
LANGUAGES=(
    "en|English"
    "pt_br|Português (Brasil)"
    "pt|Português (Portugal)"
    "es|Español"
    "fr|Français"
    "de|Deutsch"
    "it|Italiano"
    "nl|Nederlands"
    "ca|Català"
    "ro|Română"
    "pl|Polski"
    "cs|Čeština"
    "sv|Svenska"
    "da|Dansk"
    "no|Norsk"
    "fi|Suomi"
    "hu|Magyar"
    "tr|Türkçe"
    "el|Ελληνικά"
    "ru|Русский"
    "uk|Українська"
)

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

_enabled_languages() {
    if [ -f "$LANG_FILE" ]; then
        grep -v '^#' "$LANG_FILE" | sed '/^[[:space:]]*$/d'
    else
        echo en    # the daemon's default too
    fi
}

_known_language() {
    local entry
    for entry in "${LANGUAGES[@]}"; do
        [ "${entry%%|*}" = "$1" ] && return 0
    done
    return 1
}

# One line per catalog language: code<TAB>name<TAB>enabled<TAB>downloaded
_languages() {
    local entry code enabled downloaded
    local -a on
    mapfile -t on < <(_enabled_languages)
    for entry in "${LANGUAGES[@]}"; do
        code="${entry%%|*}"
        enabled=no
        [[ " ${on[*]} " == *" $code "* ]] && enabled=yes
        downloaded=no
        [ -s "$LANG_DIR/$code.txt" ] && downloaded=yes
        printf '%s\t%s\t%s\t%s\n' "$code" "${entry#*|}" "$enabled" "$downloaded"
    done
}

_download_language() {
    local code="$1" tmp
    mkdir -p "$LANG_DIR"
    tmp=$(mktemp "$LANG_DIR/.$code.XXXXXX") || return 1
    if curl -fsSL --max-time 120 -o "$tmp" "$LANG_URL/$code/${code}_50k.txt" && [ -s "$tmp" ]; then
        mv -f "$tmp" "$LANG_DIR/$code.txt"
    else
        rm -f "$tmp"
        return 1
    fi
}

# Save the language choice. Missing lists are downloaded first; if one
# fails nothing is saved, so the previous choice keeps working.
_set_languages() {
    local code
    [ "$#" -gt 0 ] || { echo "set-languages: give at least one language code" >&2; return 2; }
    for code in "$@"; do
        _known_language "$code" || { echo "set-languages: unknown language '$code'" >&2; return 2; }
    done
    for code in "$@"; do
        [ -s "$LANG_DIR/$code.txt" ] && continue
        if ! _download_language "$code"; then
            echo "set-languages: could not download '$code' (offline?)" >&2
            return 1
        fi
    done
    mkdir -p "$(dirname "$LANG_FILE")"
    {
        echo "# Text prediction languages (Stoa Settings → Keyboard → Text prediction)."
        printf '%s\n' "$@"
    } > "$LANG_FILE"
    # The daemon reads the lists once at start; restart it if it is on. The
    # choice is saved either way, so a failed restart is only a warning.
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        if ! { _plugin stop && _plugin start; } >/dev/null 2>&1; then
            echo "set-languages: saved; turn text prediction off and on to use them" >&2
        fi
    fi
    return 0
}

case "${1:-}" in
    toggle|start|stop) _plugin "$1" ;;
    run)          _run ;;
    kill)         _kill ;;
    languages)    _languages ;;
    set-languages) shift; _set_languages "$@" ;;
    *)
        echo "Usage: stoa-predict {toggle|start|stop|run|kill|languages|set-languages CODE...}"
        exit 1
        ;;
esac
