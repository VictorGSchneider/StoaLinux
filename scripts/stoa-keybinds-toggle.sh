#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Keybinds cheatsheet (Super+/)                 ║
# ║                                                              ║
# ║  This used to toggle STOA_SHOW_KEYBINDS and signal waybar to ║
# ║  redraw its keybinds module. Waybar is gone and Noctalia v5  ║
# ║  ships no cheatsheet widget, so the binding now renders the  ║
# ║  cheatsheet directly through rofi, which Stoa already themes.║
# ╚══════════════════════════════════════════════════════════════╝

set -e

KEYBINDS_BIN="${HOME}/.local/bin/stoa-keybinds-bar"
[ -x "$KEYBINDS_BIN" ] || KEYBINDS_BIN="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/stoa-keybinds-bar.sh"

if ! command -v rofi >/dev/null 2>&1; then
    notify-send "Stoa" "rofi is not installed — cannot show the keybinds cheatsheet"
    exit 1
fi

# -dmenu with no selection action: this is a read-only panel.
"$KEYBINDS_BIN" text \
    | rofi -dmenu -i -markup-rows -no-custom \
           -p "Keybinds" \
           -config ~/.config/rofi/config.rasi \
    >/dev/null || true
