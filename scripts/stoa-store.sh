#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — App Store                                     ║
# ║  "Wealth is the slave of a wise man." — Seneca               ║
# ║                                                              ║
# ║  Full package manager via rofi.                              ║
# ║  Pacman + AUR + Flatpak + Snap + AppImage + DEB/RPM.        ║
# ║  Auto-applies Stoa theme on everything installed.            ║
# ╚══════════════════════════════════════════════════════════════╝

ROFI=(rofi -dmenu -i -config "${HOME}/.config/rofi/config.rasi")
APPIMAGE_DIR="${HOME}/Applications"

# ── Helpers ──────────────────────────────────────────────────

_notify() { dunstify -t 2500 "Stoa Store" "$1" 2>/dev/null; }

_rofi() {
    "${ROFI[@]}" -p "$1"
}

_rofi_list() {
    local prompt="$1"; shift
    printf '%s\n' "$@" | "${ROFI[@]}" -p "$prompt"
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
    alacritty -e bash -c "$1; echo; echo 'Press Enter to close...'; read"
}

_apply_stoa_theme() {
    local gtk3="${HOME}/.config/gtk-3.0/settings.ini"
    [ ! -f "$gtk3" ] && return
    local t i c f
    t=$(grep "^gtk-theme-name"       "$gtk3" | sed 's/^[^=]*=\s*//')
    i=$(grep "^gtk-icon-theme-name"  "$gtk3" | sed 's/^[^=]*=\s*//')
    c=$(grep "^gtk-cursor-theme-name" "$gtk3" | sed 's/^[^=]*=\s*//')
    f=$(grep "^gtk-font-name"        "$gtk3" | sed 's/^[^=]*=\s*//')
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

# ── Search (unified with source filter) ────────────────────────

_search_pacman() {
    local query="$1"
    local h; h=$(_helper)
    local results

    if [ "$h" = "pacman" ]; then
        results=$(pacman -Ss "$query" 2>/dev/null)
    else
        results=$($h -Ss "$query" 2>/dev/null)
    fi

    [ -z "$results" ] && return

    local lines=()
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

        local tag="[arch]"
        [[ "$repo" == "aur" ]] && tag="[AUR]"

        lines+=("${tag} ${pkg_name}  ${ver}  ${desc:0:45}${status}")
    done <<< "$results"

    printf '%s\n' "${lines[@]}"
}

_search_flatpak_results() {
    local query="$1"
    command -v flatpak &>/dev/null || return

    local results
    results=$(flatpak search "$query" --columns=name,application,description 2>/dev/null)
    [ -z "$results" ] && return

    while IFS=$'\t' read -r name app_id desc; do
        [ -z "$name" ] && continue
        local status=""
        flatpak info "$app_id" &>/dev/null && status="  [installed]"
        echo "[flatpak] ${name}  ${app_id}  ${desc:0:35}${status}"
    done <<< "$results"
}

_search_snap_results() {
    local query="$1"
    command -v snap &>/dev/null || return

    local results
    results=$(snap find "$query" 2>/dev/null | tail -n +2)
    [ -z "$results" ] && return

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name ver summary
        name=$(echo "$line" | awk '{print $1}')
        ver=$(echo "$line" | awk '{print $2}')
        summary=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
        local status=""
        snap list "$name" &>/dev/null 2>&1 && status="  [installed]"
        echo "[snap] ${name}  ${ver}  ${summary:0:40}${status}"
    done <<< "$results"
}

_handle_pacman_selection() {
    local sel_pkg="$1"
    _pkg_detail "$sel_pkg"
}

# ── Package detail view (Synaptic-style) ─────────────────────

_pkg_detail() {
    local pkg="$1"
    local h; h=$(_helper)

    while true; do
        local installed=false
        _is_installed "$pkg" && installed=true

        local status_tag="not installed"
        local install_reason=""
        if $installed; then
            install_reason=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Install Reason" | sed 's/.*: //')
            if [[ "$install_reason" == *"dependency"* ]]; then
                status_tag="dependency"
            else
                status_tag="explicit"
            fi
        fi

        local ver=""
        if $installed; then
            ver=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
        else
            ver=$(pacman -Si "$pkg" 2>/dev/null | grep "^Version" | head -1 | sed 's/.*: //')
        fi

        local items=()
        items+=("  Status: $status_tag  $ver")
        items+=("─────────────────────")
        items+=("  Full info")
        items+=("  Dependencies")
        items+=("  Required by (reverse deps)")
        items+=("  Optional dependencies")
        items+=("  Dependency tree")
        items+=("  Provides / Conflicts / Replaces")
        if $installed; then
            items+=("  Installed files")
            items+=("  Changelog / install script")
            items+=("─────────────────────")
            items+=("  Reinstall")
            items+=("  Remove (keep deps)")
            items+=("  Complete removal (pkg + deps)")
            if [[ "$install_reason" == *"dependency"* ]]; then
                items+=("  Mark as explicit")
            else
                items+=("  Mark as dependency")
            fi
        else
            items+=("─────────────────────")
            items+=("  Install (with dependencies)")
            items+=("  Install as dependency")
        fi
        items+=("─────────────────────")
        items+=("  Back")

        local action
        action=$(_rofi_list "  $pkg" "${items[@]}")
        [ -z "$action" ] || [[ "$action" == *Back* ]] && return

        case "$action" in
            *"Full info"*)
                if $installed; then
                    pacman -Qi "$pkg" 2>/dev/null | _rofi "  $pkg info"
                else
                    pacman -Si "$pkg" 2>/dev/null | _rofi "  $pkg info"
                fi
                ;;
            *"Dependencies"*)
                _show_deps "$pkg" "$installed"
                ;;
            *"Required by"*)
                _show_reverse_deps "$pkg" "$installed"
                ;;
            *"Optional dep"*)
                _show_optional_deps "$pkg" "$installed"
                ;;
            *"Dependency tree"*)
                _show_dep_tree "$pkg"
                ;;
            *"Provides"*)
                _show_provides_conflicts "$pkg" "$installed"
                ;;
            *"Installed files"*)
                pacman -Ql "$pkg" 2>/dev/null | awk '{print $2}' | _rofi "  $pkg files"
                ;;
            *"Changelog"*)
                local scriptlet
                scriptlet=$(pacman -Qi "$pkg" 2>/dev/null | grep -A1 "^Install Script")
                if pacman -Ql "$pkg" 2>/dev/null | grep -qi changelog; then
                    local cl_file
                    cl_file=$(pacman -Ql "$pkg" 2>/dev/null | grep -i changelog | head -1 | awk '{print $2}')
                    if [ -f "$cl_file" ]; then
                        head -80 "$cl_file" | _rofi "  $pkg changelog"
                    else
                        echo "No changelog found" | _rofi "  $pkg"
                    fi
                else
                    echo "No changelog or install script found" | _rofi "  $pkg"
                fi
                ;;
            *"Reinstall"*)
                _run_in_term "sudo pacman -S $pkg"
                _apply_stoa_theme
                ;;
            *"Remove (keep"*)
                _confirm "Remove $pkg (keep dependencies)?" && _run_in_term "sudo pacman -R $pkg"
                ;;
            *"Complete removal"*)
                _complete_removal "$pkg"
                ;;
            *"Mark as explicit"*)
                sudo pacman -D --asexplicit "$pkg" 2>/dev/null
                _notify "$pkg marked as explicitly installed"
                ;;
            *"Mark as dependency"*)
                _confirm "Mark $pkg as dependency? (may be removed as orphan)" || continue
                sudo pacman -D --asdeps "$pkg" 2>/dev/null
                _notify "$pkg marked as dependency"
                ;;
            *"Install as dep"*)
                _confirm "Install $pkg as dependency?" || continue
                if [ "$h" = "pacman" ]; then
                    _run_in_term "sudo pacman -S --asdeps $pkg"
                else
                    _run_in_term "$h -S --asdeps $pkg"
                fi
                _apply_stoa_theme
                ;;
            *"Install"*)
                _install_with_deps_preview "$pkg"
                ;;
        esac
    done
}

