#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — OSD action wrapper                            ║
# ║  Volume and brightness side-effects only — Noctalia draws    ║
# ║  the OSD natively via its volume/brightness/lock subsystems. ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-osd volume-up        stoa-osd volume-mute
#   stoa-osd volume-down      stoa-osd brightness-up
#   stoa-osd brightness-down
#
# capslock/numlock used to live here too; Noctalia's LockKeys widget +
# OSD show their state natively, so the keys are unbound at the WM
# layer and this script no longer reads /sys/class/leds.

case "$1" in
    volume-up)       wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+ -l 1.0 ;;
    volume-down)     wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%- ;;
    volume-mute)     wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    brightness-up)   brightnessctl set +1% -q ;;
    brightness-down) brightnessctl set 1%- -q ;;
    *)
        echo "Usage: stoa-osd {volume-up|volume-down|volume-mute|brightness-up|brightness-down}"
        exit 1
        ;;
esac
