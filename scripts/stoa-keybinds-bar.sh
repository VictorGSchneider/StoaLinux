#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Keybinds cheatsheet                           ║
# ║    text → the cheatsheet as plain text (used by Super+/)     ║
# ║    bar  → compact apps line     ┐ legacy waybar custom       ║
# ║    info → JSON with tooltip     ┘ modules, kept for the i3   ║
# ║                                   session and any external   ║
# ║                                   bar that still wants them  ║
# ╚══════════════════════════════════════════════════════════════╝

STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"

if [ -f "$STOA_CONF" ]; then
    # shellcheck source=/dev/null
    source "$STOA_CONF"
fi

STOA_SHOW_KEYBINDS="${STOA_SHOW_KEYBINDS:-true}"
MODE="${1:-bar}"

# ── Compact bar text: only the most-used apps ──
SEP=" • "
BAR_TEXT="⏎ Term${SEP}␣ Rofi${SEP}B Brave${SEP}E Files${SEP}O Notes${SEP}V Clip"

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
  Super+Space          Launcher (Noctalia)
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
  Super+V              Clipboard history
  Super+Shift+B        Clear

▸ Tools
  Super+Shift+T        OCR
  Super+Shift+P        Advanced paste
  Super+Shift+S        Predict toggle
  Print                Screenshot (region)
  Shift+Print          Screenshot / recording (advanced)

▸ Shell
  Super+/              This cheatsheet
  Super+Ctrl+R         Restart the bar

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

emit() {
    local text=$1 tooltip=$2 class=$3
    printf '{"text": "%s", "tooltip": "%s", "class": "%s"}\n' \
        "$(escape_json "$text")" \
        "$(escape_json "$tooltip")" \
        "$class"
}

case "$MODE" in
    bar)
        if [ "$STOA_SHOW_KEYBINDS" != "true" ]; then
            echo ""
            exit 0
        fi
        emit "$BAR_TEXT" "$TOOLTIP" "keybinds"
        ;;
    info)
        if [ "$STOA_SHOW_KEYBINDS" = "true" ]; then
            class="keybinds-info on"
        else
            class="keybinds-info off"
        fi
        emit "⌨" "$TOOLTIP" "$class"
        ;;
    text)
        # Plain text, for rofi/notify consumers. Noctalia v5 has no
        # cheatsheet widget, so Super+/ renders this through rofi instead
        # of the waybar module that used to carry it.
        printf '%s\n' "$TOOLTIP"
        ;;
    *)
        echo "usage: $0 {text|bar|info}" >&2
        exit 2
        ;;
esac
