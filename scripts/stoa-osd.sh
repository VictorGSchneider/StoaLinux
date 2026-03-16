#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — OSD (On-Screen Display)                       ║
# ║  Volume, brilho e CapsLock via dunstify progress bar.        ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Uso:
#   stoa-osd volume-up
#   stoa-osd volume-down
#   stoa-osd volume-mute
#   stoa-osd brightness-up
#   stoa-osd brightness-down
#   stoa-osd capslock

# IDs fixos para substituir notificações anteriores (sem empilhar)
VOLUME_ID=9901
BRIGHTNESS_ID=9902
CAPSLOCK_ID=9903

osd_volume() {
    local action="$1"

    case "$action" in
        up)   wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0 ;;
        down) wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- ;;
        mute) wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    esac

    local vol muted
    vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    muted=$(echo "$vol" | grep -c "MUTED")
    vol=$(echo "$vol" | awk '{printf "%.0f", $2 * 100}')

    if [ "$muted" -eq 1 ]; then
        dunstify -r "$VOLUME_ID" -u low -t 1500 " Volume" "Mudo" -h int:value:0
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
        up)   brightnessctl set +10% -q ;;
        down) brightnessctl set 10%- -q ;;
    esac

    local bri max pct
    bri=$(brightnessctl get 2>/dev/null)
    max=$(brightnessctl max 2>/dev/null)

    if [ -n "$bri" ] && [ -n "$max" ] && [ "$max" -gt 0 ]; then
        pct=$((bri * 100 / max))
        local icon=""
        [ "$pct" -le 30 ] && icon=""
        [ "$pct" -le 10 ] && icon=""
        dunstify -r "$BRIGHTNESS_ID" -u low -t 1500 "$icon Brilho" "${pct}%" -h int:value:"$pct"
    fi
}

osd_capslock() {
    local state=0

    # Tentar via LED do kernel
    local led_path
    for led_path in /sys/class/leds/*capslock*/brightness; do
        if [ -f "$led_path" ]; then
            state=$(cat "$led_path")
            break
        fi
    done

    # Fallback: xset (X11)
    if [ "$state" -eq 0 ] && command -v xset &>/dev/null; then
        state=$(xset q 2>/dev/null | grep "Caps Lock" | awk '{print ($4 == "on") ? 1 : 0}')
    fi

    if [ "$state" -eq 1 ]; then
        dunstify -r "$CAPSLOCK_ID" -u normal -t 2000 " CapsLock" "Ativado" -h int:value:100
    else
        dunstify -r "$CAPSLOCK_ID" -u low -t 1500 " CapsLock" "Desativado" -h int:value:0
    fi
}

case "$1" in
    volume-up)      osd_volume up ;;
    volume-down)    osd_volume down ;;
    volume-mute)    osd_volume mute ;;
    brightness-up)  osd_brightness up ;;
    brightness-down) osd_brightness down ;;
    capslock)       osd_capslock ;;
    *)
        echo "Uso: stoa-osd {volume-up|volume-down|volume-mute|brightness-up|brightness-down|capslock}"
        exit 1
        ;;
esac
