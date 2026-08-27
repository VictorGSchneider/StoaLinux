#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Bar launcher                                  ║
# ║  Starts the Noctalia v5 shell.                              ║
# ║                                                              ║
# ║  Kept as a script rather than calling `noctalia` directly    ║
# ║  because it also exports ~/.local/bin onto PATH — the        ║
# ║  Hyprland session does not have it, and the shell spawns     ║
# ║  stoa-* helpers.                                             ║
# ║                                                              ║
# ║  The waybar fallback and the legacy noctalia-qs (v4) branch   ║
# ║  are gone: v4 is unbuildable (Qt private ABI, dropped from   ║
# ║  the AUR) and waybar was only ever the stand-in for it.      ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

# When launched via exec-once from Hyprland (display manager or autologin),
# ~/.local/bin is not in PATH yet. Export it here so that anything the shell
# spawns can find the stoa-* scripts without hardcoding paths.
export PATH="${HOME}/.local/bin:${PATH}"

# Quickshell — and therefore Noctalia — takes its icon theme from the Qt
# platform theme. The session exports QT_QPA_PLATFORMTHEME=qt5ct, which is a
# Qt5-only plugin name: Qt6 never finds it, falls back to QGenericUnixTheme,
# and that reports "hicolor" as the system icon theme. Noctalia then resolves
# only the icons an application ships itself, so every desktop entry naming a
# generic freedesktop icon (avahi's network-wired, network-server, ...) draws
# the placeholder tile in the launcher, the dock and the taskbar.
#
# QS_ICON_THEME is read by Quickshell directly and wins over the platform
# theme, so point it at whatever GTK is already using — that keeps the shell
# in step with `stoa-settings` when the icon theme is switched there.
if [ -z "${QS_ICON_THEME:-}" ]; then
    _icon_theme=$(sed -n 's/^gtk-icon-theme-name[[:space:]]*=[[:space:]]*//p' \
        "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" 2>/dev/null | head -1)
    export QS_ICON_THEME="${_icon_theme:-Colloid-dark}"
fi

if ! command -v noctalia >/dev/null 2>&1; then
    echo "stoa-bar: noctalia is not installed — no shell to start." >&2
    echo "stoa-bar: install it with 'sudo pacman -S noctalia'." >&2
    exit 1
fi

exec noctalia
