#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — App Store                                     ║
# ║  "Wealth is the slave of a wise man." — Seneca               ║
# ║                                                              ║
# ║  Pacman + AUR + Flatpak + Snap + AppImage search/install is  ║
# ║  bauh's job (a standalone GUI package manager); this store   ║
# ║  covers what bauh doesn't: DEB/RPM conversion, per-language  ║
# ║  PMs, Acer apps, and dev/system tooling — via yad dialogs.   ║
# ║  Auto-applies the Stoa theme after every install.            ║
# ║                                                              ║
# ║  Modules live in scripts/stoa-store/ — this file is only     ║
# ║  the dispatcher; each section is its own sourced module.     ║
# ╚══════════════════════════════════════════════════════════════╝

# Resolve the script directory *through* symlinks so the install-time symlink
# at ~/.local/bin/stoa-store still finds the bundled module files in-tree.
_STOA_STORE_SELF="$(readlink -f "${BASH_SOURCE[0]}")"
_STOA_STORE_LIB="$(dirname "$_STOA_STORE_SELF")/stoa-store"

if [ ! -d "$_STOA_STORE_LIB" ]; then
    echo "stoa-store: missing module directory: $_STOA_STORE_LIB" >&2
    exit 1
fi

# shellcheck source=stoa-store/core.sh
source "$_STOA_STORE_LIB/core.sh"
# shellcheck source=stoa-store/pacman.sh
source "$_STOA_STORE_LIB/pacman.sh"
# shellcheck source=stoa-store/browser.sh
source "$_STOA_STORE_LIB/browser.sh"
# shellcheck source=stoa-store/system.sh
source "$_STOA_STORE_LIB/system.sh"
# shellcheck source=stoa-store/flatpak.sh
source "$_STOA_STORE_LIB/flatpak.sh"
# shellcheck source=stoa-store/snap.sh
source "$_STOA_STORE_LIB/snap.sh"
# shellcheck source=stoa-store/appimage.sh
source "$_STOA_STORE_LIB/appimage.sh"
# shellcheck source=stoa-store/deb-rpm.sh
source "$_STOA_STORE_LIB/deb-rpm.sh"
# shellcheck source=stoa-store/lang-misc.sh
source "$_STOA_STORE_LIB/lang-misc.sh"
# shellcheck source=stoa-store/lang.sh
source "$_STOA_STORE_LIB/lang.sh"
# shellcheck source=stoa-store/acer.sh
source "$_STOA_STORE_LIB/acer.sh"

main() {
    while true; do
        local h; h=$(_helper)
        local aur_tag=""; _has_aur && aur_tag=" + AUR"
        local sources="${h}${aur_tag}"
        command -v flatpak &>/dev/null && sources+=" + Flatpak"
        command -v snap    &>/dev/null && sources+=" + Snap"

        local items=(
            "  Search & install"
            "  Package browser"
            "  Update all"
            "  Update system"
            "  Cleanup"
            "  System info"
            "─────────────────────"
            "  Flatpak manager"
            "  Snap manager"
            "  AppImage manager"
            "  DEB / RPM (convert)"
        )
        # Only surface the Acer submenu on Acer hardware (or when DAMX is
        # already installed), to keep the menu tight for other users.
        if _acer_is_laptop || _damx_installed; then
            items+=(
                "─────────────────────"
                "  Acer apps (DAMX)"
            )
        fi
        items+=(
            "─────────────────────"
            "  Developer tools"
            "  Setup auto-theme hook"
            "  Re-apply Stoa theme"
            "  Install AUR helper"
        )

        local choice
        choice=$(_yad_select "  Stoa Store (${sources})" "${items[@]}")
        [ -z "$choice" ] && exit 0

        case "$choice" in
            *"Search & install"*) _search_install ;;
            *"Package browser"*)  _installed ;;
            *"Update all"*)       _update_all ;;
            *Update*)             _update ;;
            *Cleanup*)            _cleanup ;;
            *info*)               _stats ;;
            *"Flatpak manager"*)  menu_flatpak ;;
            *"Snap manager"*)     menu_snap ;;
            *"AppImage manager"*) menu_appimage ;;
            *DEB*)                menu_deb_rpm ;;
            *"Acer apps"*)        menu_acer ;;
            *"Developer tools"*)  menu_developer ;;
            *auto-theme*)         _setup_hook ;;
            *Re-apply*)           _apply_stoa_theme; _notify "Stoa theme applied" ;;
            *"AUR helper"*)       _install_aur_helper ;;
        esac
    done
}

main "$@"
