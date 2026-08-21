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

if ! command -v noctalia >/dev/null 2>&1; then
    echo "stoa-bar: noctalia is not installed — no shell to start." >&2
    echo "stoa-bar: install it with 'sudo pacman -S noctalia'." >&2
    exit 1
fi

exec noctalia
