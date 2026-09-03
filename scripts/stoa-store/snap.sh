#!/bin/bash
# Stoa Store — Snap manager.
#
# Search, install, and per-package browsing are bauh's job now — see
# core.sh's _open_bauh. This module keeps snapd bootstrap and the batch
# action bauh doesn't expose as a single click.

_snap_setup() {
    command -v snap &>/dev/null && return 0
    local choice; choice=$(_yad_select "Snap not installed" "  Install Snap (snapd from AUR)" "  Back")
    [[ "$choice" == *Install* ]] || return 1
    if ! _has_aur; then
        _notify "AUR helper needed to install snapd. Install yay or paru first."
        return 1
    fi
    local h; h=$(_helper)
    _run_in_term "$h -S --needed snapd && sudo systemctl enable --now snapd.socket && sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null"
    command -v snap &>/dev/null || { _notify "Snap installation failed. Reboot may be required."; return 1; }
    _notify "Snap installed! snapd.socket enabled."
}

menu_snap() {
    _snap_setup || return
    while true; do
        local pkg_count; pkg_count=$(snap list 2>/dev/null | tail -n +2 | wc -l)
        local choice; choice=$(_yad_select "  Snap ($pkg_count pkgs)" \
            "  Search & install (opens bauh)" \
            "  Update all" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*) _open_bauh ;;
            *Update*) _run_in_term "sudo snap refresh"; _notify "Snap updated" ;;
        esac
    done
}
