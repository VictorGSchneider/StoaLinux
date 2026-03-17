#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — App Store                                     ║
# ║  "Wealth is the slave of a wise man." — Seneca               ║
# ║                                                              ║
# ║  Full package manager via rofi.                              ║
# ║  Pacman + AUR + Flatpak + Snap + AppImage + DEB/RPM.        ║
# ║  Auto-aplica tema Stoa em tudo que for instalado.           ║
# ╚══════════════════════════════════════════════════════════════╝

ROFI="rofi -dmenu -i -config ${HOME}/.config/rofi/config.rasi"
APPIMAGE_DIR="${HOME}/Applications"

# ── Helpers ──────────────────────────────────────────────────

_notify() { dunstify -t 2500 "Stoa Store" "$1" 2>/dev/null; }

_rofi() {
    $ROFI -p "$1"
}

_rofi_list() {
    local prompt="$1"; shift
    printf '%s\n' "$@" | $ROFI -p "$prompt"
}

_confirm() {
    local r
    r=$(_rofi_list "$1" "  Yes" "  No")
    [[ "$r" == *Yes* ]]
}

_helper() {
    command -v yay  &>/dev/null && echo yay  && return
    command -v paru &>/dev/null && echo paru && return
    echo pacman
}

_has_aur() { [[ "$(_helper)" != "pacman" ]]; }

_is_installed() { pacman -Qi "$1" &>/dev/null; }

_run_in_term() {
    alacritty -e bash -c "$1; echo; echo 'Pressione Enter...'; read"
}

_apply_stoa_theme() {
    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    [ ! -f "$gtk3" ] && return
    local t i c f
    t=$(grep "^gtk-theme-name"       "$gtk3" | cut -d= -f2)
    i=$(grep "^gtk-icon-theme-name"  "$gtk3" | cut -d= -f2)
    c=$(grep "^gtk-cursor-theme-name" "$gtk3" | cut -d= -f2)
    f=$(grep "^gtk-font-name"        "$gtk3" | cut -d= -f2)
    if command -v gsettings &>/dev/null; then
        gsettings set org.gnome.desktop.interface gtk-theme    "${t:-Adwaita-dark}"    2>/dev/null
        gsettings set org.gnome.desktop.interface icon-theme   "${i:-Colloid-dark}"    2>/dev/null
        gsettings set org.gnome.desktop.interface cursor-theme "${c:-Colloid-cursors}" 2>/dev/null
        gsettings set org.gnome.desktop.interface font-name    "${f:-EB Garamond 11}" 2>/dev/null
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"           2>/dev/null
    fi
    [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null && \
        hyprctl setcursor "${c:-Colloid-cursors}" 24 &>/dev/null
}

# ── Search (Pacman + AUR) ─────────────────────────────────────

_search_install() {
    local query
    query=$(echo "" | _rofi "  Search (install)")
    [ -z "$query" ] && return

    _notify "Searching '$query'..."

    local h; h=$(_helper)
    local results

    if [ "$h" = "pacman" ]; then
        results=$(pacman -Ss "$query" 2>/dev/null)
    else
        results=$($h -Ss "$query" 2>/dev/null)
    fi

    [ -z "$results" ] && { _notify "Nothing found"; return; }

    # Parse: "repo/name version (group)\n    description"
    local lines=()
    local pkgs=()
    while IFS= read -r line1; do
        IFS= read -r line2 || true
        local repo_pkg ver desc
        repo_pkg=$(echo "$line1" | awk '{print $1}')
        ver=$(echo "$line1" | awk '{print $2}')
        desc=$(echo "$line2" | sed 's/^[[:space:]]*//')
        local pkg_name="${repo_pkg#*/}"
        local repo="${repo_pkg%/*}"

        local status=""
        _is_installed "$pkg_name" && status="  [installed]"

        local tag=""
        [[ "$repo" == "aur" ]] && tag="AUR"
        [ -n "$tag" ] && tag="($tag) "

        lines+=("${pkg_name}  ${tag}${ver}  ${desc:0:50}${status}")
        pkgs+=("$pkg_name")
    done <<< "$results"

    [ ${#lines[@]} -eq 0 ] && { _notify "Nothing found"; return; }

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | head -100 | _rofi "  Results ($query)")
    [ -z "$choice" ] && return

    local sel_pkg
    sel_pkg=$(echo "$choice" | awk '{print $1}')

    if _is_installed "$sel_pkg"; then
        local action
        action=$(_rofi_list "$sel_pkg [installed]" \
            "  Reinstall" \
            "  Remove" \
            "  Package info")
        case "$action" in
            *Reinstall*)
                _run_in_term "sudo pacman -S $sel_pkg"
                _apply_stoa_theme
                ;;
            *Remove*)
                _confirm "Remove $sel_pkg?" && _run_in_term "sudo pacman -Rns $sel_pkg"
                ;;
            *info*)
                pacman -Qi "$sel_pkg" 2>/dev/null | _rofi "  $sel_pkg"
                ;;
        esac
    else
        _confirm "Install $sel_pkg?" || return
        if [ "$h" = "pacman" ]; then
            _run_in_term "sudo pacman -S --needed $sel_pkg"
        else
            _run_in_term "$h -S --needed $sel_pkg"
        fi
        _is_installed "$sel_pkg" && _apply_stoa_theme && _notify "$sel_pkg installed"
    fi
}

