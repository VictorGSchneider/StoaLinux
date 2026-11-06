#!/bin/bash
# Stoa Store — Flatpak manager.
#
# Search, install, and per-app browsing are bauh's job now (a standalone
# GUI package manager that already covers Flatpak alongside Pacman/AUR/
# Snap/AppImage) — see core.sh's _open_bauh. This module keeps Flathub
# bootstrap and the batch actions bauh doesn't expose as a single click.

_flatpak_setup() {
    if command -v flatpak &>/dev/null; then
        flatpak remotes 2>/dev/null | grep -q flathub || {
            _notify "Adding Flathub repository..."
            flatpak remote-add --user --if-not-exists flathub \
                https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null
        }
        return 0
    fi
    local choice; choice=$(_yad_select "Flatpak not installed" "  Install Flatpak" "  Back")
    [[ "$choice" == *Install* ]] || return 1
    _run_in_term "sudo pacman -S --needed flatpak && flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
    command -v flatpak &>/dev/null || { _notify "Flatpak installation failed"; return 1; }
    _notify "Flatpak installed! Flathub added."
}

menu_flatpak() {
    _flatpak_setup || return
    while true; do
        local app_count; app_count=$(flatpak list --app 2>/dev/null | wc -l)
        local choice; choice=$(_yad_select "  Flatpak ($app_count apps)" \
            "  Search & install (opens bauh)" \
            "  Update all" \
            "  Clean unused runtimes" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*) _open_bauh ;;
            *Update*) _run_in_term "flatpak update"; _notify "Flatpak updated" ;;
            *Clean*)  _run_in_term "flatpak uninstall --unused"; _notify "Cleanup done" ;;
        esac
    done
}
