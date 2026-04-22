#!/bin/bash
# Stoa Store — pacman/AUR search + Synaptic-style package detail.

# Parse `pacman -Ss` style two-line records into tagged lines.
# $1 = raw output, $2 = filter: "" | "arch" | "aur" | "all"
_fmt_pacman_results() {
    local raw="$1" filter="${2:-all}"
    [ -z "$raw" ] && return
    while IFS= read -r line1; do
        IFS= read -r line2 || true
        local repo_pkg ver desc
        repo_pkg=$(echo "$line1" | awk '{print $1}')
        ver=$(echo "$line1" | awk '{print $2}')
        desc=$(echo "$line2" | sed 's/^[[:space:]]*//')
        local pkg_name="${repo_pkg#*/}" repo="${repo_pkg%/*}"
        local tag="[arch]"; [[ "$repo" == "aur" ]] && tag="[AUR]"
        case "$filter" in
            arch) [[ "$repo" == "aur" ]] && continue ;;
            aur)  [[ "$repo" != "aur" ]] && continue ;;
        esac
        local status=""; _is_installed "$pkg_name" && status="  [installed]"
        echo "${tag} ${pkg_name}  ${ver}  ${desc:0:45}${status}"
    done <<< "$raw"
}

_search_pacman() {
    local h; h=$(_helper)
    local out
    [ "$h" = "pacman" ] && out=$(pacman -Ss "$1" 2>/dev/null) || out=$($h -Ss "$1" 2>/dev/null)
    _fmt_pacman_results "$out" all
}

_search_flatpak_results() {
    command -v flatpak &>/dev/null || return
    local results; results=$(flatpak search "$1" --columns=name,application,description 2>/dev/null)
    [ -z "$results" ] && return
    while IFS=$'\t' read -r name app_id desc; do
        [ -z "$name" ] && continue
        local status=""; flatpak info "$app_id" &>/dev/null && status="  [installed]"
        echo "[flatpak] ${name}  ${app_id}  ${desc:0:35}${status}"
    done <<< "$results"
}

_search_snap_results() {
    command -v snap &>/dev/null || return
    local results; results=$(snap find "$1" 2>/dev/null | tail -n +2)
    [ -z "$results" ] && return
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local name ver summary
        name=$(echo "$line" | awk '{print $1}')
        ver=$(echo "$line" | awk '{print $2}')
        summary=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
        local status=""; snap list "$name" &>/dev/null 2>&1 && status="  [installed]"
        echo "[snap] ${name}  ${ver}  ${summary:0:40}${status}"
    done <<< "$results"
}

