#!/bin/bash
# Stoa Store — Acer apps (DAMX + DAM-FC) install/update/uninstall/status.
#
# Div Acer Manager Max (DAMX)   — Nitro/Predator fan, profiles, battery, RGB.
# DAM Fan Controls (DAM-FC)     — simpler fan-only tool (legacy, still useful).
#
# Both projects ship shell installers with interactive menus; we drive them
# in unattended mode by piping the expected choice.

DAMX_REPO="PXDiv/Div-Acer-Manager-Max"
DAMX_REMOTE_SETUP="https://raw.githubusercontent.com/${DAMX_REPO}/refs/heads/main/scripts/remoteSetup.sh"
DAMX_SERVICE="damx-daemon.service"
DAMX_INSTALL_DIR="/opt/damx"

DAMFC_REPO="PXDiv/Div-Acer-Manager-Fan-Controls"

_acer_is_laptop() {
    local vendor=""
    [ -r /sys/class/dmi/id/sys_vendor ] && vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
    [[ "$vendor" == *Acer* ]]
}

_damx_installed() {
    [ -d "$DAMX_INSTALL_DIR" ] || [ -f "/etc/systemd/system/${DAMX_SERVICE}" ]
}

_damx_version() {
    # Best-effort: read from the release tarball name left behind by the
    # installer, or fall back to the service file.
    local v
    v=$(ls "$DAMX_INSTALL_DIR"/DAMX-*.tar.xz 2>/dev/null | head -n1 | sed -E 's/.*DAMX-([^/]+)\.tar\.xz/\1/')
    [ -n "$v" ] && { echo "$v"; return; }
    echo "unknown"
}

_damx_run_remote_setup() {
    # $1 = menu choice for remoteSetup.sh (1=install, 3=uninstall, 4=update).
    local choice="$1"
    if ! command -v curl &>/dev/null; then
        _notify "curl required for DAMX setup"
        return 1
    fi
    local tmp
    tmp=$(mktemp -d -t stoa-damx-XXXXXX)
    if ! curl -fsSL "$DAMX_REMOTE_SETUP" -o "$tmp/setup.sh"; then
        _notify "Failed to download DAMX installer"
        rm -rf "$tmp"
        return 1
    fi
    chmod +x "$tmp/setup.sh"
    # remoteSetup.sh runs in a work dir; cd in so DAMX-GUI/DAMX-Daemon land
    # beside the tarball and are reusable for later updates.
    _run_in_term "cd '$tmp' && printf '%s\nq\n' '$choice' | sudo bash ./setup.sh; echo; echo 'Cleaning up temporary files...'; rm -rf '$tmp'"
}

_install_damx() {
    if _damx_installed; then
        _confirm "DAMX already installed. Reinstall / update?" || return
        _damx_run_remote_setup 4
    else
        _confirm "Install Div Acer Manager Max (DAMX)? Requires sudo." || return
        _damx_run_remote_setup 1
    fi
    if systemctl is-active --quiet "$DAMX_SERVICE" 2>/dev/null; then
        _notify "DAMX installed and running"
    else
        _notify "DAMX install finished — check service status"
    fi
}

_update_damx() {
    if ! _damx_installed; then
        _notify "DAMX not installed"
        return
    fi
    _confirm "Update DAMX to the latest release? (reinstall, sudo)" || return
    _damx_run_remote_setup 4
    _notify "DAMX updated"
}

_uninstall_damx() {
    if ! _damx_installed; then
        _notify "DAMX not installed"
        return
    fi
    _confirm "Uninstall DAMX (removes daemon and GUI)?" || return
    _damx_run_remote_setup 3
    _notify "DAMX uninstalled"
}

_status_damx() {
    if ! _damx_installed; then
        echo "DAMX is not installed." | _rofi "  DAMX status"
        return
    fi
    local lines=(
        "Install dir:   $DAMX_INSTALL_DIR"
        "Version:       $(_damx_version)"
        "Service:       $DAMX_SERVICE"
    )
    if systemctl is-enabled --quiet "$DAMX_SERVICE" 2>/dev/null; then
        lines+=("Enabled:       yes")
    else
        lines+=("Enabled:       no")
    fi
    if systemctl is-active --quiet "$DAMX_SERVICE" 2>/dev/null; then
        lines+=("Active:        yes")
    else
        lines+=("Active:        no")
    fi
    [ -x "$DAMX_INSTALL_DIR/gui/DivAcerManagerMax" ] \
        && lines+=("GUI binary:    present") \
        || lines+=("GUI binary:    missing")
    printf '%s\n' "${lines[@]}" | _rofi "  DAMX status"
}

_install_damfc() {
    # DAM-FC ships release tarballs with a SetupDrivers.sh installer. We
    # download the latest release asset and hand it to a terminal for the
    # user to pick menu option 1.
    _confirm "Install DAM Fan Controls (DAM-FC)? Requires sudo." || return
    if ! command -v curl &>/dev/null; then
        _notify "curl required for DAM-FC install"
        return 1
    fi
    local tmp api_url release_json tar_url file_name
    tmp=$(mktemp -d -t stoa-damfc-XXXXXX)
    api_url="https://api.github.com/repos/${DAMFC_REPO}/releases/latest"
    release_json=$(curl -fsSL "$api_url" 2>/dev/null)
    tar_url=$(echo "$release_json" | grep 'browser_download_url' | grep -Ei '\.(tar\.(gz|xz)|zip)"' | head -n1 | cut -d '"' -f4)
    if [ -z "$tar_url" ]; then
        _notify "No DAM-FC release asset found"
        rm -rf "$tmp"
        return 1
    fi
    file_name=$(basename "$tar_url")
    if ! curl -fsSL --retry 3 -o "$tmp/$file_name" "$tar_url"; then
        _notify "Failed to download DAM-FC"
        rm -rf "$tmp"
        return 1
    fi
    _run_in_term "cd '$tmp' && case '$file_name' in *.zip) unzip -q '$file_name' ;; *.tar.gz) tar -xzf '$file_name' ;; *.tar.xz) tar -xJf '$file_name' ;; esac; setup_sh=\$(find . -maxdepth 3 -iname 'SetupDrivers.sh' | head -n1); if [ -z \"\$setup_sh\" ]; then echo 'SetupDrivers.sh not found in release archive'; else chmod +x \"\$setup_sh\"; printf '1\n' | sudo bash \"\$setup_sh\"; fi; echo; echo 'Cleaning up...'; rm -rf '$tmp'"
    _notify "DAM-FC install finished"
}

menu_acer() {
    local items=()
    if _damx_installed; then
        items+=(
            "  Update DAMX"
            "  Reinstall DAMX"
            "  DAMX status"
            "  Uninstall DAMX"
        )
    else
        items+=("  Install DAMX (recommended)")
    fi
    items+=(
        "─────────────────────"
        "  Install DAM Fan Controls (legacy)"
    )

    local choice
    choice=$(_rofi_list "  Acer apps" "${items[@]}")
    [ -z "$choice" ] && return

    case "$choice" in
        *"Install DAMX"*)            _install_damx ;;
        *"Reinstall DAMX"*|*"Update DAMX"*) _update_damx ;;
        *"DAMX status"*)             _status_damx ;;
        *"Uninstall DAMX"*)          _uninstall_damx ;;
        *"DAM Fan Controls"*)        _install_damfc ;;
    esac
}