# ── Installed packages ───────────────────────────────────────

_installed() {
    local filter
    filter=$(_rofi_list "  Filter" \
        "  All explicitly installed" \
        "  AUR / foreign only" \
        "  Search installed")
    [ -z "$filter" ] && return

    local pkgs
    case "$filter" in
        *All*)     pkgs=$(pacman -Qe 2>/dev/null) ;;
        *AUR*)     pkgs=$(pacman -Qm 2>/dev/null) ;;
        *Search*)
            local q
            q=$(echo "" | _rofi "  Search installed")
            [ -z "$q" ] && return
            pkgs=$(pacman -Qe 2>/dev/null | grep -i "$q")
            ;;
    esac

    [ -z "$pkgs" ] && { _notify "No packages found"; return; }

    local choice
    choice=$(echo "$pkgs" | _rofi "  Installed")
    [ -z "$choice" ] && return

    local pkg_name
    pkg_name=$(echo "$choice" | awk '{print $1}')

    local action
    action=$(_rofi_list "$pkg_name" \
        "  Remove" \
        "  Package info" \
        "  List files")
    [ -z "$action" ] && return

    case "$action" in
        *Remove*)
            _confirm "Remove $pkg_name?" && _run_in_term "sudo pacman -Rns $pkg_name"
            ;;
        *info*)
            pacman -Qi "$pkg_name" 2>/dev/null | _rofi "  $pkg_name"
            ;;
        *files*)
            pacman -Ql "$pkg_name" 2>/dev/null | awk '{print $2}' | _rofi "  $pkg_name files"
            ;;
    esac
}

# ── Update ───────────────────────────────────────────────────

_update() {
    local h; h=$(_helper)

    local items=(
        "  Full system update (pacman + AUR)"
        "  Check for updates"
        "  Update mirrors (reflector)"
    )
    command -v flatpak &>/dev/null && items+=("  Update Flatpak apps")
    command -v snap &>/dev/null && items+=("  Update Snap packages")

    local action
    action=$(_rofi_list "  Update" "${items[@]}")
    [ -z "$action" ] && return

    case "$action" in
        *Full*)
            if [ "$h" = "pacman" ]; then
                _run_in_term "sudo pacman -Syu"
            else
                _run_in_term "$h -Syu"
            fi
            _apply_stoa_theme
            _notify "System updated"
            ;;
        *Check*)
            _notify "Checking..."
            local updates
            if [ "$h" = "pacman" ]; then
                updates=$(checkupdates 2>/dev/null)
            else
                updates=$($h -Qu 2>/dev/null)
            fi
            if [ -z "$updates" ]; then
                _notify "System is up to date"
            else
                local count
                count=$(echo "$updates" | wc -l)
                echo "$updates" | _rofi "  $count updates available"
            fi
            ;;
        *mirrors*)
            _confirm "Update mirrorlist with reflector?" || return
            _run_in_term "sudo reflector --latest 10 --sort rate --save /etc/pacman.d/mirrorlist && sudo pacman -Syy"
            _notify "Mirrors updated"
            ;;
        *Flatpak*)
            _run_in_term "flatpak update"
            _notify "Flatpak apps updated"
            ;;
        *Snap*)
            _run_in_term "sudo snap refresh"
            _notify "Snap packages updated"
            ;;
    esac
}

