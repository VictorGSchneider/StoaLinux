#!/bin/bash
# Stoa Store — AppImage manager.

_appimage_list() {
    [ ! -d "$APPIMAGE_DIR" ] && return
    find "$APPIMAGE_DIR" -maxdepth 1 -name "*.AppImage" -printf '%f\n' 2>/dev/null | sort
}

_appimage_run() {
    local apps; apps=$(_appimage_list)
    [ -z "$apps" ] && { _notify "No AppImages in ~/Applications"; return; }
    local choice; choice=$(echo "$apps" | _yad_list "  Run AppImage")
    [ -z "$choice" ] && return
    chmod +x "${APPIMAGE_DIR}/${choice}" 2>/dev/null
    "${APPIMAGE_DIR}/${choice}" & disown
    _notify "Launched: $choice"
}

_appimage_create_desktop() {
    local appimage="$1"
    local name="${appimage%.AppImage}"
    local desktop_dir="${HOME}/.local/share/applications"
    mkdir -p "$desktop_dir"
    cat > "${desktop_dir}/appimage-${name}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${name}
Exec=${APPIMAGE_DIR}/${appimage}
Icon=application-x-executable
Terminal=false
Categories=Utility;
Comment=AppImage: ${appimage}
EOF
    _notify "Shortcut created for $name"
}

_appimage_add_file() {
    local path; path=$(_yad_input "  Path to .AppImage file")
    [ -z "$path" ] && return
    path="${path/#\~/$HOME}"
    [ -f "$path" ] || { _notify "File not found: $path"; return; }
    [[ "$path" == *.AppImage ]] || { _notify "File must end in .AppImage"; return; }

    mkdir -p "$APPIMAGE_DIR"
    local basename; basename=$(basename "$path")
    cp "$path" "${APPIMAGE_DIR}/${basename}"
    chmod +x "${APPIMAGE_DIR}/${basename}"
    _notify "Added: $basename"
    _yad_confirm "Create desktop shortcut for $basename?" && _appimage_create_desktop "$basename"
}

_appimage_remove() {
    local apps; apps=$(_appimage_list)
    [ -z "$apps" ] && { _notify "No AppImages in ~/Applications"; return; }
    local choice; choice=$(echo "$apps" | _yad_list "  Remove AppImage")
    [ -z "$choice" ] && return
    _yad_confirm "Remove $choice?" || return
    rm -f "${APPIMAGE_DIR}/${choice}"
    local name="${choice%.AppImage}"
    rm -f "${HOME}/.local/share/applications/appimage-${name}.desktop" 2>/dev/null
    _notify "Removed: $choice"
}

menu_appimage() {
    while true; do
        mkdir -p "$APPIMAGE_DIR"
        local count; count=$(_appimage_list | wc -l)
        local choice; choice=$(_yad_select "  AppImage ($count apps)" \
            "  Run AppImage" \
            "  Add from file" \
            "  Create desktop shortcut" \
            "  Remove AppImage" \
            "  Open ~/Applications" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return
        case "$choice" in
            *Run*)           _appimage_run ;;
            *"Add from"*)    _appimage_add_file ;;
            *"desktop shortcut"*)
                local apps; apps=$(_appimage_list)
                [ -z "$apps" ] && { _notify "No AppImages"; continue; }
                local sel; sel=$(echo "$apps" | _yad_list "  Create shortcut for")
                [ -n "$sel" ] && _appimage_create_desktop "$sel" ;;
            *Remove*)        _appimage_remove ;;
            *Open*)          thunar "$APPIMAGE_DIR" & disown ;;
        esac
    done
}
