#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Bar launcher                                  ║
# ║  Picks the shell engine based on STOA_BAR in stoa.conf:     ║
# ║    noctalia    → noctalia (v5, default)                     ║
# ║    noctalia-qs → quickshell -c noctalia-shell (legacy v4)   ║
# ║    waybar      → GTK fallback                               ║
# ║  Auto-detects whichever is installed if STOA_BAR is unset.  ║
# ║                                                              ║
# ║  Noctalia v5 is a single native binary (/usr/bin/noctalia)   ║
# ║  configured from ~/.config/noctalia/*.toml. It replaces the  ║
# ║  v4 pair noctalia-qs + noctalia-shell, which was a Quickshell║
# ║  fork driving a QML tree under /etc/xdg/quickshell. v4 links ║
# ║  against Qt private APIs, so every Qt point release breaks   ║
# ║  it until it is rebuilt — the reason for this migration.     ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

# When launched via exec-once from Hyprland (display manager or autologin),
# ~/.local/bin is not in PATH yet. Export it here so that anything the shell
# spawns can find the stoa-* scripts without hardcoding paths.
export PATH="${HOME}/.local/bin:${PATH}"

STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
if [ -f "$STOA_CONF" ]; then
    # shellcheck source=/dev/null
    source "$STOA_CONF"
fi

# v5: a plain binary, unambiguous.
_noctalia_installed() {
    command -v noctalia >/dev/null 2>&1
}

# v4: the binary is just `quickshell`, ambiguous with upstream Quickshell,
# so detect it by its config tree instead.
_noctalia_qs_installed() {
    [ -d /etc/xdg/quickshell/noctalia-shell ] && command -v quickshell >/dev/null 2>&1
}

if [ -z "${STOA_BAR:-}" ]; then
    if _noctalia_installed; then
        STOA_BAR=noctalia
    elif _noctalia_qs_installed; then
        STOA_BAR=noctalia-qs
    else
        STOA_BAR=waybar
    fi
fi

case "$STOA_BAR" in
    noctalia)
        if _noctalia_installed; then
            exec noctalia
        fi
        echo "stoa-bar: noctalia (v5) not installed, falling back" >&2
        ;&
    noctalia-qs)
        if _noctalia_qs_installed; then
            exec quickshell -c noctalia-shell
        fi
        echo "stoa-bar: noctalia-shell (v4) not installed, falling back to waybar" >&2
        ;&
    waybar|*)
        exec waybar
        ;;
esac