_install_with_deps_preview() {
    local pkg="$1"
    local h; h=$(_helper)

    # Get list of dependencies that would be installed
    local deps_info
    deps_info=$(pacman -Si "$pkg" 2>/dev/null | grep "^Depends On" | sed 's/.*: //')

    local new_deps=()
    local already_installed=()
    if [ -n "$deps_info" ] && [ "$deps_info" != "None" ]; then
        for dep in $deps_info; do
            local dep_name="${dep%%[><=]*}"
            if _is_installed "$dep_name"; then
                already_installed+=("  $dep_name  [already installed]")
            else
                new_deps+=("  $dep_name  [will install]")
            fi
        done
    fi

    local lines=()
    lines+=("Package: $pkg")
    lines+=("")

    if [ ${#new_deps[@]} -gt 0 ]; then
        lines+=("── New dependencies (${#new_deps[@]}) ──")
        lines+=("${new_deps[@]}")
    fi
    if [ ${#already_installed[@]} -gt 0 ]; then
        lines+=("── Already satisfied (${#already_installed[@]}) ──")
        lines+=("${already_installed[@]}")
    fi
    if [ ${#new_deps[@]} -eq 0 ] && [ ${#already_installed[@]} -eq 0 ]; then
        lines+=("No dependencies required")
    fi
    lines+=("")
    lines+=("  Confirm install")
    lines+=("  Cancel")

    local confirm
    confirm=$(printf '%s\n' "${lines[@]}" | _rofi "  Install $pkg")
    [[ "$confirm" == *"Confirm"* ]] || return

    if [ "$h" = "pacman" ]; then
        _run_in_term "sudo pacman -S --needed $pkg"
    else
        _run_in_term "$h -S --needed $pkg"
    fi
    _is_installed "$pkg" && _apply_stoa_theme && _notify "$pkg installed"
}

_complete_removal() {
    local pkg="$1"

    # Get exclusive dependencies (deps that ONLY this package needs)
    local deps
    deps=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Depends On" | sed 's/.*: //')

    local safe_to_remove=()
    local shared_deps=()
    local conflict_details=()

    if [ -n "$deps" ] && [ "$deps" != "None" ]; then
        for dep in $deps; do
            local dep_name="${dep%%[><=]*}"
            # Skip if not installed
            _is_installed "$dep_name" || continue

            # Check who else needs this dependency
            local rdeps
            rdeps=$(pacman -Qi "$dep_name" 2>/dev/null | grep "^Required By" | sed 's/.*: //')

            if [ -z "$rdeps" ] || [ "$rdeps" = "None" ]; then
                safe_to_remove+=("$dep_name")
            else
                # Filter out the package being removed itself
                local other_rdeps=""
                for rd in $rdeps; do
                    [ "$rd" != "$pkg" ] && other_rdeps+="$rd "
                done
                other_rdeps=$(echo "$other_rdeps" | sed 's/ $//')

                if [ -z "$other_rdeps" ]; then
                    safe_to_remove+=("$dep_name")
                else
                    shared_deps+=("$dep_name")
                    conflict_details+=("  $dep_name → needed by: $other_rdeps")
                fi
            fi
        done
    fi

    # Build the confirmation screen
    local lines=()
    lines+=("Package to remove: $pkg")
    lines+=("")

    if [ ${#safe_to_remove[@]} -gt 0 ]; then
        lines+=("── Will also remove (${#safe_to_remove[@]} exclusive deps) ──")
        for d in "${safe_to_remove[@]}"; do
            lines+=("  $d")
        done
    fi

    if [ ${#shared_deps[@]} -gt 0 ]; then
        lines+=("")
        lines+=("──  Shared deps (will NOT remove) ──")
        for detail in "${conflict_details[@]}"; do
            lines+=("$detail")
        done
    fi

    local total_remove=$((1 + ${#safe_to_remove[@]}))
    lines+=("")
    lines+=("Total packages to remove: $total_remove")
    lines+=("")
    lines+=("  Confirm complete removal")
    lines+=("  Remove only $pkg (keep deps)")
    lines+=("  Cancel")

    local confirm
    confirm=$(printf '%s\n' "${lines[@]}" | _rofi "  Remove $pkg")

    case "$confirm" in
        *"Confirm complete"*)
            local remove_list="$pkg"
            for d in "${safe_to_remove[@]}"; do
                remove_list+=" $d"
            done
            _run_in_term "sudo pacman -Rns $remove_list"
            _is_installed "$pkg" || _notify "$pkg completely removed"
            ;;
        *"Remove only"*)
            _run_in_term "sudo pacman -R $pkg"
            ;;
    esac
}

_show_deps() {
    local pkg="$1" installed="$2"
    local deps

    if $installed; then
        deps=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Depends On" | sed 's/.*: //')
    else
        deps=$(pacman -Si "$pkg" 2>/dev/null | grep "^Depends On" | sed 's/.*: //')
    fi

    if [ -z "$deps" ] || [ "$deps" = "None" ]; then
        _notify "$pkg has no dependencies"
        return
    fi

    local lines=()
    for dep in $deps; do
        # Strip version constraints (e.g. glibc>=2.38)
        local dep_name="${dep%%[><=]*}"
        local status=""
        _is_installed "$dep_name" && status="  [installed]"
        lines+=("${dep}${status}")
    done

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | _rofi "  $pkg → depends on")
    [ -z "$choice" ] && return

    local sel_dep="${choice%%[><=]*}"
    sel_dep=$(echo "$sel_dep" | awk '{print $1}')
    _pkg_detail "$sel_dep"
}

_show_reverse_deps() {
    local pkg="$1" installed="$2"

    if ! $installed; then
        _notify "Package must be installed to see reverse deps"
        return
    fi

    local rdeps
    rdeps=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Required By" | sed 's/.*: //')

    if [ -z "$rdeps" ] || [ "$rdeps" = "None" ]; then
        _notify "Nothing depends on $pkg"
        return
    fi

    local lines=()
    for rdep in $rdeps; do
        local reason=""
        local r_info
        r_info=$(pacman -Qi "$rdep" 2>/dev/null | grep "^Install Reason" | sed 's/.*: //')
        [[ "$r_info" == *"dependency"* ]] && reason="  (dep)" || reason="  (explicit)"
        lines+=("${rdep}${reason}")
    done

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | _rofi "  $pkg ← required by")
    [ -z "$choice" ] && return

    local sel_rdep
    sel_rdep=$(echo "$choice" | awk '{print $1}')
    _pkg_detail "$sel_rdep"
}

_show_optional_deps() {
    local pkg="$1" installed="$2"
    local optdeps

    if $installed; then
        optdeps=$(pacman -Qi "$pkg" 2>/dev/null | sed -n '/^Optional Deps/,/^[A-Z]/p' | head -n -1 | sed 's/^Optional Deps *: //' | sed 's/^  *//')
    else
        optdeps=$(pacman -Si "$pkg" 2>/dev/null | sed -n '/^Optional Deps/,/^[A-Z]/p' | head -n -1 | sed 's/^Optional Deps *: //' | sed 's/^  *//')
    fi

    if [ -z "$optdeps" ] || [ "$optdeps" = "None" ]; then
        _notify "$pkg has no optional dependencies"
        return
    fi

    local lines=()
    while IFS= read -r odep; do
        [ -z "$odep" ] && continue
        local odep_name="${odep%%:*}"
        odep_name="${odep_name%%[><=]*}"
        odep_name=$(echo "$odep_name" | awk '{print $1}')
        local status=""
        _is_installed "$odep_name" && status=" [installed]"
        lines+=("${odep}${status}")
    done <<< "$optdeps"

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | _rofi "  $pkg → optional deps")
    [ -z "$choice" ] && return

    local sel_dep
    sel_dep=$(echo "$choice" | awk '{print $1}')
    sel_dep="${sel_dep%%:*}"
    sel_dep="${sel_dep%%[><=]*}"
    _pkg_detail "$sel_dep"
}

_show_dep_tree() {
    local pkg="$1"
    _notify "Building dependency tree..."

    local output
    output=$(pactree "$pkg" 2>/dev/null)

    if [ -z "$output" ]; then
        _notify "pactree not available or no deps"
        return
    fi

    local choice
    choice=$(echo "$output" | _rofi "  $pkg dependency tree")
    [ -z "$choice" ] && return

    # Strip tree drawing chars and get package name
    local sel_pkg
    sel_pkg=$(echo "$choice" | sed 's/[│├└─ ]//g' | sed 's/^|//' | awk '{print $1}')
    [ -n "$sel_pkg" ] && _pkg_detail "$sel_pkg"
}

_show_provides_conflicts() {
    local pkg="$1" installed="$2"
    local info_cmd="pacman -Si"
    $installed && info_cmd="pacman -Qi"

    local provides conflicts replaces
    provides=$($info_cmd "$pkg" 2>/dev/null | grep "^Provides" | sed 's/.*: //')
    conflicts=$($info_cmd "$pkg" 2>/dev/null | grep "^Conflicts With" | sed 's/.*: //')
    replaces=$($info_cmd "$pkg" 2>/dev/null | grep "^Replaces" | sed 's/.*: //')

    local lines=()
    lines+=("── Provides ──")
    if [ -n "$provides" ] && [ "$provides" != "None" ]; then
        for p in $provides; do lines+=("  $p"); done
    else
        lines+=("  (none)")
    fi
    lines+=("── Conflicts With ──")
    if [ -n "$conflicts" ] && [ "$conflicts" != "None" ]; then
        for c in $conflicts; do lines+=("  $c"); done
    else
        lines+=("  (none)")
    fi
    lines+=("── Replaces ──")
    if [ -n "$replaces" ] && [ "$replaces" != "None" ]; then
        for r in $replaces; do lines+=("  $r"); done
    else
        lines+=("  (none)")
    fi

    printf '%s\n' "${lines[@]}" | _rofi "  $pkg provides/conflicts"
}

_handle_flatpak_selection() {
    local sel_id="$1"

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

_handle_snap_selection() {
    local sel_pkg="$1"

    if snap list "$sel_pkg" &>/dev/null 2>&1; then
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

_search_install() {
    # Source filter
    local sources=("  All sources")
    sources+=("  Arch official")
    _has_aur && sources+=("  AUR")
    command -v flatpak &>/dev/null && sources+=("  Flatpak (Flathub)")
    command -v snap &>/dev/null && sources+=("  Snap Store")

    local source_choice
    source_choice=$(_rofi_list "  Filter by source" "${sources[@]}")
    [ -z "$source_choice" ] && return

    local query
    query=$(echo "" | _rofi "  Search (install)")
    [ -z "$query" ] && return

    _notify "Searching '$query'..."

    local all_results=""

    case "$source_choice" in
        *All*)
            all_results+=$(_search_pacman "$query")
            all_results+=$'\n'
            all_results+=$(_search_flatpak_results "$query")
            all_results+=$'\n'
            all_results+=$(_search_snap_results "$query")
            ;;
        *"Arch official"*)
            local results
            results=$(pacman -Ss "$query" 2>/dev/null)
            [ -n "$results" ] && {
                local lines=()
                while IFS= read -r line1; do
                    IFS= read -r line2 || true
                    local repo_pkg ver desc
                    repo_pkg=$(echo "$line1" | awk '{print $1}')
                    ver=$(echo "$line1" | awk '{print $2}')
                    desc=$(echo "$line2" | sed 's/^[[:space:]]*//')
                    local pkg_name="${repo_pkg#*/}"
                    local repo="${repo_pkg%/*}"
                    [[ "$repo" == "aur" ]] && continue
                    local status=""
                    _is_installed "$pkg_name" && status="  [installed]"
                    lines+=("[arch] ${pkg_name}  ${ver}  ${desc:0:45}${status}")
                done <<< "$results"
                all_results=$(printf '%s\n' "${lines[@]}")
            }
            ;;
        *AUR*)
            local h; h=$(_helper)
            local results
            results=$($h -Ss "$query" 2>/dev/null)
            [ -n "$results" ] && {
                local lines=()
                while IFS= read -r line1; do
                    IFS= read -r line2 || true
                    local repo_pkg ver desc
                    repo_pkg=$(echo "$line1" | awk '{print $1}')
                    ver=$(echo "$line1" | awk '{print $2}')
                    desc=$(echo "$line2" | sed 's/^[[:space:]]*//')
                    local pkg_name="${repo_pkg#*/}"
                    local repo="${repo_pkg%/*}"
                    [[ "$repo" != "aur" ]] && continue
                    local status=""
                    _is_installed "$pkg_name" && status="  [installed]"
                    lines+=("[AUR] ${pkg_name}  ${ver}  ${desc:0:45}${status}")
                done <<< "$results"
                all_results=$(printf '%s\n' "${lines[@]}")
            }
            ;;
        *Flatpak*)
            all_results=$(_search_flatpak_results "$query")
            ;;
        *Snap*)
            all_results=$(_search_snap_results "$query")
            ;;
    esac

    # Remove empty lines
    all_results=$(echo "$all_results" | sed '/^$/d')

    [ -z "$all_results" ] && { _notify "Nothing found for '$query'"; return; }

    local choice
    choice=$(echo "$all_results" | head -120 | _rofi "  Results ($query)")
    [ -z "$choice" ] && return

    # Determine source from tag and dispatch
    local tag
    tag=$(echo "$choice" | awk '{print $1}')
    local sel_pkg

    case "$tag" in
        "[arch]"|"[AUR]")
            sel_pkg=$(echo "$choice" | awk '{print $2}')
            _handle_pacman_selection "$sel_pkg"
            ;;
        "[flatpak]")
            sel_pkg=$(echo "$choice" | awk '{print $3}')
            _handle_flatpak_selection "$sel_pkg"
            ;;
        "[snap]")
            sel_pkg=$(echo "$choice" | awk '{print $2}')
            _handle_snap_selection "$sel_pkg"
            ;;
    esac
}

# ── Package browser (Synaptic-style) ─────────────────────────

_installed() {
    while true; do
        local total deps explicit foreign orphans
        total=$(pacman -Q 2>/dev/null | wc -l)
        explicit=$(pacman -Qe 2>/dev/null | wc -l)
        deps=$((total - explicit))
        foreign=$(pacman -Qm 2>/dev/null | wc -l)
        orphans=$(pacman -Qdtq 2>/dev/null | wc -l)

        local filter
        filter=$(_rofi_list "  Package browser ($total pkgs)" \
            "  All installed ($total)" \
            "  Explicitly installed ($explicit)" \
            "  Dependencies only ($deps)" \
            "  AUR / foreign ($foreign)" \
            "  Orphan dependencies ($orphans)" \
            "  Upgradeable" \
            "─────────────────────" \
            "  Browse by group" \
            "  Browse by repository" \
            "  Search all (installed + available)" \
            "  Search installed" \
            "  Check broken dependencies" \
            "─────────────────────" \
            "  Back")
        [ -z "$filter" ] || [[ "$filter" == *Back* ]] && return

        case "$filter" in
            *"All installed"*)
                _browse_pkg_list "pacman -Q" "  All installed"
                ;;
            *"Explicitly"*)
                _browse_pkg_list "pacman -Qe" "  Explicit"
                ;;
            *"Dependencies only"*)
                _browse_pkg_list "pacman -Qd" "  Dependencies"
                ;;
            *"AUR / foreign"*)
                _browse_pkg_list "pacman -Qm" "  AUR / foreign"
                ;;
            *"Orphan"*)
                _browse_orphans
                ;;
            *"Upgradeable"*)
                _browse_upgradeable
                ;;
            *"Browse by group"*)
                _browse_groups
                ;;
            *"Browse by repo"*)
                _browse_repos
                ;;
            *"Search all"*)
                _search_all_pacman
                ;;
            *"Search installed"*)
                _search_installed
                ;;
            *"Check broken"*)
                _check_broken_deps
                ;;
        esac
    done
}