# ── Cleanup ──────────────────────────────────────────────────

_cleanup() {
    local items=(
        "  Remove orphans"
        "  Clean package cache"
        "  Clean all cached packages"
    )
    command -v flatpak &>/dev/null && items+=("  Clean unused Flatpak runtimes")

    local action
    action=$(_rofi_list "  Cleanup" "${items[@]}")
    [ -z "$action" ] && return

    case "$action" in
        *orphans*)
            local orphans
            orphans=$(pacman -Qdtq 2>/dev/null)
            if [ -z "$orphans" ]; then
                _notify "No orphans"
                return
            fi
            local count; count=$(echo "$orphans" | wc -l)
            echo "$orphans" | _rofi "  $count orphans (read-only)"
            _confirm "Remove $count orphans?" && \
                _run_in_term "sudo pacman -Rns \$(pacman -Qdtq)"
            _notify "Orphans removed"
            ;;
        *"Clean package"*)
            _confirm "Clean old cached packages? (keep last 3)" || return
            _run_in_term "sudo paccache -r"
            _notify "Cache cleaned"
            ;;
        *"Clean all"*)
            _confirm "Remove ALL cached packages?" || return
            _run_in_term "sudo pacman -Scc"
            _notify "All cache cleaned"
            ;;
        *Flatpak*)
            _run_in_term "flatpak uninstall --unused"
            _notify "Unused Flatpak runtimes removed"
            ;;
    esac
}

# ── Stats ────────────────────────────────────────────────────

_stats() {
    local total explicit foreign orphans cache_size
    total=$(pacman -Q 2>/dev/null | wc -l)
    explicit=$(pacman -Qe 2>/dev/null | wc -l)
    foreign=$(pacman -Qm 2>/dev/null | wc -l)
    orphans=$(pacman -Qdtq 2>/dev/null | wc -l)
    cache_size=$(du -sh /var/cache/pacman/pkg/ 2>/dev/null | awk '{print $1}')

    local h; h=$(_helper)
    local hook_status="not installed"
    [ -f /etc/pacman.d/hooks/stoa-theme.hook ] && hook_status="active"

    local lines=(
        "Pacman packages:    $total"
        "Explicitly installed: $explicit"
        "AUR / foreign:      $foreign"
        "Orphans:            $orphans"
        "Cache size:         $cache_size"
        "AUR helper:         $h"
        "Auto-theme hook:    $hook_status"
    )

    if command -v flatpak &>/dev/null; then
        local fp_count
        fp_count=$(flatpak list --app 2>/dev/null | wc -l)
        lines+=("Flatpak apps:       $fp_count")
    fi

    if command -v snap &>/dev/null; then
        local sn_count
        sn_count=$(snap list 2>/dev/null | tail -n +2 | wc -l)
        lines+=("Snap packages:      $sn_count")
    fi

    local ai_count=0
    [ -d "$APPIMAGE_DIR" ] && ai_count=$(find "$APPIMAGE_DIR" -maxdepth 1 -name "*.AppImage" 2>/dev/null | wc -l)
    lines+=("AppImages:          $ai_count")

    printf '%s\n' "${lines[@]}" | _rofi "  System info"
}

# ── Pacman hook setup ────────────────────────────────────────

