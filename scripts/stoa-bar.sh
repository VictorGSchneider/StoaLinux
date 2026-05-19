#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Bar launcher                                  ║
# ║  Picks the bar engine based on STOA_BAR in stoa.conf:       ║
# ║    quickshell  → ~/.config/quickshell/shell.qml (default)   ║
# ║    waybar      → ~/.config/waybar (legacy)                  ║
# ║  Falls back to whichever binary is installed if the config  ║
# ║  doesn't specify a preference.                               ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
if [ -f "$STOA_CONF" ]; then
    # shellcheck source=/dev/null
    source "$STOA_CONF"
fi

# Default: quickshell if present, otherwise waybar.
if [ -z "${STOA_BAR:-}" ]; then
    if command -v quickshell >/dev/null 2>&1; then
        STOA_BAR=quickshell
    else
        STOA_BAR=waybar
    fi
fi

case "$STOA_BAR" in
    quickshell)
        if command -v quickshell >/dev/null 2>&1; then
            exec quickshell
        fi
        echo "stoa-bar: quickshell not installed, falling back to waybar" >&2
        ;&
    waybar|*)
        exec waybar
        ;;
esac
