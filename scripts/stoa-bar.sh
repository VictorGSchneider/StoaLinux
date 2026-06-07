#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Bar launcher                                  ║
# ║  Picks the shell engine based on STOA_BAR in stoa.conf:     ║
# ║    noctalia    → quickshell -c noctalia-shell (default)     ║
# ║    waybar      → legacy GTK fallback                        ║
# ║  Auto-detects whichever is installed if STOA_BAR is unset.  ║
# ║                                                              ║
# ║  Note: the noctalia-qs package ships /usr/bin/quickshell    ║
# ║  (their Quickshell fork) and noctalia-shell ships its QML   ║
# ║  config tree under /etc/xdg/quickshell/noctalia-shell —     ║
# ║  hence the `-c noctalia-shell` selector.                    ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

# When launched via exec-once from Hyprland (display manager or autologin),
# ~/.local/bin is not in PATH yet. Export it here so that every Quickshell
# Process that calls stoa-* scripts can find them without hardcoding paths.
export PATH="${HOME}/.local/bin:${PATH}"

STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
if [ -f "$STOA_CONF" ]; then
    # shellcheck source=/dev/null
    source "$STOA_CONF"
fi

# A Noctalia install is detected by the presence of its config tree
# (the binary is just `quickshell`, which is ambiguous with upstream).
_noctalia_installed() {
    [ -d /etc/xdg/quickshell/noctalia-shell ] && command -v quickshell >/dev/null 2>&1
}

if [ -z "${STOA_BAR:-}" ]; then
    if _noctalia_installed; then
        STOA_BAR=noctalia
    else
        STOA_BAR=waybar
    fi
fi

case "$STOA_BAR" in
    noctalia)
        if _noctalia_installed; then
            exec quickshell -c noctalia-shell
        fi
        echo "stoa-bar: noctalia-shell not installed, falling back to waybar" >&2
        ;&
    waybar|*)
        exec waybar
        ;;
esac