_setup_hook() {
    local hook="/etc/pacman.d/hooks/stoa-theme.hook"
    local script="/usr/local/bin/stoa-theme-enforce"

    if [ -f "$hook" ]; then
        _notify "Auto-theme hook already active"
        return
    fi

    _confirm "Install auto-theme pacman hook? (sudo)" || return

    local stoa_dir
    stoa_dir="$(dirname "$(readlink -f "$0")")/.."

    if [ -f "$stoa_dir/pacman-hooks/stoa-theme-enforce" ]; then
        sudo mkdir -p /etc/pacman.d/hooks
        sudo cp "$stoa_dir/pacman-hooks/stoa-theme-enforce" "$script"
        sudo chmod +x "$script"
        sudo cp "$stoa_dir/pacman-hooks/stoa-theme.hook" "$hook"
    else
        # Inline fallback
        sudo mkdir -p /etc/pacman.d/hooks
        sudo tee "$script" > /dev/null <<'ENFORCE'
#!/bin/bash
U="${SUDO_USER:-$USER}"; H=$(eval echo "~$U")
g="$H/.config/gtk-3.0/settings.ini"; [ ! -f "$g" ] && exit 0
t=$(grep "^gtk-theme-name" "$g"|cut -d= -f2)
i=$(grep "^gtk-icon-theme-name" "$g"|cut -d= -f2)
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

# ── AUR helper install ───────────────────────────────────────

_install_aur_helper() {
    if _has_aur; then
        _notify "AUR helper already available: $(_helper)"
        return
    fi

    local choice
    choice=$(_rofi_list "  Install AUR helper" \
        "yay   — Go-based, most popular" \
        "paru  — Rust-based, fast")
    [ -z "$choice" ] && return

    local pkg
    [[ "$choice" == yay* ]] && pkg="yay"
    [[ "$choice" == paru* ]] && pkg="paru"

    _run_in_term "sudo pacman -S --needed git base-devel && cd /tmp && git clone https://aur.archlinux.org/${pkg}-bin.git && cd ${pkg}-bin && makepkg -si --noconfirm"
    command -v "$pkg" &>/dev/null && _notify "$pkg installed!"
}

# ══════════════════════════════════════════════════════════════
#   FLATPAK
# ══════════════════════════════════════════════════════════════

_flatpak_setup() {
    if command -v flatpak &>/dev/null; then
        # Ensure Flathub is added
        if ! flatpak remotes 2>/dev/null | grep -q flathub; then
            _notify "Adding Flathub repository..."
            flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo 2>/dev/null
        fi
        return 0
    fi

    local choice
    choice=$(_rofi_list "Flatpak not installed" \
        "  Install Flatpak" \
        "  Back")
    [[ "$choice" == *Install* ]] || return 1

    _run_in_term "sudo pacman -S --needed flatpak && flatpak remote-add --user --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo"
    command -v flatpak &>/dev/null || { _notify "Flatpak installation failed"; return 1; }
    _notify "Flatpak installed! Flathub added."
    return 0
}

_flatpak_search() {
    local query
    query=$(echo "" | _rofi "  Search Flathub")
    [ -z "$query" ] && return

    _notify "Searching Flathub for '$query'..."

    local results
    results=$(flatpak search "$query" --columns=name,application,description 2>/dev/null)
    [ -z "$results" ] && { _notify "Nothing found on Flathub"; return; }

    local lines=()
    while IFS=$'\t' read -r name app_id desc; do
        [ -z "$name" ] && continue
        local status=""
        flatpak info "$app_id" &>/dev/null && status="  [installed]"
        lines+=("${name}  ${app_id}  ${desc:0:40}${status}")
    done <<< "$results"

    [ ${#lines[@]} -eq 0 ] && { _notify "Nothing found"; return; }

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | head -80 | _rofi "  Flathub ($query)")
    [ -z "$choice" ] && return

    local sel_id
    sel_id=$(echo "$choice" | awk '{print $2}')

    if flatpak info "$sel_id" &>/dev/null; then
        local action
        action=$(_rofi_list "$sel_id [installed]" \
            "  Run" \
            "  Uninstall" \
            "  App info")
        case "$action" in
            *Run*)       flatpak run "$sel_id" & disown ;;
            *Uninstall*) _confirm "Remove $sel_id?" && _run_in_term "flatpak uninstall $sel_id" ;;
            *info*)      flatpak info "$sel_id" 2>/dev/null | _rofi "  $sel_id" ;;
        esac
    else
        _confirm "Install $sel_id from Flathub?" || return
        _run_in_term "flatpak install flathub $sel_id"
        _apply_stoa_theme
        _notify "$sel_id installed (Flatpak)"
    fi
}

