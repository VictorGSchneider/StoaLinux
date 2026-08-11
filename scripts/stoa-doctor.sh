#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Doctor (Health Check)                         ║
# ║  "Know thyself." — inscribed at Delphi                       ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Runs at startup to verify that all binaries and services
# required by Stoa scripts are present and functional.
# Reports issues via desktop notifications (notify-send → Noctalia).

set -o pipefail

STOA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa"
LOG="${STOA_DIR}/doctor.log"
mkdir -p "$STOA_DIR"

ISSUES=()
WARNINGS=()

_ok()   { echo "[OK]   $1" >> "$LOG"; }
_warn() { echo "[WARN] $1" >> "$LOG"; WARNINGS+=("$1"); }
_fail() { echo "[FAIL] $1" >> "$LOG"; ISSUES+=("$1"); }

_check_bin() {
    local bin="$1"
    local desc="${2:-$1}"
    if command -v "$bin" &>/dev/null; then
        _ok "$desc ($bin)"
    else
        _fail "$desc — '$bin' not found"
    fi
}

_check_optional() {
    local bin="$1"
    local desc="${2:-$1}"
    if command -v "$bin" &>/dev/null; then
        _ok "$desc ($bin)"
    else
        _warn "$desc — '$bin' not found (optional)"
    fi
}

# ── Start ──
{
    echo "════════════════════════════════════════"
    echo "  Stoa Doctor — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "════════════════════════════════════════"
} > "$LOG"

# ══════════════════════════════════════════
#   Core binaries
# ══════════════════════════════════════════

_check_bin rofi         "Settings panel (rofi)"
_check_bin notify-send  "Notifications (libnotify)"
_check_bin jq           "JSON parser (jq)"
_check_bin eww          "Widgets (eww)"
_check_bin waybar       "Status bar (waybar)"

