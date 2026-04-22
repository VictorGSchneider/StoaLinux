#!/bin/bash
# Stoa Store — DEB / RPM converter wrappers (debtap + rpmextract).

_debtap_setup() {
    command -v debtap &>/dev/null && return 0
    local choice; choice=$(_rofi_list "debtap not installed" "  Install debtap (AUR)" "  Back")
    [[ "$choice" == *Install* ]] || return 1
    if ! _has_aur; then
        _notify "AUR helper needed to install debtap. Install yay or paru first."
        return 1
    fi
    local h; h=$(_helper)
    _run_in_term "$h -S --needed debtap && sudo debtap -u"
    command -v debtap &>/dev/null || { _notify "debtap installation failed"; return 1; }
    _notify "debtap installed and database updated"
}

_install_deb() {
    local path; path=$(_rofi_input "  Path to .deb file")
    [ -z "$path" ] && return
    path="${path/#\~/$HOME}"
    [ -f "$path" ]         || { _notify "File not found: $path"; return; }
    [[ "$path" == *.deb ]] || { _notify "File must be a .deb package"; return; }

    _notify "Converting .deb to Arch package..."
    _run_in_term "cd /tmp && debtap -Q '$path' && sudo pacman -U /tmp/*.pkg.tar* && rm -f /tmp/*.pkg.tar*"
    _apply_stoa_theme
    _notify "DEB package installed"
}

_install_rpm() {
    command -v rpmextract &>/dev/null || {
        _notify "rpmextract not found. Installing..."
        _run_in_term "sudo pacman -S --needed rpmextract"
    }
    local path; path=$(_rofi_input "  Path to .rpm file")
    [ -z "$path" ] && return
    path="${path/#\~/$HOME}"
    [ -f "$path" ]         || { _notify "File not found: $path"; return; }
    [[ "$path" == *.rpm ]] || { _notify "File must be a .rpm package"; return; }

    _notify "Extracting .rpm package..."
    _run_in_term "cd /tmp && mkdir -p stoa-rpm-extract && cd stoa-rpm-extract && rpmextract.sh '$path' && echo '── Contents extracted to /tmp/stoa-rpm-extract ──' && ls -la && echo && echo 'Install manually: sudo cp -r usr/ /usr/' && echo 'Or convert first: install debtap, then alien -d file.rpm, then debtap file.deb'"
    _apply_stoa_theme
    _notify "RPM package installed"
}

menu_deb_rpm() {
    _debtap_setup || return
    while true; do
        local choice; choice=$(_rofi_list "  DEB / RPM" \
            "  Install .deb package" \
            "  Install .rpm package" \
            "  Update debtap database" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *.deb*)   _install_deb ;;
            *.rpm*)   _install_rpm ;;
            *Update*) _run_in_term "sudo debtap -u"; _notify "debtap database updated" ;;
        esac
    done
}