_flatpak_installed() {
    local apps
    apps=$(flatpak list --app --columns=name,application 2>/dev/null)
    [ -z "$apps" ] && { _notify "No Flatpak apps installed"; return; }

    local lines=()
    while IFS=$'\t' read -r name app_id; do
        [ -z "$name" ] && continue
        lines+=("${name}  ${app_id}")
    done <<< "$apps"

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | _rofi "  Flatpak apps")
    [ -z "$choice" ] && return

    local sel_id
    sel_id=$(echo "$choice" | awk '{print $NF}')

    local action
    action=$(_rofi_list "$sel_id" \
        "  Run" \
        "  Uninstall" \
        "  App info")
    [ -z "$action" ] && return

    case "$action" in
        *Run*)       flatpak run "$sel_id" & disown ;;
        *Uninstall*) _confirm "Remove $sel_id?" && _run_in_term "flatpak uninstall $sel_id" ;;
        *info*)      flatpak info "$sel_id" 2>/dev/null | _rofi "  $sel_id" ;;
    esac
}

menu_flatpak() {
    _flatpak_setup || return

    while true; do
        local app_count
        app_count=$(flatpak list --app 2>/dev/null | wc -l)

        local choice
        choice=$(_rofi_list "  Flatpak ($app_count apps)" \
            "  Search & install (Flathub)" \
            "  Installed apps" \
            "  Update all" \
            "  Clean unused runtimes" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Search*)   _flatpak_search ;;
            *Installed*) _flatpak_installed ;;
            *Update*)   _run_in_term "flatpak update"; _notify "Flatpak updated" ;;
            *Clean*)    _run_in_term "flatpak uninstall --unused"; _notify "Cleanup done" ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   SNAP
# ══════════════════════════════════════════════════════════════

_snap_setup() {
    if command -v snap &>/dev/null; then
        return 0
    fi

    local choice
    choice=$(_rofi_list "Snap not installed" \
        "  Install Snap (snapd from AUR)" \
        "  Back")
    [[ "$choice" == *Install* ]] || return 1

    if ! _has_aur; then
        _notify "AUR helper needed to install snapd. Install yay or paru first."
        return 1
    fi

    local h; h=$(_helper)
    _run_in_term "$h -S --needed snapd && sudo systemctl enable --now snapd.socket && sudo ln -sf /var/lib/snapd/snap /snap 2>/dev/null"
    command -v snap &>/dev/null || { _notify "Snap installation failed. Reboot may be required."; return 1; }
    _notify "Snap installed! snapd.socket enabled."
    return 0
}

_snap_search() {
    local query
    query=$(echo "" | _rofi "  Search Snap Store")
    [ -z "$query" ] && return

    _notify "Searching Snap Store for '$query'..."

    local results
    results=$(snap find "$query" 2>/dev/null | tail -n +2)
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

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | head -80 | _rofi "  Snap ($query)")
    [ -z "$choice" ] && return

    local sel_pkg
    sel_pkg=$(echo "$choice" | awk '{print $1}')

    if snap list "$sel_pkg" &>/dev/null; then
        local action
        action=$(_rofi_list "$sel_pkg [installed]" \
            "  Run" \
            "  Remove" \
            "  Info")
        case "$action" in
            *Run*)    snap run "$sel_pkg" & disown ;;
            *Remove*) _confirm "Remove $sel_pkg?" && _run_in_term "sudo snap remove $sel_pkg" ;;
            *Info*)   snap info "$sel_pkg" 2>/dev/null | _rofi "  $sel_pkg" ;;
        esac
    else
        _confirm "Install $sel_pkg from Snap?" || return
        _run_in_term "sudo snap install $sel_pkg"
        _notify "$sel_pkg installed (Snap)"
    fi
}

