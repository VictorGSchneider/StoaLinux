#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Bar launcher                                  ║
# ║  Picks the shell engine based on STOA_BAR in stoa.conf:     ║
# ║    noctalia    → Noctalia Shell (Quickshell, default)       ║
# ║    waybar      → legacy GTK fallback                        ║
# ║  Auto-detects whichever is installed if STOA_BAR is unset.  ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
if [ -f "$STOA_CONF" ]; then
    # shellcheck source=/dev/null
    source "$STOA_CONF"
fi

if [ -z "${STOA_BAR:-}" ]; then
    if command -v noctalia-shell >/dev/null 2>&1; then
        STOA_BAR=noctalia
    else
        STOA_BAR=waybar
    fi
fi

case "$STOA_BAR" in
    noctalia)
        if command -v noctalia-shell >/dev/null 2>&1; then
            exec noctalia-shell
        fi
        echo "stoa-bar: noctalia-shell not installed, falling back to waybar" >&2
        ;&
    waybar|*)
        exec waybar
        ;;
esac