_browse_pkg_list() {
    local cmd="$1" prompt="$2"
    local pkgs
    pkgs=$(eval "$cmd" 2>/dev/null)
    [ -z "$pkgs" ] && { _notify "No packages found"; return; }

    local count
    count=$(echo "$pkgs" | wc -l)

    local choice
    choice=$(echo "$pkgs" | _rofi "$prompt ($count)")
    [ -z "$choice" ] && return

    local pkg_name
    pkg_name=$(echo "$choice" | awk '{print $1}')
    _pkg_detail "$pkg_name"
}

_browse_orphans() {
    local orphans
    orphans=$(pacman -Qdtq 2>/dev/null)
    if [ -z "$orphans" ]; then
        _notify "No orphan packages"
        return
    fi

    local count
    count=$(echo "$orphans" | wc -l)

    local items=()
    while IFS= read -r pkg; do
        local ver
        ver=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
        local size
        size=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Installed Size" | sed 's/.*: //')
        items+=("$pkg  $ver  [$size]")
    done <<< "$orphans"

    local choice
    choice=$(printf '%s\n' "${items[@]}" | _rofi "  Orphans ($count) — select or remove all")
    [ -z "$choice" ] && return

    local sel_pkg
    sel_pkg=$(echo "$choice" | awk '{print $1}')
    _pkg_detail "$sel_pkg"
}