_snap_installed() {
    local apps
    apps=$(snap list 2>/dev/null | tail -n +2)
    [ -z "$apps" ] && { _notify "No Snap packages installed"; return; }

    local lines=()
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name ver
        name=$(echo "$line" | awk '{print $1}')
        ver=$(echo "$line" | awk '{print $2}')
        lines+=("${name}  ${ver}")
    done <<< "$apps"

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | _rofi "  Snap packages")
    [ -z "$choice" ] && return

    local sel_pkg
    sel_pkg=$(echo "$choice" | awk '{print $1}')

    local action
    action=$(_rofi_list "$sel_pkg" \
        "  Run" \
        "  Remove" \
        "  Info")
    [ -z "$action" ] && return

    case "$action" in
        *Run*)    snap run "$sel_pkg" & disown ;;
        *Remove*) _confirm "Remove $sel_pkg?" && _run_in_term "sudo snap remove $sel_pkg" ;;
        *Info*)   snap info "$sel_pkg" 2>/dev/null | _rofi "  $sel_pkg" ;;
    esac
}

menu_snap() {
    _snap_setup || return

    while true; do
        local pkg_count
        pkg_count=$(snap list 2>/dev/null | tail -n +2 | wc -l)

        local choice
        choice=$(_rofi_list "  Snap ($pkg_count pkgs)" \
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

# ══════════════════════════════════════════════════════════════
#   APPIMAGE
# ══════════════════════════════════════════════════════════════

_appimage_list() {
    [ ! -d "$APPIMAGE_DIR" ] && return
    find "$APPIMAGE_DIR" -maxdepth 1 -name "*.AppImage" -printf '%f\n' 2>/dev/null | sort
}

_appimage_run() {
    local apps
    apps=$(_appimage_list)
    [ -z "$apps" ] && { _notify "No AppImages in ~/Applications"; return; }

    local choice
    choice=$(echo "$apps" | _rofi "  Run AppImage")
    [ -z "$choice" ] && return

    chmod +x "${APPIMAGE_DIR}/${choice}" 2>/dev/null
    "${APPIMAGE_DIR}/${choice}" & disown
    _notify "Launched: $choice"
}

_appimage_add_file() {
    local path
    path=$(echo "" | _rofi "  Path to .AppImage file")
    [ -z "$path" ] && return

    # Expand ~ if present
    path="${path/#\~/$HOME}"

    if [ ! -f "$path" ]; then
        _notify "File not found: $path"
        return
    fi

    if [[ "$path" != *.AppImage ]]; then
        _notify "File must end in .AppImage"
        return
    fi

    mkdir -p "$APPIMAGE_DIR"
    local basename
    basename=$(basename "$path")
    cp "$path" "${APPIMAGE_DIR}/${basename}"
    chmod +x "${APPIMAGE_DIR}/${basename}"
    _notify "Added: $basename"

    _confirm "Create desktop shortcut for $basename?" && _appimage_create_desktop "$basename"
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

_appimage_remove() {
    local apps
    apps=$(_appimage_list)
    [ -z "$apps" ] && { _notify "No AppImages in ~/Applications"; return; }

    local choice
    choice=$(echo "$apps" | _rofi "  Remove AppImage")
    [ -z "$choice" ] && return

    _confirm "Remove $choice?" || return

    rm -f "${APPIMAGE_DIR}/${choice}"
    local name="${choice%.AppImage}"
    rm -f "${HOME}/.local/share/applications/appimage-${name}.desktop" 2>/dev/null
    _notify "Removed: $choice"
}

menu_appimage() {
    while true; do
        mkdir -p "$APPIMAGE_DIR"
        local count
        count=$(_appimage_list | wc -l)

        local choice
        choice=$(_rofi_list "  AppImage ($count apps)" \
            "  Run AppImage" \
            "  Add from file" \
            "  Create desktop shortcut" \
            "  Remove AppImage" \
            "  Open ~/Applications" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Run*)
                _appimage_run
                ;;
            *"Add from"*)
                _appimage_add_file
                ;;
            *"desktop shortcut"*)
                local apps
                apps=$(_appimage_list)
                [ -z "$apps" ] && { _notify "No AppImages"; continue; }
                local sel
                sel=$(echo "$apps" | _rofi "  Create shortcut for")
                [ -n "$sel" ] && _appimage_create_desktop "$sel"
                ;;
            *Remove*)
                _appimage_remove
                ;;
            *Open*)
                thunar "$APPIMAGE_DIR" & disown
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   DEB / RPM  (convert via debtap)
# ══════════════════════════════════════════════════════════════

