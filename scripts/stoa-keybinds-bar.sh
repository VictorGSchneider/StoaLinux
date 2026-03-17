#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Keybinds Bar                                  ║
# ║  Waybar module: shows main keybinds in the bar               ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Reads STOA_SHOW_KEYBINDS from stoa.conf.
# Waybar hides custom modules with empty output.

STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"

# Load config
if [ -f "$STOA_CONF" ]; then
    # shellcheck source=/dev/null
    source "$STOA_CONF"
fi

# Default: enabled
STOA_SHOW_KEYBINDS="${STOA_SHOW_KEYBINDS:-true}"

if [ "$STOA_SHOW_KEYBINDS" != "true" ]; then
    echo ""
    exit 0
fi

# Compact text for the bar
TEXT="⏎ Term │ A Store │ B Brave │ C Calc │ D Rofi │ E Files │ I Settings │ N Monitor │ O Notes │ V Clipboard │ Esc Lock │ Q Close │ F Full │ HJKL Nav"

# Full tooltip
TOOLTIP="╔═══ STOA KEYBINDS ═══╗\n"
TOOLTIP+="Super+Enter   Terminal\n"
TOOLTIP+="Super+A       App Store\n"
TOOLTIP+="Super+B       Brave Browser\n"
TOOLTIP+="Super+C       Calculator\n"
TOOLTIP+="Super+D       Rofi (launcher)\n"
TOOLTIP+="Super+E       Files (lf)\n"
TOOLTIP+="Super+I       Settings\n"
TOOLTIP+="Super+N       Monitor (btop)\n"
TOOLTIP+="Super+O       Obsidian\n"
TOOLTIP+="Super+M       Memento Mori\n"
TOOLTIP+="Super+V       Clipboard (history)\n"
TOOLTIP+="Super+Shift+V Pin clipboard item\n"
TOOLTIP+="Super+Shift+T OCR (text extractor)\n"
TOOLTIP+="Super+Shift+P Advanced Paste\n"
TOOLTIP+="Super+Escape  Lock screen\n"
TOOLTIP+="Super+Q       Close window\n"
TOOLTIP+="Super+F       Fullscreen\n"
TOOLTIP+="Super+Shift+Space  Floating\n"
TOOLTIP+="─────────────────────\n"
TOOLTIP+="Super+HJKL    Navigation\n"
TOOLTIP+="Super+Shift+HJKL  Move window\n"
TOOLTIP+="Super+R       Resize mode\n"
TOOLTIP+="Super+1-0     Workspaces I-X\n"
TOOLTIP+="─────────────────────\n"
TOOLTIP+="Print         Screenshot (satty)\n"
TOOLTIP+="Super+Print   Screenshot (selection)\n"
TOOLTIP+="Super+/       Hide/show keybinds\n"
TOOLTIP+="╚═════════════════════╝"

# Waybar JSON format
printf '{"text": "%s", "tooltip": "%s", "class": "keybinds"}' "$TEXT" "$TOOLTIP"