_browse_upgradeable() {
    _notify "Checking for updates..."

    local h; h=$(_helper)
    local updates

    if [ "$h" = "pacman" ]; then
        updates=$(checkupdates 2>/dev/null)
    else
        updates=$($h -Qu 2>/dev/null)
    fi

    if [ -z "$updates" ]; then
        _notify "All packages are up to date"
        return
    fi

    local count
    count=$(echo "$updates" | wc -l)

    local choice
    choice=$(echo "$updates" | _rofi "  Upgradeable ($count)")
    [ -z "$choice" ] && return

    local sel_pkg
    sel_pkg=$(echo "$choice" | awk '{print $1}')
    _pkg_detail "$sel_pkg"
}

_browse_groups() {
    local groups
    groups=$(pacman -Sg 2>/dev/null | sort -u)
    [ -z "$groups" ] && { _notify "No groups found"; return; }

    local choice
    choice=$(echo "$groups" | _rofi "  Package groups")
    [ -z "$choice" ] && return

    local group="$choice"
    local pkgs
    pkgs=$(pacman -Sg "$group" 2>/dev/null | awk '{print $2}')
    [ -z "$pkgs" ] && { _notify "Group '$group' is empty"; return; }

    local count
    count=$(echo "$pkgs" | wc -l)

    local lines=()
    while IFS= read -r pkg; do
        local status=""
        _is_installed "$pkg" && status="  [installed]"
        lines+=("${pkg}${status}")
    done <<< "$pkgs"

    local sel
    sel=$(printf '%s\n' "${lines[@]}" | _rofi "  Group: $group ($count)")
    [ -z "$sel" ] && return

    local sel_pkg
    sel_pkg=$(echo "$sel" | awk '{print $1}')
    _pkg_detail "$sel_pkg"
}

_browse_repos() {
    local repos
    repos=$(pacman-conf --repo-list 2>/dev/null)
    [ -z "$repos" ] && repos=$(grep '^\[' /etc/pacman.conf 2>/dev/null | grep -v '^\[options' | tr -d '[]')

    local items=()
    while IFS= read -r repo; do
        [ -z "$repo" ] && continue
        local count
        count=$(pacman -Sl "$repo" 2>/dev/null | wc -l)
        items+=("$repo  ($count packages)")
    done <<< "$repos"

    local choice
    choice=$(printf '%s\n' "${items[@]}" | _rofi "  Repositories")
    [ -z "$choice" ] && return

    local repo
    repo=$(echo "$choice" | awk '{print $1}')

    local pkgs
    pkgs=$(pacman -Sl "$repo" 2>/dev/null)
    [ -z "$pkgs" ] && { _notify "Repository '$repo' is empty"; return; }

    local lines=()
    while IFS= read -r line; do
        local r name ver status
        r=$(echo "$line" | awk '{print $1}')
        name=$(echo "$line" | awk '{print $2}')
        ver=$(echo "$line" | awk '{print $3}')
        status=""
        [[ "$line" == *"[installed]"* ]] && status="  [installed]"
        lines+=("${name}  ${ver}${status}")
    done <<< "$pkgs"

    local sel
    sel=$(printf '%s\n' "${lines[@]}" | _rofi "  [$repo]")
    [ -z "$sel" ] && return

    local sel_pkg
    sel_pkg=$(echo "$sel" | awk '{print $1}')
    _pkg_detail "$sel_pkg"
}

