#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Screen Recorder                               ║
# ║  "Begin at once to live." — Seneca                           ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Toggle screen recording on/off.
# Wayland: wf-recorder   |   Xorg: ffmpeg
#
# Usage:
#   stoa-record              Toggle full screen recording
#   stoa-record region       Toggle region recording (select area)
#   stoa-record stop         Stop current recording

set -euo pipefail

RECORD_DIR="${HOME}/Videos/recordings"
PIDFILE="/tmp/stoa-record.pid"

mkdir -p "$RECORD_DIR"

_notify() {
    if command -v dunstify &>/dev/null; then
        dunstify -r 9999 -u "$2" "Screen Recorder" "$1"
    elif command -v notify-send &>/dev/null; then
        notify-send "Screen Recorder" "$1"
    fi
}

_is_recording() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

_stop() {
    if _is_recording; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
        _notify "Recording saved to ~/Videos/recordings/" "normal"
    fi
}

_start() {
    local mode="${1:-full}"
    local filename="${RECORD_DIR}/recording-$(date +%Y%m%d-%H%M%S).mp4"

    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        if ! command -v wf-recorder &>/dev/null; then
            _notify "wf-recorder not found. Install: sudo pacman -S wf-recorder" "critical"
            exit 1
        fi

        if [ "$mode" = "region" ]; then
            local geom
            geom=$(slurp 2>/dev/null) || exit 0
            wf-recorder -g "$geom" -f "$filename" --audio &
        else
            wf-recorder -f "$filename" --audio &
        fi
    else
        if ! command -v ffmpeg &>/dev/null; then
            _notify "ffmpeg not found." "critical"
            exit 1
        fi

        local resolution
        resolution=$(xdpyinfo 2>/dev/null | grep dimensions | awk '{print $2}')
        resolution="${resolution:-1920x1080}"

        if [ "$mode" = "region" ]; then
            local geom
            geom=$(slop -f "%x,%y %wx%h" 2>/dev/null) || exit 0
            local offset size
            offset=$(echo "$geom" | awk '{print $1}')
            size=$(echo "$geom" | awk '{print $2}')
            ffmpeg -y -f x11grab -video_size "$size" -i "${DISPLAY}+${offset}" \
                   -f pulse -i default \
                   -c:v libx264 -preset ultrafast -crf 23 \
                   -c:a aac "$filename" &
        else
            ffmpeg -y -f x11grab -video_size "$resolution" -i "${DISPLAY}+0,0" \
                   -f pulse -i default \
                   -c:v libx264 -preset ultrafast -crf 23 \
                   -c:a aac "$filename" &
        fi
    fi

    echo $! > "$PIDFILE"
    _notify "Recording started ($([ "$mode" = "region" ] && echo "region" || echo "full screen"))" "low"
}

# ── Main ──
case "${1:-toggle}" in
    stop)
        _stop
        ;;
    region)
        if _is_recording; then
            _stop
        else
            _start region
        fi
        ;;
    *)
        if _is_recording; then
            _stop
        else
            _start full
        fi
        ;;
esac
