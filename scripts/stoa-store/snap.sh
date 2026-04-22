#!/bin/bash
# Stoa Store — Snap manager.

_snap_setup() {
    command -v snap &>/dev/null && return 0
    local choice; choice=$(_rofi_list "Snap not installed" "  Install Snap (snapd from AUR)" "  Back")
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

_snap_search() {
    local query; query=$(_rofi_input "  Search Snap Store")
    [ -z "$query" ] && return
    _notify "Searching Snap Store for '$query'..."
    local results; results=$(snap find "$query" 2>/dev/null | tail -n +2)
    [ -z "$results" ] && { _notify "Nothing found on Snap Store"; return; }

    local lines=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name ver publisher summary
        name=$(echo "$line" | awk '{print $1}')
        ver=$(echo "$line" | awk '{print $2}')
        publisher=$(echo "$line" | awk '{print $3}')
        summary=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
        lines+=("${name}  ${ver}  ${publisher}  ${summary:0:40}")
    done <<< "$results"
    [ ${#lines[@]} -eq 0 ] && { _notify "Nothing found"; return; }

    local choice; choice=$(printf '%s\n' "${lines[@]}" | head -80 | _rofi "  Snap ($query)")
    [ -z "$choice" ] && return
    _handle_snap_selection "$(echo "$choice" | awk '{print $1}')"
}

_snap_installed() {
    local apps; apps=$(snap list 2>/dev/null | tail -n +2)
    [ -z "$apps" ] && { _notify "No Snap packages installed"; return; }
    local lines=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name ver
        name=$(echo "$line" | awk '{print $1}')
        ver=$(echo "$line" | awk '{print $2}')
        lines+=("${name}  ${ver}")
    done <<< "$apps"
    local choice; choice=$(printf '%s\n' "${lines[@]}" | _rofi "  Snap packages")
    [ -z "$choice" ] && return
    _handle_snap_selection "$(echo "$choice" | awk '{print $1}')"
}

menu_snap() {
    _snap_setup || return
    while true; do
        local pkg_count; pkg_count=$(snap list 2>/dev/null | tail -n +2 | wc -l)
        local choice; choice=$(_rofi_list "  Snap ($pkg_count pkgs)" \
            "  Search & install (Snap Store)" \
            "  Installed packages" \
            "  Update all" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*)    _snap_search ;;
            *Installed*) _snap_installed ;;
            *Update*)    _run_in_term "sudo snap refresh"; _notify "Snap updated" ;;
        esac
    done
}