_search_all_pacman() {
    local query
    query=$(echo "" | _rofi "  Search all packages")
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

    local lines=()
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

        lines+=("[${repo}] ${pkg_name}  ${ver}  ${desc:0:40}${status}")
    done <<< "$results"

    [ ${#lines[@]} -eq 0 ] && { _notify "Nothing found"; return; }

    local choice
    choice=$(printf '%s\n' "${lines[@]}" | head -150 | _rofi "  Results ($query)")
    [ -z "$choice" ] && return

    local sel_pkg
    sel_pkg=$(echo "$choice" | awk '{print $2}')
    _pkg_detail "$sel_pkg"
}

_search_installed() {
    local query
    query=$(echo "" | _rofi "  Search installed")
    [ -z "$query" ] && return

    local pkgs
    pkgs=$(pacman -Q 2>/dev/null | grep -i "$query")
    [ -z "$pkgs" ] && { _notify "Not found in installed packages"; return; }

    local choice
    choice=$(echo "$pkgs" | _rofi "  Installed: $query")
    [ -z "$choice" ] && return

    local pkg_name
    pkg_name=$(echo "$choice" | awk '{print $1}')
    _pkg_detail "$pkg_name"
}

_check_broken_deps() {
    _notify "Checking for broken dependencies..."

    local broken
    broken=$(pacman -Dk 2>&1 | grep -v ": all dependencies satisfied")

    if [ -z "$broken" ]; then
        _notify "No broken dependencies found!"
        return
    fi

    local count
    count=$(echo "$broken" | wc -l)
    echo "$broken" | _rofi "  Broken deps ($count issues)"
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
                _run_in_term "sudo pacman -Rns \$(pacman -Qdtq)" && \
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

    if [ -f "$stoa_dir/theme/pacman-hooks/stoa-theme-enforce" ]; then
        sudo mkdir -p /etc/pacman.d/hooks
        sudo cp "$stoa_dir/theme/pacman-hooks/stoa-theme-enforce" "$script"
        sudo chmod +x "$script"
        sudo cp "$stoa_dir/theme/pacman-hooks/stoa-theme.hook" "$hook"
    else
        # Inline fallback
        sudo mkdir -p /etc/pacman.d/hooks
        sudo tee "$script" > /dev/null <<'ENFORCE'
#!/bin/bash
U="${SUDO_USER:-$USER}"; H=$(eval echo "~$U")
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

    _notify "Extracting .rpm package..."
    _run_in_term "cd /tmp && mkdir -p stoa-rpm-extract && cd stoa-rpm-extract && rpmextract.sh '$path' && echo '── Contents extracted to /tmp/stoa-rpm-extract ──' && ls -la && echo && echo 'Install manually: sudo cp -r usr/ /usr/' && echo 'Or convert first: install debtap, then alien -d file.rpm, then debtap file.deb'"
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
#   LANGUAGE PACKAGE MANAGERS
# ══════════════════════════════════════════════════════════════

# Generic handler for language package managers
# Usage: _lang_pm_action <name> <cmd> <search_cmd> <install_cmd> <remove_cmd> <list_cmd> <info_cmd> <update_cmd>

_lang_detect_available() {
    local items=()
    command -v pip    &>/dev/null && items+=("  Python (pip)")
    command -v pipx   &>/dev/null && items+=("  Python apps (pipx)")
    command -v npm    &>/dev/null && items+=("  Node.js (npm)")
    command -v yarn   &>/dev/null && items+=("  Node.js (yarn)")
    command -v pnpm   &>/dev/null && items+=("  Node.js (pnpm)")
    command -v cargo  &>/dev/null && items+=("  Rust (cargo)")
    command -v gem    &>/dev/null && items+=("  Ruby (gem)")
    command -v go     &>/dev/null && items+=("  Go (go install)")
    command -v composer &>/dev/null && items+=("  PHP (composer)")
    command -v dotnet &>/dev/null && items+=("  .NET (dotnet/nuget)")
    command -v luarocks &>/dev/null && items+=("  Lua (luarocks)")
    command -v cpan   &>/dev/null && items+=("  Perl (cpan)")
    command -v ghcup  &>/dev/null && items+=("  Haskell (cabal/stack)")
    command -v cabal  &>/dev/null && [ ${#items[@]} -gt 0 ] || true
    command -v julia  &>/dev/null && items+=("  Julia (Pkg)")
    command -v R      &>/dev/null && items+=("  R (CRAN)")
    printf '%s\n' "${items[@]}"
}

_lang_pip() {
    while true; do
        local count
        count=$(pip list 2>/dev/null | tail -n +3 | wc -l)

        local choice
        choice=$(_rofi_list "  Python pip ($count pkgs)" \
            "  Search PyPI" \
            "  Installed packages" \
            "  Outdated packages" \
            "  Install package" \
            "  Uninstall package" \
            "  Package info" \
            "  Show dependencies" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Search*)
                local q; q=$(echo "" | _rofi "  Search PyPI")
                [ -z "$q" ] && continue
                _notify "Searching PyPI..."
                local results
                results=$(pip index versions "$q" 2>/dev/null || pip search "$q" 2>/dev/null || echo "Use: pip install $q (PyPI search API may be disabled)")
                echo "$results" | _rofi "  PyPI: $q"
                ;;
            *"Installed packages"*)
                local pkgs
                pkgs=$(pip list 2>/dev/null)
                [ -z "$pkgs" ] && { _notify "No pip packages"; continue; }
                local sel
                sel=$(echo "$pkgs" | _rofi "  pip list")
                [ -z "$sel" ] && continue
                local pkg_name; pkg_name=$(echo "$sel" | awk '{print $1}')
                pip show "$pkg_name" 2>/dev/null | _rofi "  pip: $pkg_name"
                ;;
            *Outdated*)
                _notify "Checking outdated..."
                local outdated
                outdated=$(pip list --outdated 2>/dev/null)
                [ -z "$outdated" ] && { _notify "All up to date"; continue; }
                local sel
                sel=$(echo "$outdated" | _rofi "  pip outdated")
                [ -z "$sel" ] && continue
                local pkg_name; pkg_name=$(echo "$sel" | awk '{print $1}')
                _confirm "Upgrade $pkg_name?" && _run_in_term "pip install --upgrade $pkg_name"
                ;;
            *"Install package"*)
                local pkg; pkg=$(echo "" | _rofi "  pip install")
                [ -z "$pkg" ] && continue
                _run_in_term "pip install $pkg"
                ;;
            *Uninstall*)
                local pkgs
                pkgs=$(pip list --format=columns 2>/dev/null | tail -n +3)
                local sel
                sel=$(echo "$pkgs" | _rofi "  pip uninstall")
                [ -z "$sel" ] && continue
                local pkg_name; pkg_name=$(echo "$sel" | awk '{print $1}')
                _confirm "Uninstall $pkg_name?" && _run_in_term "pip uninstall $pkg_name"
                ;;
            *"Package info"*)
                local pkg; pkg=$(echo "" | _rofi "  pip show (package name)")
                [ -z "$pkg" ] && continue
                pip show "$pkg" 2>/dev/null | _rofi "  pip: $pkg"
                ;;
            *dependencies*)
                local pkg; pkg=$(echo "" | _rofi "  Show deps for")
                [ -z "$pkg" ] && continue
                local info
                info=$(pip show "$pkg" 2>/dev/null)
                local deps
                deps=$(echo "$info" | grep "^Requires:" | sed 's/Requires: //')
                local rdeps
                rdeps=$(echo "$info" | grep "^Required-by:" | sed 's/Required-by: //')
                printf '%s\n' \
                    "── $pkg depends on ──" \
                    "${deps:-  (none)}" \
                    "" \
                    "── Required by ──" \
                    "${rdeps:-  (none)}" \
                | _rofi "  pip deps: $pkg"
                ;;
        esac
    done
}

