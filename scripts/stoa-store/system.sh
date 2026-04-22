#!/bin/bash
# Stoa Store — system update/cleanup/stats + pacman theme hook + AUR helper install.

_update_all() {
    local h; h=$(_helper)
    local summary="System"
    [ "$h" != "pacman" ] && summary="System + AUR ($h)"
    command -v flatpak &>/dev/null && summary+=" + Flatpak"
    command -v snap    &>/dev/null && summary+=" + Snap"
    _confirm "Update all: ${summary}?" || return

    local script
    [ "$h" = "pacman" ] \
        && script="echo '── System (pacman) ──'; sudo pacman -Syu" \
        || script="echo '── System + AUR (${h}) ──'; ${h} -Syu"
    command -v flatpak &>/dev/null && script+="; echo; echo '── Flatpak ──'; flatpak update"
    command -v snap    &>/dev/null && script+="; echo; echo '── Snap ──'; sudo snap refresh"

    _notify "Updating ${summary}..."
    _run_in_term "$script"
    _apply_stoa_theme
    _notify "Update all complete"
}

_update() {
    local h; h=$(_helper)
    local items=(
        "  Update all (pacman + AUR + Flatpak + Snap)"
        "  Full system update (pacman + AUR)"
        "  Check for updates"
        "  Update mirrors (reflector)"
    )
    command -v flatpak &>/dev/null && items+=("  Update Flatpak apps")
    command -v snap    &>/dev/null && items+=("  Update Snap packages")

    local action; action=$(_rofi_list "  Update" "${items[@]}")
    [ -z "$action" ] && return

    case "$action" in
        *"Update all"*) _update_all ;;
        *Full*)
            [ "$h" = "pacman" ] && _run_in_term "sudo pacman -Syu" || _run_in_term "$h -Syu"
            _apply_stoa_theme; _notify "System updated" ;;
        *Check*)
            _notify "Checking..."
            local updates
            [ "$h" = "pacman" ] && updates=$(checkupdates 2>/dev/null) || updates=$($h -Qu 2>/dev/null)
            if [ -z "$updates" ]; then
                _notify "System is up to date"
            else
                local c; c=$(echo "$updates" | wc -l)
                echo "$updates" | _rofi "  $c updates available"
            fi ;;
        *mirrors*)
            _confirm "Update mirrorlist with reflector?" || return
            _run_in_term "sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syy"
            _notify "Mirrors updated" ;;
        *Flatpak*) _run_in_term "flatpak update";   _notify "Flatpak apps updated" ;;
        *Snap*)    _run_in_term "sudo snap refresh"; _notify "Snap packages updated" ;;
    esac
}

_cleanup() {
    local items=(
        "  Remove orphans"
        "  Clean package cache"
        "  Clean all cached packages"
    )
    command -v flatpak &>/dev/null && items+=("  Clean unused Flatpak runtimes")

    local action; action=$(_rofi_list "  Cleanup" "${items[@]}")
    [ -z "$action" ] && return

    case "$action" in
        *orphans*)
            local orphans; orphans=$(pacman -Qdtq 2>/dev/null)
            [ -z "$orphans" ] && { _notify "No orphans"; return; }
            local c; c=$(echo "$orphans" | wc -l)
            echo "$orphans" | _rofi "  $c orphans (read-only)"
            _confirm "Remove $c orphans?" \
                && _run_in_term "sudo pacman -Rns \$(pacman -Qdtq)" \
                && _notify "Orphans removed" ;;
        *"Clean package"*)
            _confirm "Clean old cached packages? (keep last 3)" || return
            _run_in_term "sudo paccache -r"; _notify "Cache cleaned" ;;
        *"Clean all"*)
            _confirm "Remove ALL cached packages?" || return
            _run_in_term "sudo pacman -Scc"; _notify "All cache cleaned" ;;
        *Flatpak*)
            _run_in_term "flatpak uninstall --unused"
            _notify "Unused Flatpak runtimes removed" ;;
    esac
}

