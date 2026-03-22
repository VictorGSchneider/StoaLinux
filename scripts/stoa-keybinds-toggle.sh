#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Keybinds Toggle                               ║
# ║  Toggle keybinds display in Waybar                           ║
# ╚══════════════════════════════════════════════════════════════╝

STOA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa"
STOA_CONF="${STOA_DIR}/stoa.conf"

# Ensure directory and file exist
mkdir -p "$STOA_DIR"
if [ ! -f "$STOA_CONF" ]; then
    echo "STOA_SHOW_KEYBINDS=true" > "$STOA_CONF"
fi

# Read current value
source "$STOA_CONF"
CURRENT="${STOA_SHOW_KEYBINDS:-true}"

# Toggle
if [ "$CURRENT" = "true" ]; then
    if grep -q '^STOA_SHOW_KEYBINDS=' "$STOA_CONF"; then
        sed -i 's/^STOA_SHOW_KEYBINDS=.*/STOA_SHOW_KEYBINDS=false/' "$STOA_CONF"
    else
        echo "STOA_SHOW_KEYBINDS=false" >> "$STOA_CONF"
    fi
    notify-send -t 2000 "Stoa" "Bar keybinds: disabled"
else
    if grep -q '^STOA_SHOW_KEYBINDS=' "$STOA_CONF"; then
        sed -i 's/^STOA_SHOW_KEYBINDS=.*/STOA_SHOW_KEYBINDS=true/' "$STOA_CONF"
    else
        echo "STOA_SHOW_KEYBINDS=true" >> "$STOA_CONF"
    fi
    notify-send -t 2000 "Stoa" "Bar keybinds: enabled"
fi

# Reload Waybar to apply
pkill -SIGUSR2 waybar