_lang_pipx() {
    while true; do
        local choice
        choice=$(_rofi_list "  Python pipx" \
            "  Install app" \
            "  Installed apps" \
            "  Upgrade all" \
            "  Uninstall app" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *"Install app"*)
                local pkg; pkg=$(echo "" | _rofi "  pipx install")
                [ -z "$pkg" ] && continue
                _run_in_term "pipx install $pkg"
                ;;
            *"Installed"*)
                local apps
                apps=$(pipx list --short 2>/dev/null)
                echo "${apps:-No apps installed}" | _rofi "  pipx apps"
                ;;
            *Upgrade*)
                _run_in_term "pipx upgrade-all"
                _notify "pipx apps upgraded"
                ;;
            *Uninstall*)
                local apps
                apps=$(pipx list --short 2>/dev/null | awk '{print $1}')
                [ -z "$apps" ] && { _notify "No pipx apps"; continue; }
                local sel; sel=$(echo "$apps" | _rofi "  pipx uninstall")
                [ -z "$sel" ] && continue
                _confirm "Uninstall $sel?" && _run_in_term "pipx uninstall $sel"
                ;;
        esac
    done
}

_lang_npm() {
    while true; do
        local count
        count=$(npm list -g --depth=0 2>/dev/null | tail -n +2 | wc -l)

        local choice
        choice=$(_rofi_list "  npm ($count global pkgs)" \
            "  Search npm" \
            "  Global packages" \
            "  Outdated (global)" \
            "  Install global" \
            "  Uninstall global" \
            "  Package info" \
            "  Show dependencies" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Search*)
                local q; q=$(echo "" | _rofi "  Search npm")
                [ -z "$q" ] && continue
                _notify "Searching npm..."
                npm search "$q" 2>/dev/null | head -30 | _rofi "  npm: $q"
                ;;
            *"Global packages"*)
                npm list -g --depth=0 2>/dev/null | _rofi "  npm global"
                ;;
            *Outdated*)
                _notify "Checking..."
                local outdated
                outdated=$(npm outdated -g 2>/dev/null)
                echo "${outdated:-All up to date}" | _rofi "  npm outdated"
                ;;
            *"Install global"*)
                local pkg; pkg=$(echo "" | _rofi "  npm install -g")
                [ -z "$pkg" ] && continue
                _run_in_term "npm install -g $pkg"
                ;;
            *Uninstall*)
                local pkgs
                pkgs=$(npm list -g --depth=0 --parseable 2>/dev/null | tail -n +2 | xargs -I{} basename {})
                [ -z "$pkgs" ] && { _notify "No global packages"; continue; }
                local sel; sel=$(echo "$pkgs" | _rofi "  npm uninstall -g")
                [ -z "$sel" ] && continue
                _confirm "Uninstall $sel?" && _run_in_term "npm uninstall -g $sel"
                ;;
            *"Package info"*)
                local pkg; pkg=$(echo "" | _rofi "  npm info")
                [ -z "$pkg" ] && continue
                npm info "$pkg" 2>/dev/null | head -40 | _rofi "  npm: $pkg"
                ;;
            *dependencies*)
                local pkg; pkg=$(echo "" | _rofi "  Show deps for")
                [ -z "$pkg" ] && continue
                npm info "$pkg" dependencies 2>/dev/null | _rofi "  npm deps: $pkg"
                ;;
        esac
    done
}

_lang_yarn() {
    while true; do
        local choice
        choice=$(_rofi_list "  yarn" \
            "  Global packages" \
            "  Install global" \
            "  Remove global" \
            "  Package info" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *"Global"*)
                yarn global list 2>/dev/null | _rofi "  yarn global"
                ;;
            *Install*)
                local pkg; pkg=$(echo "" | _rofi "  yarn global add")
                [ -z "$pkg" ] && continue
                _run_in_term "yarn global add $pkg"
                ;;
            *Remove*)
                local pkg; pkg=$(echo "" | _rofi "  yarn global remove")
                [ -z "$pkg" ] && continue
                _confirm "Remove $pkg?" && _run_in_term "yarn global remove $pkg"
                ;;
            *info*)
                local pkg; pkg=$(echo "" | _rofi "  yarn info")
                [ -z "$pkg" ] && continue
                yarn info "$pkg" 2>/dev/null | head -40 | _rofi "  yarn: $pkg"
                ;;
        esac
    done
}

_lang_pnpm() {
    while true; do
        local choice
        choice=$(_rofi_list "  pnpm" \
            "  Global packages" \
            "  Install global" \
            "  Remove global" \
            "  Outdated (global)" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *"Global"*)
                pnpm list -g 2>/dev/null | _rofi "  pnpm global"
                ;;
            *Install*)
                local pkg; pkg=$(echo "" | _rofi "  pnpm add -g")
                [ -z "$pkg" ] && continue
                _run_in_term "pnpm add -g $pkg"
                ;;
            *Remove*)
                local pkg; pkg=$(echo "" | _rofi "  pnpm remove -g")
                [ -z "$pkg" ] && continue
                _confirm "Remove $pkg?" && _run_in_term "pnpm remove -g $pkg"
                ;;
            *Outdated*)
                pnpm outdated -g 2>/dev/null | _rofi "  pnpm outdated"
                ;;
        esac
    done
}

_lang_cargo() {
    while true; do
        local count=0
        [ -d "$HOME/.cargo/bin" ] && count=$(ls "$HOME/.cargo/bin" 2>/dev/null | wc -l)

        local choice
        choice=$(_rofi_list "  Rust cargo ($count bins)" \
            "  Search crates.io" \
            "  Installed binaries" \
            "  Install crate" \
            "  Uninstall crate" \
            "  Crate info" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Search*)
                local q; q=$(echo "" | _rofi "  Search crates.io")
                [ -z "$q" ] && continue
                _notify "Searching crates.io..."
                cargo search "$q" 2>/dev/null | head -30 | _rofi "  crates: $q"
                ;;
            *"Installed"*)
                if command -v cargo-install-update &>/dev/null; then
                    cargo install --list 2>/dev/null | _rofi "  cargo installed"
                else
                    cargo install --list 2>/dev/null | _rofi "  cargo installed"
                fi
                ;;
            *"Install crate"*)
                local pkg; pkg=$(echo "" | _rofi "  cargo install")
                [ -z "$pkg" ] && continue
                _run_in_term "cargo install $pkg"
                ;;
            *Uninstall*)
                local bins
                bins=$(cargo install --list 2>/dev/null | grep -v '^ ' | sed 's/ .*//')
                [ -z "$bins" ] && { _notify "No installed crates"; continue; }
                local sel; sel=$(echo "$bins" | _rofi "  cargo uninstall")
                [ -z "$sel" ] && continue
                _confirm "Uninstall $sel?" && _run_in_term "cargo uninstall $sel"
                ;;
            *info*)
                local pkg; pkg=$(echo "" | _rofi "  Crate name")
                [ -z "$pkg" ] && continue
                cargo search "$pkg" 2>/dev/null | head -5 | _rofi "  $pkg"
                ;;
        esac
    done
}

