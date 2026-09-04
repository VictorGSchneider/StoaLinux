#!/bin/bash
# Stoa Store — core helpers, yad wrappers, theme reapplication.

APPIMAGE_DIR="${HOME}/Applications"

_notify() { notify-send -t 2500 "Stoa Store" "$1" 2>/dev/null; }

# Selection list built from function arguments (each arg = one row).
_yad_select() {
    local prompt="$1"
    shift
    printf '%s\n' "$@" \
        | yad --list --title="$prompt" --column="Option" --no-headers \
              --width=520 --height=440 --separator=''
}

# Selection list built from stdin (one row per line) — replaces the old
# `command | _yad_list "prompt"` idiom used throughout the store modules.
_yad_list() {
    local prompt="$1"
    yad --list --title="$prompt" --column="Option" --no-headers \
        --width=560 --height=460 --separator=''
}

_yad_input() {
    local prompt="$1"
    yad --entry --title="$prompt" --width=380
}

_yad_confirm() {
    local msg="$1"
    yad --question --title="Stoa Store" --text="$msg"
}

# Read-only scrollable text viewer for long, non-actionable output
# (package info dumps, changelogs, status reports).
_yad_info() {
    local prompt="$1"
    yad --text-info --title="$prompt" --fontname="monospace 11" \
        --width=560 --height=420 --button="Close:0"
}

_helper() {
    command -v yay  &>/dev/null && { echo yay;  return; }
    command -v paru &>/dev/null && { echo paru; return; }
    echo pacman
}
_has_aur()       { [[ "$(_helper)" != "pacman" ]]; }
_is_installed()  { pacman -Qi "$1" &>/dev/null; }

# Quick read-only pacman info for a single package. Used by the modules
# that still need to show a package's status inline (e.g. the developer
# base-packages checklist) without pulling back in a full search/install
# UI — that job now belongs to bauh (see pacman.sh).
_pkg_quick_info() {
    local pkg="$1"
    if _is_installed "$pkg"; then
        pacman -Qi "$pkg" 2>/dev/null | _yad_info "  $pkg"
    else
        { pacman -Si "$pkg" 2>/dev/null
          echo
          echo "Not installed — use the Package Manager (bauh) to install it."
        } | _yad_info "  $pkg"
    fi
}

# Pacman + AUR + Flatpak + Snap + AppImage are all managed through bauh, a
# unified package-manager GUI (added as a dependency in setup/*-install.sh).
# Search, install, removal and updates for those sources go through it
# instead of the custom rofi menus this store used to carry.
#
# Launched through stoa-bauh (a thin Python wrapper) instead of the bare
# `bauh` binary: the AUR package still calls pkgutil.find_loader(), which
# was removed from the stdlib in Python 3.12+, so bare `bauh` crashes on
# startup on any current Arch install. stoa-bauh patches that back in
# before importing bauh's own code — see scripts/stoa-bauh.py.
#
# Launched detached with stdout/stderr captured to a log file instead of a
# bare `& disown`: when this fires from a keybind or the Stoa Store menu
# (no terminal attached), a crash on launch would otherwise be completely
# silent — the window just never appears, with no way to tell why.
_open_bauh() {
    local shim="${HOME}/.local/bin/stoa-bauh"
    local cmd=""
    if [ -x "$shim" ]; then
        cmd="$shim"
    elif command -v bauh &>/dev/null; then
        cmd="bauh"
    else
        _notify "bauh not found — install it (AUR: bauh) to manage packages"
        return 1
    fi

    local log="${XDG_CACHE_HOME:-$HOME/.cache}/stoa/bauh.log"
    mkdir -p "$(dirname "$log")"
    (
        "$cmd" >"$log" 2>&1
        status=$?
        if [ "$status" -ne 0 ]; then
            notify-send -u critical -t 8000 "Stoa Store" \
                "bauh exited with an error (code ${status}) — see ${log}" 2>/dev/null
        fi
    ) &
    disown
}

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
    command -v hyprctl &>/dev/null && \
        hyprctl setcursor "${c:-Colloid-cursors}" 24 &>/dev/null
}
