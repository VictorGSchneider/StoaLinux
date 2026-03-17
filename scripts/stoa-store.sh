#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — App Store                                     ║
# ║  "Wealth is the slave of a wise man." — Seneca               ║
# ║                                                              ║
# ║  Full package manager via rofi.                              ║
# ║  Repos oficiais + AUR. Instalar, remover, atualizar.        ║
# ║  Auto-aplica tema Stoa em tudo que for instalado.           ║
# ╚══════════════════════════════════════════════════════════════╝

ROFI="rofi -dmenu -i -config ${HOME}/.config/rofi/config.rasi"

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
        gsettings set org.gnome.desktop.interface icon-theme   "${i:-Papirus-Dark}"    2>/dev/null
        gsettings set org.gnome.desktop.interface cursor-theme "${c:-Adwaita}"         2>/dev/null
        gsettings set org.gnome.desktop.interface font-name    "${f:-Noto Serif 10}" 2>/dev/null
        gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"           2>/dev/null
    fi
    [ -n "$WAYLAND_DISPLAY" ] && command -v hyprctl &>/dev/null && \
        hyprctl setcursor "${c:-Adwaita}" 24 &>/dev/null
}

# ── Search ───────────────────────────────────────────────────

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
    local action
    action=$(_rofi_list "  Update" \
        "  Full system update" \
        "  Check for updates" \
        "  Update mirrors (reflector)")
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
    esac
}

# ── Cleanup ──────────────────────────────────────────────────

_cleanup() {
    local action
    action=$(_rofi_list "  Cleanup" \
        "  Remove orphans" \
        "  Clean package cache" \
        "  Clean all cached packages")
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

    printf '%s\n' \
        "Total packages:     $total" \
        "Explicitly installed: $explicit" \
        "AUR / foreign:      $foreign" \
        "Orphans:            $orphans" \
        "Cache size:         $cache_size" \
        "AUR helper:         $h" \
        "Auto-theme hook:    $hook_status" \
    | _rofi "  System info"
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
#   MAIN
# ══════════════════════════════════════════════════════════════

main() {
    while true; do
        local h; h=$(_helper)
        local aur_tag=""
        _has_aur && aur_tag=" + AUR"

        local choice
        choice=$(_rofi_list "  Stoa Store (${h}${aur_tag})" \
            "  Search & install" \
            "  Installed packages" \
            "  Update system" \
            "  Cleanup" \
            "  System info" \
            "─────────────────────" \
            "  Setup auto-theme hook" \
            "  Re-apply Stoa theme" \
            "  Install AUR helper")
        [ -z "$choice" ] && exit 0

        case "$choice" in
            *Search*)       _search_install ;;
            *Installed*)    _installed ;;
            *Update*)       _update ;;
            *Cleanup*)      _cleanup ;;
            *info*)         _stats ;;
            *auto-theme*)   _setup_hook ;;
            *Re-apply*)     _apply_stoa_theme; _notify "Stoa theme applied" ;;
            *AUR*)          _install_aur_helper ;;
        esac
    done
}

main