_stats() {
    local total explicit foreign orphans cache_size
    total=$(pacman -Q    2>/dev/null | wc -l)
    explicit=$(pacman -Qe 2>/dev/null | wc -l)
    foreign=$(pacman -Qm 2>/dev/null | wc -l)
    orphans=$(pacman -Qdtq 2>/dev/null | wc -l)
    cache_size=$(du -sh /var/cache/pacman/pkg/ 2>/dev/null | awk '{print $1}')

    local h; h=$(_helper)
    local hook_status="not installed"
    [ -f /etc/pacman.d/hooks/stoa-theme.hook ] && hook_status="active"

    local lines=(
        "Pacman packages:      $total"
        "Explicitly installed: $explicit"
        "AUR / foreign:        $foreign"
        "Orphans:              $orphans"
        "Cache size:           $cache_size"
        "AUR helper:           $h"
        "Auto-theme hook:      $hook_status"
    )
    if command -v flatpak &>/dev/null; then
        local fp; fp=$(flatpak list --app 2>/dev/null | wc -l)
        lines+=("Flatpak apps:         $fp")
    fi
    if command -v snap &>/dev/null; then
        local sn; sn=$(snap list 2>/dev/null | tail -n +2 | wc -l)
        lines+=("Snap packages:        $sn")
    fi
    local ai=0
    [ -d "$APPIMAGE_DIR" ] && ai=$(find "$APPIMAGE_DIR" -maxdepth 1 -name "*.AppImage" 2>/dev/null | wc -l)
    lines+=("AppImages:            $ai")

    printf '%s\n' "${lines[@]}" | _rofi "  System info"
}

_setup_hook() {
    local hook="/etc/pacman.d/hooks/stoa-theme.hook"
    local script="/usr/local/bin/stoa-theme-enforce"
    [ -f "$hook" ] && { _notify "Auto-theme hook already active"; return; }
    _confirm "Install auto-theme pacman hook? (sudo)" || return

    local stoa_dir; stoa_dir="$(dirname "$(readlink -f "$0")")/.."
    if [ -f "$stoa_dir/theme/pacman-hooks/stoa-theme-enforce" ]; then
        sudo mkdir -p /etc/pacman.d/hooks
        sudo cp "$stoa_dir/theme/pacman-hooks/stoa-theme-enforce" "$script"
        sudo chmod +x "$script"
        sudo cp "$stoa_dir/theme/pacman-hooks/stoa-theme.hook" "$hook"
    else
        sudo mkdir -p /etc/pacman.d/hooks
        sudo tee "$script" > /dev/null <<'ENFORCE'
#!/bin/bash
U="${SUDO_USER:-$USER}"
H=$(getent passwd "$U" | cut -d: -f6)
[ -z "$H" ] && exit 0
g="$H/.config/gtk-3.0/settings.ini"; [ ! -f "$g" ] && exit 0
t=$(grep "^gtk-theme-name" "$g"|sed 's/^[^=]*=\s*//')
i=$(grep "^gtk-icon-theme-name" "$g"|sed 's/^[^=]*=\s*//')
command -v gsettings &>/dev/null && su - "$U" -c "
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/\$(id -u)/bus
gsettings set org.gnome.desktop.interface gtk-theme '${t:-Adwaita-dark}' 2>/dev/null
gsettings set org.gnome.desktop.interface icon-theme '${i:-Papirus-Dark}' 2>/dev/null
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null
" 2>/dev/null
ENFORCE
        sudo chmod +x "$script"
        sudo tee "$hook" > /dev/null <<'HOOK'
[Trigger]
Operation = Install
Operation = Upgrade
Type = Package
Target = *
[Action]
Description = Applying Stoa theme...
When = PostTransaction
Exec = /usr/local/bin/stoa-theme-enforce
HOOK
    fi
    _notify "Auto-theme hook installed!"
}

_install_aur_helper() {
    if _has_aur; then _notify "AUR helper already available: $(_helper)"; return; fi
    local choice; choice=$(_rofi_list "  Install AUR helper" \
        "yay   — Go-based, most popular" \
        "paru  — Rust-based, fast")
    [ -z "$choice" ] && return
    local pkg
    [[ "$choice" == yay*  ]] && pkg="yay"
    [[ "$choice" == paru* ]] && pkg="paru"
    _run_in_term "sudo pacman -S --needed git base-devel && cd /tmp && git clone https://aur.archlinux.org/${pkg}-bin.git && cd ${pkg}-bin && makepkg -si --noconfirm"
    command -v "$pkg" &>/dev/null && _notify "$pkg installed!"
}