_lang_gem() {
    while true; do
        local count
        count=$(gem list --no-versions 2>/dev/null | wc -l)

        local choice
        choice=$(_rofi_list "  Ruby gem ($count gems)" \
            "  Search RubyGems" \
            "  Installed gems" \
            "  Outdated gems" \
            "  Install gem" \
            "  Uninstall gem" \
            "  Gem info" \
            "  Gem dependencies" \
            "  Clean old versions" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Search*)
                local q; q=$(echo "" | _rofi "  Search RubyGems")
                [ -z "$q" ] && continue
                _notify "Searching..."
                gem search "$q" 2>/dev/null | head -40 | _rofi "  gems: $q"
                ;;
            *"Installed"*)
                gem list 2>/dev/null | _rofi "  gem list"
                ;;
            *Outdated*)
                _notify "Checking..."
                gem outdated 2>/dev/null | _rofi "  gem outdated"
                ;;
            *"Install gem"*)
                local pkg; pkg=$(echo "" | _rofi "  gem install")
                [ -z "$pkg" ] && continue
                _run_in_term "gem install $pkg"
                ;;
            *Uninstall*)
                local gems
                gems=$(gem list --no-versions 2>/dev/null)
                local sel; sel=$(echo "$gems" | _rofi "  gem uninstall")
                [ -z "$sel" ] && continue
                _confirm "Uninstall $sel?" && _run_in_term "gem uninstall $sel"
                ;;
            *"Gem info"*)
                local pkg; pkg=$(echo "" | _rofi "  gem info")
                [ -z "$pkg" ] && continue
                gem info "$pkg" 2>/dev/null | _rofi "  gem: $pkg"
                ;;
            *dependencies*)
                local pkg; pkg=$(echo "" | _rofi "  gem dependency")
                [ -z "$pkg" ] && continue
                gem dependency "$pkg" 2>/dev/null | _rofi "  gem deps: $pkg"
                ;;
            *Clean*)
                _confirm "Clean old gem versions?" && _run_in_term "gem cleanup"
                ;;
        esac
    done
}

_lang_go() {
    while true; do
        local count=0
        [ -d "$(go env GOPATH 2>/dev/null)/bin" ] && count=$(ls "$(go env GOPATH)/bin" 2>/dev/null | wc -l)

        local choice
        choice=$(_rofi_list "  Go ($count bins)" \
            "  Installed binaries" \
            "  Install module" \
            "  Module info" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *"Installed"*)
                local gobin
                gobin=$(go env GOPATH 2>/dev/null)/bin
                [ -d "$gobin" ] && ls "$gobin" 2>/dev/null | _rofi "  go binaries" || _notify "No Go binaries"
                ;;
            *"Install module"*)
                local pkg; pkg=$(echo "" | _rofi "  go install (full path@version)")
                [ -z "$pkg" ] && continue
                _run_in_term "go install $pkg"
                ;;
            *info*)
                local pkg; pkg=$(echo "" | _rofi "  Module path")
                [ -z "$pkg" ] && continue
                _run_in_term "go doc $pkg 2>&1 | head -50; echo; echo 'Press Enter...'; read"
                ;;
        esac
    done
}

_lang_composer() {
    while true; do
        local choice
        choice=$(_rofi_list "  PHP Composer" \
            "  Search Packagist" \
            "  Global packages" \
            "  Install global" \
            "  Remove global" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Search*)
                local q; q=$(echo "" | _rofi "  Search Packagist")
                [ -z "$q" ] && continue
                _notify "Searching..."
                composer search "$q" 2>/dev/null | head -30 | _rofi "  packagist: $q"
                ;;
            *"Global"*)
                composer global show 2>/dev/null | _rofi "  composer global"
                ;;
            *"Install"*)
                local pkg; pkg=$(echo "" | _rofi "  composer global require")
                [ -z "$pkg" ] && continue
                _run_in_term "composer global require $pkg"
                ;;
            *Remove*)
                local pkg; pkg=$(echo "" | _rofi "  composer global remove")
                [ -z "$pkg" ] && continue
                _confirm "Remove $pkg?" && _run_in_term "composer global remove $pkg"
                ;;
        esac
    done
}

_lang_dotnet() {
    while true; do
        local choice
        choice=$(_rofi_list "  .NET / NuGet" \
            "  Search NuGet" \
            "  Global tools" \
            "  Install global tool" \
            "  Uninstall global tool" \
            "  Installed SDKs" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Search*)
                local q; q=$(echo "" | _rofi "  Search NuGet")
                [ -z "$q" ] && continue
                _notify "Searching..."
                dotnet tool search "$q" 2>/dev/null | head -30 | _rofi "  nuget: $q"
                ;;
            *"Global tools"*)
                dotnet tool list -g 2>/dev/null | _rofi "  dotnet global tools"
                ;;
            *"Install global"*)
                local pkg; pkg=$(echo "" | _rofi "  dotnet tool install -g")
                [ -z "$pkg" ] && continue
                _run_in_term "dotnet tool install -g $pkg"
                ;;
            *Uninstall*)
                local tools
                tools=$(dotnet tool list -g 2>/dev/null | tail -n +3 | awk '{print $1}')
                local sel; sel=$(echo "$tools" | _rofi "  dotnet uninstall")
                [ -z "$sel" ] && continue
                _confirm "Uninstall $sel?" && _run_in_term "dotnet tool uninstall -g $sel"
                ;;
            *SDKs*)
                dotnet --list-sdks 2>/dev/null | _rofi "  .NET SDKs"
                ;;
        esac
    done
}

_lang_luarocks() {
    while true; do
        local choice
        choice=$(_rofi_list "  Lua (luarocks)" \
            "  Search" \
            "  Installed" \
            "  Install" \
            "  Remove" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Search*)
                local q; q=$(echo "" | _rofi "  Search luarocks")
                [ -z "$q" ] && continue
                luarocks search "$q" 2>/dev/null | head -30 | _rofi "  luarocks: $q"
                ;;
            *Installed*)
                luarocks list 2>/dev/null | _rofi "  luarocks installed"
                ;;
            *Install*)
                local pkg; pkg=$(echo "" | _rofi "  luarocks install")
                [ -z "$pkg" ] && continue
                _run_in_term "luarocks install $pkg"
                ;;
            *Remove*)
                local pkg; pkg=$(echo "" | _rofi "  luarocks remove")
                [ -z "$pkg" ] && continue
                _confirm "Remove $pkg?" && _run_in_term "luarocks remove $pkg"
                ;;
        esac
    done
}

_lang_cpan() {
    while true; do
        local choice
        choice=$(_rofi_list "  Perl (CPAN)" \
            "  Installed modules" \
            "  Install module" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Installed*)
                perldoc -t perllocal 2>/dev/null | head -80 | _rofi "  perl modules" || cpan -l 2>/dev/null | head -80 | _rofi "  cpan modules"
                ;;
            *Install*)
                local pkg; pkg=$(echo "" | _rofi "  cpan install")
                [ -z "$pkg" ] && continue
                _run_in_term "cpan install $pkg"
                ;;
        esac
    done
}

_lang_haskell() {
    while true; do
        local choice
        choice=$(_rofi_list "  Haskell" \
            "  GHCup toolchain" \
            "  Cabal installed" \
            "  Cabal install" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *GHCup*)
                ghcup list 2>/dev/null | _rofi "  ghcup toolchain"
                ;;
            *"Cabal installed"*)
                cabal list --installed 2>/dev/null | head -60 | _rofi "  cabal installed"
                ;;
            *"Cabal install"*)
                local pkg; pkg=$(echo "" | _rofi "  cabal install")
                [ -z "$pkg" ] && continue
                _run_in_term "cabal install $pkg"
                ;;
        esac
    done
}

