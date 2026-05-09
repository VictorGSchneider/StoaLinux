#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Keybinds Bar                                  ║
# ║  Waybar module: shows main keybinds in the bar               ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Reads STOA_SHOW_KEYBINDS from stoa.conf.
# Waybar hides custom modules with empty output.

STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"

if [ -f "$STOA_CONF" ]; then
    # shellcheck source=/dev/null
    source "$STOA_CONF"
fi

STOA_SHOW_KEYBINDS="${STOA_SHOW_KEYBINDS:-true}"

if [ "$STOA_SHOW_KEYBINDS" != "true" ]; then
    echo ""
    exit 0
fi

# ── Compact bar text (grouped by category) ──
SEP=" • "
WIN="⏎ Term${SEP}Q Close${SEP}F Full${SEP}⇧␣ Float"
NAV="HJKL Focus${SEP}⇧HJKL Move${SEP}R Resize${SEP}1–0 WS"
APP="␣ Rofi${SEP}B Brave${SEP}E Files${SEP}C Calc${SEP}O Notes${SEP}N Top"
TOOL="V Clip${SEP}⇧T OCR${SEP}⇧P Paste${SEP}Print Capture"
TEXT="${WIN}  │  ${NAV}  │  ${APP}  │  ${TOOL}"

# ── Full tooltip (organized into sections) ──
read -r -d '' TOOLTIP <<'EOF'
╔════════════ STOA KEYBINDS ════════════╗

▸ Window
  Super+Return         Terminal (kitty)
  Super+Q              Close window
  Super+F              Fullscreen
  Super+Shift+Space    Toggle floating
  Super+Escape         Lock screen
  Super+Ctrl+E         Exit Hyprland

▸ Mouse
  Super+LeftDrag       Move window
  Super+RightDrag      Resize window

▸ Navigation
  Super+H/J/K/L        Move focus
  Super+Shift+H/J/K/L  Move window
  Super+R              Resize mode (HJKL, Esc to exit)

▸ Workspaces
  Super+1–0            Switch to workspace 1–10
  Super+Shift+1–0      Move window to workspace 1–10

▸ Apps
  Super+Space          Rofi (launcher)
  Super+A              App Store
  Super+B              Brave
  Super+C              Calculator
  Super+E              Files (Thunar)
  Super+Shift+E        Files (lf in kitty)
  Super+G              DFM (Dotfile Manager)
  Super+M              Memento Mori
  Super+N              Monitor (btop)
  Super+O              Obsidian
  Super+S              Settings
  Super+W              WinApps

▸ Clipboard
  Super+V              Show history
  Super+Shift+V        Pin item
  Super+Shift+B        Clear

▸ Tools
  Super+Shift+T        OCR
  Super+Shift+P        Advanced paste
  Super+Shift+S        Predict toggle
  Print                Screenshot / recording

▸ Bar
  Super+/              Toggle this keybinds bar

╚═══════════════════════════════════════╝
EOF

# Escape for JSON: backslashes, quotes, then convert real newlines to \n
escape_json() {
    local s=$1
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    printf '%s' "$s"
}

TEXT_JSON=$(escape_json "$TEXT")
TOOLTIP_JSON=$(escape_json "$TOOLTIP")

printf '{"text": "%s", "tooltip": "%s", "class": "keybinds"}\n' "$TEXT_JSON" "$TOOLTIP_JSON"
