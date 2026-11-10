#!/bin/bash
# Stoa Store — DEB / RPM converter wrappers (debtap + rpmextract).

_debtap_setup() {
    command -v debtap &>/dev/null && return 0
    local choice; choice=$(_yad_select "debtap not installed" "  Install debtap (AUR)" "  Back")
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
    local path; path=$(_yad_input "  Path to .deb file")
    [ -z "$path" ] && return
    path="${path/#\~/$HOME}"
    [ -f "$path" ]         || { _notify "File not found: $path"; return; }
    [[ "$path" == *.deb ]] || { _notify "File must be a .deb package"; return; }

    _notify "Converting .deb to Arch package..."
    # A private work dir, and the path quoted for the shell it is pasted into: a
    # fixed /tmp glob installs whatever else is lying there, and a quote in the
    # file name ended the single-quoted string early.
    local work qpath qwork
    work=$(mktemp -d) || { _notify "Could not create a work directory"; return 1; }
    printf -v qpath '%q' "$path"; printf -v qwork '%q' "$work"
    _run_in_term "cd $qwork && debtap -Q $qpath && sudo pacman -U ./*.pkg.tar*; cd / && rm -rf $qwork"
    _apply_stoa_theme
    _notify "DEB package installed"
}

_install_rpm() {
    command -v rpmextract &>/dev/null || {
        _notify "rpmextract not found. Installing..."
        _run_in_term "sudo pacman -S --needed rpmextract"
    }
    local path; path=$(_yad_input "  Path to .rpm file")
    [ -z "$path" ] && return
    path="${path/#\~/$HOME}"
    [ -f "$path" ]         || { _notify "File not found: $path"; return; }
    [[ "$path" == *.rpm ]] || { _notify "File must be a .rpm package"; return; }

    _notify "Extracting .rpm package..."
    local rwork qpath qrwork
    rwork=$(mktemp -d) || { _notify "Could not create a work directory"; return 1; }
    printf -v qpath '%q' "$path"; printf -v qrwork '%q' "$rwork"
    _run_in_term "cd $qrwork && rpmextract.sh $qpath && echo \"── Contents extracted to $qrwork ──\" && ls -la && echo && echo 'Install manually: sudo cp -r usr/ /usr/' && echo 'Or convert first: install debtap, then alien -d file.rpm, then debtap file.deb'"
    _apply_stoa_theme
    _notify "RPM package installed"
}

menu_deb_rpm() {
    _debtap_setup || return
    while true; do
        local choice; choice=$(_yad_select "  DEB / RPM" \
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
