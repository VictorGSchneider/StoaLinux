#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Keybinds cheatsheet (Super+/)                 ║
# ║                                                              ║
# ║  This used to toggle STOA_SHOW_KEYBINDS and signal waybar to ║
# ║  redraw its keybinds module. Waybar is gone and Noctalia v5  ║
# ║  ships no cheatsheet widget, so the binding renders the      ║
# ║  cheatsheet through a read-only yad text dialog instead.     ║
# ╚══════════════════════════════════════════════════════════════╝

# ── --help ──
case "${1:-}" in
    -h|--help)
        cat <<'STOA_HELP'
stoa-keybinds-toggle — show the keybind cheatsheet in a yad window (Super+/).

USAGE
  stoa-keybinds-toggle

Renders `stoa-keybinds-bar text` in a text dialog. Takes no arguments.

OPTIONS
  -h, --help    show this help

RESUMO RÁPIDO
  stoa-keybinds-toggle
  stoa-keybinds-toggle -h | --help
STOA_HELP
        exit 0
        ;;
esac

set -e

KEYBINDS_BIN="${HOME}/.local/bin/stoa-keybinds-bar"
[ -x "$KEYBINDS_BIN" ] || KEYBINDS_BIN="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/stoa-keybinds-bar.sh"

if ! command -v yad >/dev/null 2>&1; then
    notify-send "Stoa" "yad is not installed — cannot show the keybinds cheatsheet"
    exit 1
fi

"$KEYBINDS_BIN" text \
    | yad --text-info \
          --title="Stoa Keybinds" \
          --fontname="monospace 11" \
          --width=560 --height=640 \
          --button="Close:0" \
    >/dev/null 2>&1 || true
