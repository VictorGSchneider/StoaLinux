#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — App Store                                     ║
# ║  "Wealth is the slave of a wise man." — Seneca               ║
# ║                                                              ║
# ║  Rofi-driven package manager: Pacman + AUR + Flatpak + Snap  ║
# ║  + AppImage + DEB/RPM + per-language PMs.                    ║
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

main() {
    while true; do
        local h; h=$(_helper)
        local aur_tag=""; _has_aur && aur_tag=" + AUR"
        local sources="${h}${aur_tag}"
        command -v flatpak &>/dev/null && sources+=" + Flatpak"
        command -v snap    &>/dev/null && sources+=" + Snap"

        local choice
        choice=$(_rofi_list "  Stoa Store (${sources})" \
            "  Search & install" \
            "  Package browser" \
            "  Update all" \
            "  Update system" \
            "  Cleanup" \
            "  System info" \
            "─────────────────────" \
            "  Flatpak manager" \
            "  Snap manager" \
            "  AppImage manager" \
            "  DEB / RPM (convert)" \
            "─────────────────────" \
            "  Developer tools" \
            "  Setup auto-theme hook" \
            "  Re-apply Stoa theme" \
            "  Install AUR helper")
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
            *"Developer tools"*)  menu_developer ;;
            *auto-theme*)         _setup_hook ;;
            *Re-apply*)           _apply_stoa_theme; _notify "Stoa theme applied" ;;
            *"AUR helper"*)       _install_aur_helper ;;
        esac
    done
}

main "$@"
