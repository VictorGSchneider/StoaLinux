#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — OSD (On-Screen Display)                       ║
# ║  Volume, brightness, CapsLock and NumLock via dunstify.      ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-osd volume-up        stoa-osd volume-mute
#   stoa-osd volume-down      stoa-osd brightness-up
#   stoa-osd brightness-down  stoa-osd capslock
#   stoa-osd numlock

# Fixed IDs to replace previous notifications (no stacking)
VOLUME_ID=9901
BRIGHTNESS_ID=9902
CAPSLOCK_ID=9903
NUMLOCK_ID=9904

osd_volume() {
    local action="$1"

    case "$action" in
        up)   wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+ -l 1.0 ;;
        down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%- ;;
        mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    esac

    local vol muted
    vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    muted=$(echo "$vol" | grep -c "MUTED")
    vol=$(echo "$vol" | awk '{printf "%.0f", $2 * 100}')

    if [ "$muted" -eq 1 ]; then
        dunstify -r "$VOLUME_ID" -u low -t 1500 " Volume" "Muted" -h int:value:0
    else
        local icon=""
        [ "$vol" -le 30 ] && icon=""
        [ "$vol" -eq 0 ] && icon=""
        dunstify -r "$VOLUME_ID" -u low -t 1500 "$icon Volume" "${vol}%" -h int:value:"$vol"
    fi
}

osd_brightness() {
    local action="$1"

    case "$action" in
        up)   brightnessctl set +1% -q ;;
        down) brightnessctl set 1%- -q ;;
    esac

    local bri max pct
    bri=$(brightnessctl get 2>/dev/null)
    max=$(brightnessctl max 2>/dev/null)

    if [ -n "$bri" ] && [ -n "$max" ] && [ "$max" -gt 0 ]; then
        pct=$((bri * 100 / max))
        local icon=""
        [ "$pct" -le 30 ] && icon=""
        [ "$pct" -le 10 ] && icon=""
        dunstify -r "$BRIGHTNESS_ID" -u low -t 1500 "$icon Brightness" "${pct}%" -h int:value:"$pct"
    fi
}

_read_lock_state() {
    local lock_name="$1"
    local state=""

    # Give the kernel a moment to propagate the LED change after the
    # keypress. Without this the sysfs value still reflects the
    # pre-toggle state on fast hardware.
    sleep 0.05

    # A system can expose multiple LED nodes for the same lock (e.g.
    # input2::capslock, input5::capslock for a second keyboard, plus
    # vendor LEDs like tpacpi::numlock). Iterating only the first match
    # is unreliable because some of those LEDs stay latched on and the
    # script then reports "Enabled" forever. Treat the lock as enabled
    # if *any* matching LED reports a non-zero brightness.
    local led_path val
    for led_path in /sys/class/leds/*${lock_name}*/brightness; do
        [ -f "$led_path" ] || continue
        val=$(cat "$led_path" 2>/dev/null)
        [[ "$val" =~ ^[0-9]+$ ]] || continue
        if [ "$val" -gt 0 ]; then
            state=1
            break
        fi
        state=0
    done

    # Fallback: xset (X11) — only if no LED file was found
    if [ -z "$state" ] && command -v xset &>/dev/null; then
        local label
        case "$lock_name" in
            capslock) label="Caps Lock" ;;
            numlock)  label="Num Lock" ;;
        esac
        state=$(xset q 2>/dev/null | awk -v lbl="$label" '
            $0 ~ lbl { for(i=1;i<=NF;i++) if($i ~ /on|off/) { print ($i=="on") ? 1 : 0; exit } }
        ')
    fi

    echo "${state:-0}"
}

osd_capslock() {
    local state
    state=$(_read_lock_state capslock)

    if [ "$state" -eq 1 ]; then
        dunstify -r "$CAPSLOCK_ID" -u normal -t 2000 " CapsLock" "Enabled" -h int:value:100
    else
        dunstify -r "$CAPSLOCK_ID" -u low -t 1500 " CapsLock" "Disabled" -h int:value:0
    fi
}

osd_numlock() {
    local state
    state=$(_read_lock_state numlock)

    if [ "$state" -eq 1 ]; then
        dunstify -r "$NUMLOCK_ID" -u normal -t 2000 " NumLock" "Enabled" -h int:value:100
    else
        dunstify -r "$NUMLOCK_ID" -u low -t 1500 " NumLock" "Disabled" -h int:value:0
    fi
}

case "$1" in
    volume-up)       osd_volume up ;;
    volume-down)     osd_volume down ;;
    volume-mute)     osd_volume mute ;;
    brightness-up)   osd_brightness up ;;
    brightness-down) osd_brightness down ;;
    capslock)        osd_capslock ;;
    numlock)         osd_numlock ;;
    *)
        echo "Usage: stoa-osd {volume-up|volume-down|volume-mute|brightness-up|brightness-down|capslock|numlock}"
        exit 1
        ;;
esac