# ── Display / WM ──
if [ "$XDG_SESSION_TYPE" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    _check_bin hyprctl      "Hyprland control (hyprctl)"
    _check_bin grim         "Screenshot (grim)"
    _check_bin slurp        "Region select (slurp)"
    _check_bin wf-recorder  "Screen recording (wf-recorder)"
    _check_bin swaybg       "Wallpaper (swaybg)"
    _check_bin wl-paste     "Clipboard (wl-clipboard)"
    _check_bin cliphist     "Clipboard history (cliphist)"
    _check_optional satty   "Screenshot editor (satty)"
    if [ -x /usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1 ] \
        || command -v hyprpolkitagent &>/dev/null \
        || command -v lxpolkit &>/dev/null; then
        echo "[OK] Polkit agent present" >> "$LOG"
    else
        echo "[WARN] No polkit authentication agent found (polkit-gnome / hyprpolkitagent / lxpolkit)" >> "$LOG"
    fi

    # ── Hyprland version check ──
    if command -v hyprctl &>/dev/null; then
        HYPR_VER=$(hyprctl version -j 2>/dev/null | jq -r '.tag // .version // empty' 2>/dev/null | head -1)
        if [ -n "$HYPR_VER" ]; then
            echo "[INFO] Hyprland version: ${HYPR_VER}" >> "$LOG"

            # Test hyprctl getoption format (changed between versions)
            _test_output=$(hyprctl getoption general:border_size 2>/dev/null)
            if echo "$_test_output" | grep -q "int:"; then
                echo "[INFO] hyprctl getoption: legacy format (int:/float:/str:)" >> "$LOG"
                echo "legacy" > "${STOA_DIR}/hyprctl-format"
            elif echo "$_test_output" | grep -qE "^[0-9]"; then
                echo "[INFO] hyprctl getoption: new format (raw value)" >> "$LOG"
                echo "raw" > "${STOA_DIR}/hyprctl-format"
            else
                _warn "hyprctl getoption returned unexpected format"
                echo "unknown" > "${STOA_DIR}/hyprctl-format"
            fi

            # Save version for scripts to check
            echo "$HYPR_VER" > "${STOA_DIR}/hyprland-version"

            # ── Lua config floor ──
            # Stoa ships config/hypr/hyprland.lua. Hyprland only reads it
            # from 0.55 onward; older builds silently ignore it and fall
            # back to their own defaults (or a stale hyprland.conf), which
            # looks like "my whole desktop reverted" rather than an error.
            _hypr_major=$(echo "$HYPR_VER" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
            _hypr_minor=$(echo "$HYPR_VER" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f2)
            if [ -n "$_hypr_minor" ] \
                && [ "${_hypr_major:-0}" -eq 0 ] && [ "$_hypr_minor" -lt 55 ]; then
                _warn "Hyprland ${HYPR_VER} predates 0.55 — hyprland.lua is ignored. Upgrade Hyprland."
            fi
        else
            _warn "Could not detect Hyprland version"
        fi
    fi
else
    _check_bin i3           "Window manager (i3)"
    _check_bin maim         "Screenshot (maim)"
    _check_bin xrandr       "Display config (xrandr)"
    _check_bin xdotool      "Window tools (xdotool)"
    _check_bin picom        "Compositor (picom)"
    _check_bin feh          "Wallpaper (feh)"
    _check_bin xclip        "Clipboard (xclip)"
fi

# ── Audio ──
_check_bin wpctl        "Audio control (WirePlumber)"
_check_optional pactl   "PulseAudio ctl (pactl)"

# ── Brightness ──
_check_bin brightnessctl "Brightness control"

# ── Network ──
_check_bin nmcli        "NetworkManager (nmcli)"
_check_optional iwctl   "iwd Wi-Fi (iwctl)"
_check_optional bluetoothctl "Bluetooth (bluetoothctl)"

# ── File manager ──
_check_bin thunar       "File manager (Thunar)"

# ── Terminal ──
_terminal_found=""
for _t in kitty alacritty foot wezterm ghostty xterm konsole gnome-terminal xfce4-terminal; do
    if command -v "$_t" &>/dev/null; then
        _terminal_found="$_t"
        break
    fi
done
if [ -n "$_terminal_found" ]; then
    _ok "Terminal ($_terminal_found)"
else
    _warn "Terminal — no terminal emulator found"
fi
unset _t _terminal_found

# ── Utilities ──
_check_bin curl         "HTTP client (curl)"
_check_bin tesseract    "OCR (tesseract)"

# ── Dotfile Manager (Super+G) ──
_check_bin dfm          "Dotfile Manager (dfm)"

# ══════════════════════════════════════════
#   Service checks
# ══════════════════════════════════════════

# PipeWire
if pgrep -x pipewire &>/dev/null; then
    _ok "PipeWire is running"
else
    _warn "PipeWire is not running — audio may not work"
fi

# Notification daemon — Noctalia owns org.freedesktop.Notifications on
# the Hyprland/Wayland path. stoa-bar launches it as
# `quickshell -c noctalia-shell` (or `qs -c noctalia-shell`); the AUR
# noctalia-shell package also ships a launcher of the same name. Match
# the cmdline substring "noctalia-shell" with pgrep -f so we catch all
# three forms.
if pgrep -f 'noctalia-shell' &>/dev/null; then
    _ok "Noctalia Shell is running (notifications)"
else
    _warn "Noctalia Shell is not running — notifications won't show"
fi

# ══════════════════════════════════════════
#   Directories
# ══════════════════════════════════════════

for dir in \
    "${HOME}/Pictures/screenshots" \
    "${HOME}/Videos/recordings" \
    "${STOA_DIR}/wallpapers" \
    "${STOA_DIR}/pkg-snapshots"; do
    if [ -d "$dir" ]; then
        _ok "Directory exists: $dir"
    else
        mkdir -p "$dir"
        _warn "Created missing directory: $dir"
    fi
done

# ══════════════════════════════════════════
#   Report
# ══════════════════════════════════════════

{
    echo "────────────────────────────────────────"
    echo "  Issues: ${#ISSUES[@]}  |  Warnings: ${#WARNINGS[@]}"
    echo "────────────────────────────────────────"
} >> "$LOG"

# Notify user of problems
if [ ${#ISSUES[@]} -gt 0 ]; then
    msg="Missing: ${#ISSUES[@]} required\n"
    for issue in "${ISSUES[@]:0:5}"; do
        msg+="• ${issue}\n"
    done
    [ ${#ISSUES[@]} -gt 5 ] && msg+="… and $((${#ISSUES[@]} - 5)) more (see doctor.log)"

    if command -v notify-send &>/dev/null; then
        notify-send -r 9990 -u critical -t 10000 "Stoa Doctor" "$msg"
    else
        echo -e "STOA DOCTOR:\n$msg" >&2
    fi
elif [ ${#WARNINGS[@]} -gt 0 ]; then
    if command -v notify-send &>/dev/null; then
        notify-send -r 9990 -u low -t 5000 "Stoa Doctor" "${#WARNINGS[@]} warnings — see ~/.config/stoa/doctor.log"
    fi
fi

# Quiet exit if all good
[ ${#ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ] && {
    echo "[INFO] All checks passed." >> "$LOG"
}

exit 0