_pkg_detail() {
    local pkg="$1" h; h=$(_helper)
    while true; do
        local installed=false; _is_installed "$pkg" && installed=true
        local status_tag="not installed" install_reason="" ver=""
        if $installed; then
            install_reason=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Install Reason" | sed 's/.*: //')
            [[ "$install_reason" == *"dependency"* ]] && status_tag="dependency" || status_tag="explicit"
            ver=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
        else
            ver=$(pacman -Si "$pkg" 2>/dev/null | grep "^Version" | head -1 | sed 's/.*: //')
        fi

        local items=("  Status: $status_tag  $ver" "─────────────────────"
                     "  Full info" "  Dependencies" "  Required by (reverse deps)"
                     "  Optional dependencies" "  Dependency tree"
                     "  Provides / Conflicts / Replaces")
        if $installed; then
            items+=("  Installed files" "  Changelog / install script"
                    "─────────────────────"
                    "  Reinstall" "  Remove (keep deps)" "  Complete removal (pkg + deps)")
            [[ "$install_reason" == *"dependency"* ]] \
                && items+=("  Mark as explicit") \
                || items+=("  Mark as dependency")
        else
            items+=("─────────────────────"
                    "  Install (with dependencies)" "  Install as dependency")
        fi
        items+=("─────────────────────" "  Back")

        local action; action=$(_rofi_list "  $pkg" "${items[@]}")
        [ -z "$action" ] || [[ "$action" == *Back* ]] && return

        case "$action" in
            *"Full info"*)
                if $installed; then pacman -Qi "$pkg" 2>/dev/null | _rofi "  $pkg info"
                else pacman -Si "$pkg" 2>/dev/null | _rofi "  $pkg info"; fi ;;
            *"Dependencies"*)     _show_deps "$pkg" "$installed" ;;
            *"Required by"*)      _show_reverse_deps "$pkg" "$installed" ;;
            *"Optional dep"*)     _show_optional_deps "$pkg" "$installed" ;;
            *"Dependency tree"*)  _show_dep_tree "$pkg" ;;
            *"Provides"*)         _show_provides_conflicts "$pkg" "$installed" ;;
            *"Installed files"*)
                pacman -Ql "$pkg" 2>/dev/null | awk '{print $2}' | _rofi "  $pkg files" ;;
            *"Changelog"*)
                if pacman -Ql "$pkg" 2>/dev/null | grep -qi changelog; then
                    local cl; cl=$(pacman -Ql "$pkg" 2>/dev/null | grep -i changelog | head -1 | awk '{print $2}')
                    [ -f "$cl" ] && head -80 "$cl" | _rofi "  $pkg changelog" \
                                || echo "No changelog found" | _rofi "  $pkg"
                else
                    echo "No changelog or install script found" | _rofi "  $pkg"
                fi ;;
            *"Reinstall"*)         _run_in_term "sudo pacman -S $pkg"; _apply_stoa_theme ;;
            *"Remove (keep"*)
                _confirm "Remove $pkg (keep dependencies)?" && _run_in_term "sudo pacman -R $pkg" ;;
            *"Complete removal"*)  _complete_removal "$pkg" ;;
            *"Mark as explicit"*)
                sudo pacman -D --asexplicit "$pkg" 2>/dev/null
                _notify "$pkg marked as explicitly installed" ;;
            *"Mark as dependency"*)
                _confirm "Mark $pkg as dependency? (may be removed as orphan)" || continue
                sudo pacman -D --asdeps "$pkg" 2>/dev/null
                _notify "$pkg marked as dependency" ;;
            *"Install as dep"*)
                _confirm "Install $pkg as dependency?" || continue
                [ "$h" = "pacman" ] && _run_in_term "sudo pacman -S --asdeps $pkg" \
                                    || _run_in_term "$h -S --asdeps $pkg"
                _apply_stoa_theme ;;
            *"Install"*)           _install_with_deps_preview "$pkg" ;;
        esac
    done
}