_lang_julia() {
    while true; do
        local choice
        choice=$(_rofi_list "  Julia (Pkg)" \
            "  Installed packages" \
            "  Install package" \
            "  Remove package" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Installed*)
                julia -e 'using Pkg; Pkg.status()' 2>/dev/null | _rofi "  julia packages"
                ;;
            *Install*)
                local pkg; pkg=$(echo "" | _rofi "  Julia Pkg.add")
                [ -z "$pkg" ] && continue
                _run_in_term "julia -e 'using Pkg; Pkg.add(\"$pkg\")'"
                ;;
            *Remove*)
                local pkg; pkg=$(echo "" | _rofi "  Julia Pkg.rm")
                [ -z "$pkg" ] && continue
                _confirm "Remove $pkg?" && _run_in_term "julia -e 'using Pkg; Pkg.rm(\"$pkg\")'"
                ;;
        esac
    done
}

_lang_r() {
    while true; do
        local choice
        choice=$(_rofi_list "  R (CRAN)" \
            "  Installed packages" \
            "  Install package" \
            "  Remove package" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *Installed*)
                R -e 'installed.packages()[,"Package"]' 2>/dev/null | _rofi "  R packages"
                ;;
            *Install*)
                local pkg; pkg=$(echo "" | _rofi "  install.packages")
                [ -z "$pkg" ] && continue
                _run_in_term "R -e 'install.packages(\"$pkg\", repos=\"https://cloud.r-project.org\")'"
                ;;
            *Remove*)
                local pkg; pkg=$(echo "" | _rofi "  remove.packages")
                [ -z "$pkg" ] && continue
                _confirm "Remove $pkg?" && _run_in_term "R -e 'remove.packages(\"$pkg\")'"
                ;;
        esac
    done
}

menu_developer() {
    while true; do
        # Count detected runtimes
        local rt_count=0
        command -v pip       &>/dev/null && ((rt_count++))
        command -v pipx      &>/dev/null && ((rt_count++))
        command -v npm       &>/dev/null && ((rt_count++))
        command -v yarn      &>/dev/null && ((rt_count++))
        command -v pnpm      &>/dev/null && ((rt_count++))
        command -v cargo     &>/dev/null && ((rt_count++))
        command -v gem       &>/dev/null && ((rt_count++))
        command -v go        &>/dev/null && ((rt_count++))
        command -v composer  &>/dev/null && ((rt_count++))
        command -v dotnet    &>/dev/null && ((rt_count++))
        command -v luarocks  &>/dev/null && ((rt_count++))
        command -v cpan      &>/dev/null && ((rt_count++))
        command -v ghcup     &>/dev/null && ((rt_count++))
        command -v julia     &>/dev/null && ((rt_count++))
        command -v R         &>/dev/null && ((rt_count++))

        local choice
        choice=$(_rofi_list "  Developer tools" \
            "  Language packages ($rt_count runtimes)" \
            "  Base development packages" \
            "─────────────────────" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *"Language"*)
                menu_lang_packages
                ;;
            *"Base dev"*)
                # Show base-devel and common dev tool groups
                local dev_items=()
                local groups=("base-devel")
                for g in "${groups[@]}"; do
                    local count
                    count=$(pacman -Sg "$g" 2>/dev/null | wc -l)
                    local installed=0
                    while IFS= read -r line; do
                        local p="${line#* }"
                        _is_installed "$p" && ((installed++))
                    done <<< "$(pacman -Sg "$g" 2>/dev/null)"
                    dev_items+=("  $g  ($installed/$count installed)")
                done

                # Common dev tools check
                local dev_tools=("git" "cmake" "meson" "ninja" "gdb" "valgrind" "strace" "docker" "podman")
                dev_items+=("─────────────────────")
                for tool in "${dev_tools[@]}"; do
                    local status=""
                    _is_installed "$tool" && status="  [installed]" || status="  [not installed]"
                    dev_items+=("  $tool${status}")
                done

                local sel
                sel=$(_rofi_list "  Dev packages" "${dev_items[@]}" "  Back")
                [ -z "$sel" ] || [[ "$sel" == *Back* ]] && continue

                local sel_name
                sel_name=$(echo "$sel" | awk '{print $1}')

                # Check if it's a group
                if pacman -Sg "$sel_name" &>/dev/null; then
                    local group_pkgs
                    group_pkgs=$(pacman -Sg "$sel_name" 2>/dev/null | awk '{print $2}')
                    local lines=()
                    while IFS= read -r p; do
                        local st=""
                        _is_installed "$p" && st="  [installed]"
                        lines+=("${p}${st}")
                    done <<< "$group_pkgs"
                    local pkg_sel
                    pkg_sel=$(printf '%s\n' "${lines[@]}" | _rofi "  $sel_name")
                    [ -z "$pkg_sel" ] && continue
                    local pkg_name; pkg_name=$(echo "$pkg_sel" | awk '{print $1}')
                    _pkg_detail "$pkg_name"
                else
                    _pkg_detail "$sel_name"
                fi
                ;;
        esac
    done
}

menu_lang_packages() {
    while true; do
        local available
        available=$(_lang_detect_available)

        if [ -z "$available" ]; then
            _notify "No language runtimes detected"
            return
        fi

        local choice
        choice=$(echo "$available" | {
            cat
            echo "─────────────────────"
            echo "  Back"
        } | "${ROFI[@]}" -p "  Language packages")
        [ -z "$choice" ] || [[ "$choice" == *Back* ]] && return

        case "$choice" in
            *"Python (pip)"*)    _lang_pip ;;
            *"pipx"*)            _lang_pipx ;;
            *"npm"*)             _lang_npm ;;
            *"yarn"*)            _lang_yarn ;;
            *"pnpm"*)            _lang_pnpm ;;
            *"cargo"*)           _lang_cargo ;;
            *"gem"*)             _lang_gem ;;
            *"Go"*)              _lang_go ;;
            *"composer"*)        _lang_composer ;;
            *".NET"*)            _lang_dotnet ;;
            *"luarocks"*)        _lang_luarocks ;;
            *"cpan"*|*"Perl"*)   _lang_cpan ;;
            *"Haskell"*)         _lang_haskell ;;
            *"Julia"*)           _lang_julia ;;
            *"R (CRAN)"*)        _lang_r ;;
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
            "  Search & install" \
            "  Package browser" \
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
            *"Search & install"*)  _search_install ;;
            *"Package browser"*)   _installed ;;
            *Update*)              _update ;;
            *Cleanup*)             _cleanup ;;
            *info*)                _stats ;;
            *"Flatpak manager"*)   menu_flatpak ;;
            *"Snap manager"*)      menu_snap ;;
            *"AppImage manager"*)  menu_appimage ;;
            *DEB*)                 menu_deb_rpm ;;
            *"Developer tools"*)   menu_developer ;;
            *auto-theme*)          _setup_hook ;;
            *Re-apply*)            _apply_stoa_theme; _notify "Stoa theme applied" ;;
            *"AUR helper"*)        _install_aur_helper ;;
        esac
    done
}

main
