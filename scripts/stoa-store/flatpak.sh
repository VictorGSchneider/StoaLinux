#!/bin/bash
# Stoa Store — Flatpak manager.

_flatpak_setup() {
    if command -v flatpak &>/dev/null; then
        flatpak remotes 2>/dev/null | grep -q flathub || {
            _notify "Adding Flathub repository..."
            flatpak remote-add --user --if-not-exists flathub \
                https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null
        }
        return 0
    fi
    local choice; choice=$(_rofi_list "Flatpak not installed" "  Install Flatpak" "  Back")
    [[ "$choice" == *Install* ]] || return 1
    _run_in_term "sudo pacman -S --needed flatpak && flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
    command -v flatpak &>/dev/null || { _notify "Flatpak installation failed"; return 1; }
    _notify "Flatpak installed! Flathub added."
}

_flatpak_search() {
    local query; query=$(_rofi_input "  Search Flathub")
    [ -z "$query" ] && return
    _notify "Searching Flathub for '$query'..."
    local lines; lines=$(_search_flatpak_results "$query")
    [ -z "$lines" ] && { _notify "Nothing found on Flathub"; return; }

    # Strip the leading "[flatpak] " tag that _search_flatpak_results adds.
    local display; display=$(echo "$lines" | sed 's/^\[flatpak\] //')
    local choice; choice=$(echo "$display" | head -80 | _rofi "  Flathub ($query)")
    [ -z "$choice" ] && return
    _handle_flatpak_selection "$(echo "$choice" | awk '{print $2}')"
}

_flatpak_installed() {
    local apps; apps=$(flatpak list --app --columns=name,application 2>/dev/null)
    [ -z "$apps" ] && { _notify "No Flatpak apps installed"; return; }
    local lines=()
    while IFS=$'\t' read -r name app_id; do
        [ -z "$name" ] && continue
        lines+=("${name}  ${app_id}")
    done <<< "$apps"
    local choice; choice=$(printf '%s\n' "${lines[@]}" | _rofi "  Flatpak apps")
    [ -z "$choice" ] && return
    _handle_flatpak_selection "$(echo "$choice" | awk '{print $NF}')"
}

menu_flatpak() {
    _flatpak_setup || return
    while true; do
        local app_count; app_count=$(flatpak list --app 2>/dev/null | wc -l)
        local choice; choice=$(_rofi_list "  Flatpak ($app_count apps)" \
            "  Search & install (Flathub)" \
            "  Installed apps" \
            "  Update all" \
            "  Clean unused runtimes" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Search*)    _flatpak_search ;;
            *Installed*) _flatpak_installed ;;
            *Update*)    _run_in_term "flatpak update"; _notify "Flatpak updated" ;;
            *Clean*)     _run_in_term "flatpak uninstall --unused"; _notify "Cleanup done" ;;
        esac
    done
}