_install_with_deps_preview() {
    local pkg="$1" h; h=$(_helper)
    local deps_info; deps_info=$(pacman -Si "$pkg" 2>/dev/null | grep "^Depends On" | sed 's/.*: //')

    local new_deps=() already_installed=()
    if [ -n "$deps_info" ] && [ "$deps_info" != "None" ]; then
        for dep in $deps_info; do
            local dep_name="${dep%%[><=]*}"
            _is_installed "$dep_name" \
                && already_installed+=("  $dep_name  [already installed]") \
                || new_deps+=("  $dep_name  [will install]")
        done
    fi

    local lines=("Package: $pkg" "")
    [ ${#new_deps[@]} -gt 0 ] && lines+=("── New dependencies (${#new_deps[@]}) ──" "${new_deps[@]}")
    [ ${#already_installed[@]} -gt 0 ] && lines+=("── Already satisfied (${#already_installed[@]}) ──" "${already_installed[@]}")
    [ ${#new_deps[@]} -eq 0 ] && [ ${#already_installed[@]} -eq 0 ] && lines+=("No dependencies required")
    lines+=("" "  Confirm install" "  Cancel")

    local confirm; confirm=$(printf '%s\n' "${lines[@]}" | _rofi "  Install $pkg")
    [[ "$confirm" == *"Confirm"* ]] || return

    [ "$h" = "pacman" ] && _run_in_term "sudo pacman -S --needed $pkg" \
                        || _run_in_term "$h -S --needed $pkg"
    _is_installed "$pkg" && _apply_stoa_theme && _notify "$pkg installed"
}

_complete_removal() {
    local pkg="$1"
    local deps; deps=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Depends On" | sed 's/.*: //')
    local safe_to_remove=() shared_deps=() conflict_details=()

    if [ -n "$deps" ] && [ "$deps" != "None" ]; then
        for dep in $deps; do
            local dep_name="${dep%%[><=]*}"
            _is_installed "$dep_name" || continue
            local rdeps; rdeps=$(pacman -Qi "$dep_name" 2>/dev/null | grep "^Required By" | sed 's/.*: //')
            if [ -z "$rdeps" ] || [ "$rdeps" = "None" ]; then
                safe_to_remove+=("$dep_name")
            else
                local other=""
                for rd in $rdeps; do [ "$rd" != "$pkg" ] && other+="$rd "; done
                other=$(echo "$other" | sed 's/ $//')
                if [ -z "$other" ]; then
                    safe_to_remove+=("$dep_name")
                else
                    shared_deps+=("$dep_name")
                    conflict_details+=("  $dep_name → needed by: $other")
                fi
            fi
        done
    fi

    local lines=("Package to remove: $pkg" "")
    if [ ${#safe_to_remove[@]} -gt 0 ]; then
        lines+=("── Will also remove (${#safe_to_remove[@]} exclusive deps) ──")
        for d in "${safe_to_remove[@]}"; do lines+=("  $d"); done
    fi
    if [ ${#shared_deps[@]} -gt 0 ]; then
        lines+=("" "──  Shared deps (will NOT remove) ──")
        for d in "${conflict_details[@]}"; do lines+=("$d"); done
    fi
    local total=$((1 + ${#safe_to_remove[@]}))
    lines+=("" "Total packages to remove: $total" ""
            "  Confirm complete removal" "  Remove only $pkg (keep deps)" "  Cancel")

    local confirm; confirm=$(printf '%s\n' "${lines[@]}" | _rofi "  Remove $pkg")
    case "$confirm" in
        *"Confirm complete"*)
            local list="$pkg"; for d in "${safe_to_remove[@]}"; do list+=" $d"; done
            _run_in_term "sudo pacman -Rns $list"
            _is_installed "$pkg" || _notify "$pkg completely removed" ;;
        *"Remove only"*) _run_in_term "sudo pacman -R $pkg" ;;
    esac
}

_show_deps() {
    local pkg="$1" installed="$2" deps
    if $installed; then
        deps=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Depends On" | sed 's/.*: //')
    else
        deps=$(pacman -Si "$pkg" 2>/dev/null | grep "^Depends On" | sed 's/.*: //')
    fi
    [ -z "$deps" ] || [ "$deps" = "None" ] && { _notify "$pkg has no dependencies"; return; }

    local lines=()
    for dep in $deps; do
        local dep_name="${dep%%[><=]*}" status=""
        _is_installed "$dep_name" && status="  [installed]"
        lines+=("${dep}${status}")
    done
    local choice; choice=$(printf '%s\n' "${lines[@]}" | _rofi "  $pkg → depends on")
    [ -z "$choice" ] && return
    local sel="${choice%%[><=]*}"; sel=$(echo "$sel" | awk '{print $1}')
    _pkg_detail "$sel"
}

_show_reverse_deps() {
    local pkg="$1" installed="$2"
    $installed || { _notify "Package must be installed to see reverse deps"; return; }
    local rdeps; rdeps=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Required By" | sed 's/.*: //')
    [ -z "$rdeps" ] || [ "$rdeps" = "None" ] && { _notify "Nothing depends on $pkg"; return; }

    local lines=()
    for rdep in $rdeps; do
        local reason; reason=$(pacman -Qi "$rdep" 2>/dev/null | grep "^Install Reason" | sed 's/.*: //')
        [[ "$reason" == *"dependency"* ]] && lines+=("${rdep}  (dep)") || lines+=("${rdep}  (explicit)")
    done
    local choice; choice=$(printf '%s\n' "${lines[@]}" | _rofi "  $pkg ← required by")
    [ -z "$choice" ] && return
    _pkg_detail "$(echo "$choice" | awk '{print $1}')"
}

_show_optional_deps() {
    local pkg="$1" installed="$2" optdeps
    local src="pacman -Si"; $installed && src="pacman -Qi"
    optdeps=$($src "$pkg" 2>/dev/null | sed -n '/^Optional Deps/,/^[A-Z]/p' | head -n -1 \
              | sed 's/^Optional Deps *: //' | sed 's/^  *//')
    [ -z "$optdeps" ] || [ "$optdeps" = "None" ] && { _notify "$pkg has no optional dependencies"; return; }

    local lines=()
    while IFS= read -r odep; do
        [ -z "$odep" ] && continue
        local name="${odep%%:*}"; name="${name%%[><=]*}"; name=$(echo "$name" | awk '{print $1}')
        local status=""; _is_installed "$name" && status=" [installed]"
        lines+=("${odep}${status}")
    done <<< "$optdeps"
    local choice; choice=$(printf '%s\n' "${lines[@]}" | _rofi "  $pkg → optional deps")
    [ -z "$choice" ] && return
    local sel; sel=$(echo "$choice" | awk '{print $1}'); sel="${sel%%:*}"; sel="${sel%%[><=]*}"
    _pkg_detail "$sel"
}

_show_dep_tree() {
    local pkg="$1"
    _notify "Building dependency tree..."
    local output; output=$(pactree "$pkg" 2>/dev/null)
    [ -z "$output" ] && { _notify "pactree not available or no deps"; return; }
    local choice; choice=$(echo "$output" | _rofi "  $pkg dependency tree")
    [ -z "$choice" ] && return
    local sel; sel=$(echo "$choice" | sed 's/[│├└─ ]//g' | sed 's/^|//' | awk '{print $1}')
    [ -n "$sel" ] && _pkg_detail "$sel"
}

_show_provides_conflicts() {
    local pkg="$1" installed="$2"
    local info_cmd="pacman -Si"; $installed && info_cmd="pacman -Qi"
    local provides conflicts replaces
    provides=$($info_cmd "$pkg" 2>/dev/null | grep "^Provides" | sed 's/.*: //')
    conflicts=$($info_cmd "$pkg" 2>/dev/null | grep "^Conflicts With" | sed 's/.*: //')
    replaces=$($info_cmd "$pkg" 2>/dev/null | grep "^Replaces" | sed 's/.*: //')

    local lines=()
    for sec in "Provides:$provides" "Conflicts With:$conflicts" "Replaces:$replaces"; do
        local name="${sec%%:*}" val="${sec#*:}"
        lines+=("── $name ──")
        if [ -n "$val" ] && [ "$val" != "None" ]; then
            for v in $val; do lines+=("  $v"); done
        else
            lines+=("  (none)")
        fi
    done
    printf '%s\n' "${lines[@]}" | _rofi "  $pkg provides/conflicts"
}

_handle_pacman_selection() { _pkg_detail "$1"; }

_handle_flatpak_selection() {
    local sel_id="$1"
    if flatpak info "$sel_id" &>/dev/null; then
        local action; action=$(_rofi_list "$sel_id [installed]" "  Run" "  Uninstall" "  App info")
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
        local action; action=$(_rofi_list "$sel_pkg [installed]" "  Run" "  Remove" "  Info")
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
    local sources=("  All sources" "  Arch official")
    _has_aur && sources+=("  AUR")
    command -v flatpak &>/dev/null && sources+=("  Flatpak (Flathub)")
    command -v snap    &>/dev/null && sources+=("  Snap Store")

    local src; src=$(_rofi_list "  Filter by source" "${sources[@]}")
    [ -z "$src" ] && return

    local query; query=$(_rofi_input "  Search (install)")
    [ -z "$query" ] && return
    _notify "Searching '$query'..."

    local all=""
    case "$src" in
        *All*)
            all+=$(_search_pacman "$query"); all+=$'\n'
            all+=$(_search_flatpak_results "$query"); all+=$'\n'
            all+=$(_search_snap_results "$query") ;;
        *"Arch official"*)
            local h raw; h=$(_helper)
            [ "$h" = "pacman" ] && raw=$(pacman -Ss "$query" 2>/dev/null) || raw=$($h -Ss "$query" 2>/dev/null)
            all=$(_fmt_pacman_results "$raw" arch) ;;
        *AUR*)
            local h raw; h=$(_helper); raw=$($h -Ss "$query" 2>/dev/null)
            all=$(_fmt_pacman_results "$raw" aur) ;;
        *Flatpak*) all=$(_search_flatpak_results "$query") ;;
        *Snap*)    all=$(_search_snap_results "$query") ;;
    esac

    all=$(echo "$all" | sed '/^$/d')
    [ -z "$all" ] && { _notify "Nothing found for '$query'"; return; }

    local choice; choice=$(echo "$all" | head -120 | _rofi "  Results ($query)")
    [ -z "$choice" ] && return
    local tag; tag=$(echo "$choice" | awk '{print $1}')
    case "$tag" in
        "[arch]"|"[AUR]") _handle_pacman_selection  "$(echo "$choice" | awk '{print $2}')" ;;
        "[flatpak]")      _handle_flatpak_selection "$(echo "$choice" | awk '{print $3}')" ;;
        "[snap]")         _handle_snap_selection    "$(echo "$choice" | awk '{print $2}')" ;;
    esac
}
