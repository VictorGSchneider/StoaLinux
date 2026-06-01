#!/bin/bash
# Stoa Store — core helpers, rofi wrappers, theme reapplication.

ROFI=(rofi -dmenu -i -config "${HOME}/.config/rofi/config.rasi")
APPIMAGE_DIR="${HOME}/Applications"

_notify()    { notify-send -t 2500 "Stoa Store" "$1" 2>/dev/null; }
_rofi()      { "${ROFI[@]}" -p "$1"; }
_rofi_list() { local p="$1"; shift; printf '%s\n' "$@" | "${ROFI[@]}" -p "$p"; }
_rofi_input(){ echo "" | "${ROFI[@]}" -p "$1"; }

_confirm() {
    local r; r=$(_rofi_list "$1" "  Yes" "  No")
    [[ "$r" == *Yes* ]]
}

_helper() {
    command -v yay  &>/dev/null && { echo yay;  return; }
    command -v paru &>/dev/null && { echo paru; return; }
    echo pacman
}
_has_aur()       { [[ "$(_helper)" != "pacman" ]]; }
_is_installed()  { pacman -Qi "$1" &>/dev/null; }

_run_in_term() {
    local term="${TERMINAL:-}"
    if [ -z "$term" ] || ! command -v "$term" &>/dev/null; then
        for c in kitty alacritty foot xterm; do
            command -v "$c" &>/dev/null && { term="$c"; break; }
        done
    fi
    if [ -z "$term" ] || ! command -v "$term" &>/dev/null; then
        _notify "No terminal emulator found (need kitty/alacritty/foot/xterm)"
        return 1
    fi
    "$term" -e bash -c "$1; echo; echo 'Press Enter to close...'; read"
}

_apply_stoa_theme() {
    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    [ ! -f "$gtk3" ] && return
    local t i c f
    t=$(grep "^gtk-theme-name"        "$gtk3" | sed 's/^[^=]*=\s*//')
    i=$(grep "^gtk-icon-theme-name"   "$gtk3" | sed 's/^[^=]*=\s*//')
    c=$(grep "^gtk-cursor-theme-name" "$gtk3" | sed 's/^[^=]*=\s*//')
    f=$(grep "^gtk-font-name"         "$gtk3" | sed 's/^[^=]*=\s*//')
    if command -v gsettings &>/dev/null; then
        gsettings set org.gnome.desktop.interface gtk-theme    "${t:-Adwaita-dark}"    2>/dev/null
        gsettings set org.gnome.desktop.interface icon-theme   "${i:-Colloid-dark}"    2>/dev/null
        gsettings set org.gnome.desktop.interface cursor-theme "${c:-Colloid-cursors}" 2>/dev/null
        gsettings set org.gnome.desktop.interface font-name    "${f:-EB Garamond 11}"  2>/dev/null
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"           2>/dev/null
    fi
    [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null && \
        hyprctl setcursor "${c:-Colloid-cursors}" 24 &>/dev/null
}