_debtap_setup() {
    if command -v debtap &>/dev/null; then
        return 0
    fi

    local choice
    choice=$(_rofi_list "debtap not installed" \
        "  Install debtap (AUR)" \
        "  Back")
    [[ "$choice" == *Install* ]] || return 1

    if ! _has_aur; then
        _notify "AUR helper needed to install debtap. Install yay or paru first."
        return 1
    fi

    local h; h=$(_helper)
    _run_in_term "$h -S --needed debtap && sudo debtap -u"
    command -v debtap &>/dev/null || { _notify "debtap installation failed"; return 1; }
    _notify "debtap installed and database updated"
    return 0
}

_install_deb() {
    local path
    path=$(echo "" | _rofi "  Path to .deb file")
    [ -z "$path" ] && return
    path="${path/#\~/$HOME}"

    if [ ! -f "$path" ]; then
        _notify "File not found: $path"
        return
    fi

    if [[ "$path" != *.deb ]]; then
        _notify "File must be a .deb package"
        return
    fi

    _notify "Converting .deb to Arch package..."
    _run_in_term "cd /tmp && debtap -Q '$path' && sudo pacman -U /tmp/*.pkg.tar* && rm -f /tmp/*.pkg.tar*"
    _apply_stoa_theme
    _notify "DEB package installed"
}

_install_rpm() {
    if ! command -v rpmextract &>/dev/null; then
        _notify "rpmextract not found. Installing..."
        _run_in_term "sudo pacman -S --needed rpmextract"
    fi

    local path
    path=$(echo "" | _rofi "  Path to .rpm file")
    [ -z "$path" ] && return
    path="${path/#\~/$HOME}"

    if [ ! -f "$path" ]; then
        _notify "File not found: $path"
        return
    fi

    if [[ "$path" != *.rpm ]]; then
        _notify "File must be a .rpm package"
        return
    fi

    _notify "Converting .rpm to Arch package..."
    _run_in_term "cd /tmp && debtap -Q '$path' && sudo pacman -U /tmp/*.pkg.tar* && rm -f /tmp/*.pkg.tar*"
    _apply_stoa_theme
    _notify "RPM package installed"
}

menu_deb_rpm() {
    _debtap_setup || return

    while true; do
        local choice
        choice=$(_rofi_list "  DEB / RPM" \
            "  Install .deb package" \
            "  Install .rpm package" \
            "  Update debtap database" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *.deb*)     _install_deb ;;
            *.rpm*)     _install_rpm ;;
            *Update*)   _run_in_term "sudo debtap -u"; _notify "debtap database updated" ;;
        esac
    done
}

# ══════════════════════════════════════════════════════════════
#   MAIN
# ══════════════════════════════════════════════════════════════

main() {
    while true; do
        local h; h=$(_helper)
        local aur_tag=""
        _has_aur && aur_tag=" + AUR"

        local sources="${h}${aur_tag}"
        command -v flatpak &>/dev/null && sources+=" + Flatpak"
        command -v snap &>/dev/null && sources+=" + Snap"

        local choice
        choice=$(_rofi_list "  Stoa Store (${sources})" \
            "  Search & install (Pacman + AUR)" \
            "  Installed packages" \
            "  Update system" \
            "  Cleanup" \
            "  System info" \
            "─────────────────────" \
            "  Flatpak (Flathub)" \
            "  Snap (Snap Store)" \
            "  AppImage" \
            "  DEB / RPM (convert)" \
            "─────────────────────" \
            "  Setup auto-theme hook" \
            "  Re-apply Stoa theme" \
            "  Install AUR helper")
        [ -z "$choice" ] && exit 0

        case "$choice" in
            *"Search & install"*) _search_install ;;
            *Installed*)    _installed ;;
            *Update*)       _update ;;
            *Cleanup*)      _cleanup ;;
            *info*)         _stats ;;
            *Flatpak*)      menu_flatpak ;;
            *Snap*)         menu_snap ;;
            *AppImage*)     menu_appimage ;;
            *DEB*)          menu_deb_rpm ;;
            *auto-theme*)   _setup_hook ;;
            *Re-apply*)     _apply_stoa_theme; _notify "Stoa theme applied" ;;
            *"AUR helper"*) _install_aur_helper ;;
        esac
    done
}

main
