#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Capture (Screenshot + Recording)              ║
# ║  "Begin at once to live." — Seneca                           ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-capture                         Toggle widget / stop recording
#   stoa-capture <mode> <type> [delay]   Execute capture (called by eww)
#     mode:  selection | screen | window
#     type:  screenshot | recording
#     delay: seconds (0, 3, 5, 10) — screenshot only

set -uo pipefail

SCREENSHOT_DIR="${HOME}/Pictures/screenshots"
RECORD_DIR="${HOME}/Videos/recordings"
PIDFILE="/tmp/stoa-record.pid"

mkdir -p "$SCREENSHOT_DIR" "$RECORD_DIR"

_notify() {
    if command -v dunstify &>/dev/null; then
        dunstify -r 9998 -u "${2:-normal}" "Capture" "$1"
    fi
}

_is_recording() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

_stop_recording() {
    if _is_recording; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
        _notify "Recording saved to ~/Videos/recordings/"
        return 0
    fi
    return 1
}

_get_window_geom() {
    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        local json
        json=$(hyprctl activewindow -j 2>/dev/null)
        if [ -n "$json" ]; then
            local x y w h
            x=$(echo "$json" | jq -r '.at[0]')
            y=$(echo "$json" | jq -r '.at[1]')
            w=$(echo "$json" | jq -r '.size[0]')
            h=$(echo "$json" | jq -r '.size[1]')
            echo "${x},${y} ${w}x${h}"
        fi
    else
        xdotool getactivewindow 2>/dev/null
    fi
}

_screenshot() {
    local mode="$1"
    local delay="${2:-0}"
    local filename="${SCREENSHOT_DIR}/screenshot-$(date +%Y%m%d-%H%M%S).png"

    [ "$delay" -gt 0 ] 2>/dev/null && sleep "$delay"

    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        case "$mode" in
            selection)
                local geom
                geom=$(slurp 2>/dev/null) || return 0
                grim -g "$geom" - | satty -f - --output-filename "$filename"
                ;;
            window)
                local geom
                geom=$(_get_window_geom)
                if [ -n "$geom" ]; then
                    grim -g "$geom" - | satty -f - --output-filename "$filename"
                else
                    grim - | satty -f - --output-filename "$filename"
                fi
                ;;
            screen)
                grim - | satty -f - --output-filename "$filename"
                ;;
        esac
    else
        case "$mode" in
            selection) maim -s "$filename" ;;
            window)    maim -i "$(_get_window_geom)" "$filename" ;;
            screen)    maim "$filename" ;;
        esac
    fi

    [ -f "$filename" ] && _notify "Screenshot saved"
}

_record() {
    local mode="$1"
    local filename="${RECORD_DIR}/recording-$(date +%Y%m%d-%H%M%S).mp4"

    if [ "$XDG_SESSION_TYPE" = "wayland" ]; then
        if ! command -v wf-recorder &>/dev/null; then
            _notify "wf-recorder not found" "critical"
            return 1
        fi
        case "$mode" in
            selection)
                local geom
                geom=$(slurp 2>/dev/null) || return 0
                wf-recorder -g "$geom" -f "$filename" --audio &
                ;;
            window)
                local geom
                geom=$(_get_window_geom)
                if [ -n "$geom" ]; then
                    wf-recorder -g "$geom" -f "$filename" --audio &
                else
                    wf-recorder -f "$filename" --audio &
                fi
                ;;
            screen)
                wf-recorder -f "$filename" --audio &
                ;;
        esac
    else
        local resolution
        resolution=$(xdpyinfo 2>/dev/null | grep dimensions | awk '{print $2}')
        resolution="${resolution:-1920x1080}"

        case "$mode" in
            selection)
                local geom
                geom=$(slop -f "%x,%y %wx%h" 2>/dev/null) || return 0
                local offset size
                offset=$(echo "$geom" | awk '{print $1}')
                size=$(echo "$geom" | awk '{print $2}')
                ffmpeg -y -f x11grab -video_size "$size" -i "${DISPLAY}+${offset}" \
                       -f pulse -i default -c:v libx264 -preset ultrafast -crf 23 \
                       -c:a aac "$filename" &
                ;;
            screen)
                ffmpeg -y -f x11grab -video_size "$resolution" -i "${DISPLAY}+0,0" \
                       -f pulse -i default -c:v libx264 -preset ultrafast -crf 23 \
                       -c:a aac "$filename" &
                ;;
            window)
                ffmpeg -y -f x11grab -video_size "$resolution" -i "${DISPLAY}+0,0" \
                       -f pulse -i default -c:v libx264 -preset ultrafast -crf 23 \
                       -c:a aac "$filename" &
                ;;
        esac
    fi

    echo $! > "$PIDFILE"
    _notify "Recording started — press Print to stop" "low"
}

# ── Main ──
case "${1:-}" in
    "")
        # Toggle: stop recording → close widget → open widget
        if _stop_recording; then
            eww close capture 2>/dev/null
            exit 0
        fi
        if eww active-windows 2>/dev/null | grep -q "capture"; then
            eww close capture
        else
            eww update capture-mode="screen" capture-type="screenshot" capture-delay=0 2>/dev/null
            eww open capture
        fi
        ;;
    selection|screen|window)
        local_mode="$1"
        local_type="${2:-screenshot}"
        local_delay="${3:-0}"

        # Close widget first
        eww close capture 2>/dev/null

        if [ "$local_type" = "recording" ]; then
            _record "$local_mode"
        else
            # Small delay so the eww window disappears from the screenshot
            sleep 0.3
            _screenshot "$local_mode" "$local_delay"
        fi
        ;;
    stop)
        _stop_recording
        ;;
esac
