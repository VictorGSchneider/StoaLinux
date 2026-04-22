#!/bin/bash
# Stoa Store — Synaptic-style installed-package browser.

_browse_pkg_list() {
    local cmd="$1" prompt="$2"
    local pkgs; pkgs=$(eval "$cmd" 2>/dev/null)
    [ -z "$pkgs" ] && { _notify "No packages found"; return; }
    local count; count=$(echo "$pkgs" | wc -l)
    local choice; choice=$(echo "$pkgs" | _rofi "$prompt ($count)")
    [ -z "$choice" ] && return
    _pkg_detail "$(echo "$choice" | awk '{print $1}')"
}

_browse_orphans() {
    local orphans; orphans=$(pacman -Qdtq 2>/dev/null)
    [ -z "$orphans" ] && { _notify "No orphan packages"; return; }
    local count; count=$(echo "$orphans" | wc -l)
    local items=()
    while IFS= read -r pkg; do
        local ver size
        ver=$(pacman -Q "$pkg" 2>/dev/null | awk '{print $2}')
        size=$(pacman -Qi "$pkg" 2>/dev/null | grep "^Installed Size" | sed 's/.*: //')
        items+=("$pkg  $ver  [$size]")
    done <<< "$orphans"
    local choice; choice=$(printf '%s\n' "${items[@]}" | _rofi "  Orphans ($count) — select or remove all")
    [ -z "$choice" ] && return
    _pkg_detail "$(echo "$choice" | awk '{print $1}')"
}

_browse_upgradeable() {
    _notify "Checking for updates..."
    local h; h=$(_helper)
    local updates
    [ "$h" = "pacman" ] && updates=$(checkupdates 2>/dev/null) || updates=$($h -Qu 2>/dev/null)
    [ -z "$updates" ] && { _notify "All packages are up to date"; return; }
    local count; count=$(echo "$updates" | wc -l)
    local choice; choice=$(echo "$updates" | _rofi "  Upgradeable ($count)")
    [ -z "$choice" ] && return
    _pkg_detail "$(echo "$choice" | awk '{print $1}')"
}

_browse_groups() {
    local groups; groups=$(pacman -Sg 2>/dev/null | sort -u)
    [ -z "$groups" ] && { _notify "No groups found"; return; }
    local group; group=$(echo "$groups" | _rofi "  Package groups")
    [ -z "$group" ] && return
    local pkgs; pkgs=$(pacman -Sg "$group" 2>/dev/null | awk '{print $2}')
    [ -z "$pkgs" ] && { _notify "Group '$group' is empty"; return; }
    local count; count=$(echo "$pkgs" | wc -l)
    local lines=()
    while IFS= read -r pkg; do
        local status=""; _is_installed "$pkg" && status="  [installed]"
        lines+=("${pkg}${status}")
    done <<< "$pkgs"
    local sel; sel=$(printf '%s\n' "${lines[@]}" | _rofi "  Group: $group ($count)")
    [ -z "$sel" ] && return
    _pkg_detail "$(echo "$sel" | awk '{print $1}')"
}

_browse_repos() {
    local repos; repos=$(pacman-conf --repo-list 2>/dev/null)
    [ -z "$repos" ] && repos=$(grep '^\[' /etc/pacman.conf 2>/dev/null | grep -v '^\[options' | tr -d '[]')
    local items=()
    while IFS= read -r repo; do
        [ -z "$repo" ] && continue
        local count; count=$(pacman -Sl "$repo" 2>/dev/null | wc -l)
        items+=("$repo  ($count packages)")
    done <<< "$repos"
    local choice; choice=$(printf '%s\n' "${items[@]}" | _rofi "  Repositories")
    [ -z "$choice" ] && return
    local repo; repo=$(echo "$choice" | awk '{print $1}')
    local pkgs; pkgs=$(pacman -Sl "$repo" 2>/dev/null)
    [ -z "$pkgs" ] && { _notify "Repository '$repo' is empty"; return; }
    local lines=()
    while IFS= read -r line; do
        local name ver status=""
        name=$(echo "$line" | awk '{print $2}')
        ver=$(echo "$line" | awk '{print $3}')
        [[ "$line" == *"[installed]"* ]] && status="  [installed]"
        lines+=("${name}  ${ver}${status}")
    done <<< "$pkgs"
    local sel; sel=$(printf '%s\n' "${lines[@]}" | _rofi "  [$repo]")
    [ -z "$sel" ] && return
    _pkg_detail "$(echo "$sel" | awk '{print $1}')"
}

_search_all_pacman() {
    local query; query=$(_rofi_input "  Search all packages")
    [ -z "$query" ] && return
    _notify "Searching '$query'..."
    local h; h=$(_helper)
    local results
    [ "$h" = "pacman" ] && results=$(pacman -Ss "$query" 2>/dev/null) || results=$($h -Ss "$query" 2>/dev/null)
    [ -z "$results" ] && { _notify "Nothing found"; return; }

    local lines=()
    while IFS= read -r line1; do
        IFS= read -r line2 || true
        local repo_pkg ver desc
        repo_pkg=$(echo "$line1" | awk '{print $1}')
        ver=$(echo "$line1" | awk '{print $2}')
        desc=$(echo "$line2" | sed 's/^[[:space:]]*//')
        local pkg_name="${repo_pkg#*/}" repo="${repo_pkg%/*}"
        local status=""; _is_installed "$pkg_name" && status="  [installed]"
        lines+=("[${repo}] ${pkg_name}  ${ver}  ${desc:0:40}${status}")
    done <<< "$results"
    [ ${#lines[@]} -eq 0 ] && { _notify "Nothing found"; return; }

    local choice; choice=$(printf '%s\n' "${lines[@]}" | head -150 | _rofi "  Results ($query)")
    [ -z "$choice" ] && return
    _pkg_detail "$(echo "$choice" | awk '{print $2}')"
}

_search_installed() {
    local query; query=$(_rofi_input "  Search installed")
    [ -z "$query" ] && return
    local pkgs; pkgs=$(pacman -Q 2>/dev/null | grep -i "$query")
    [ -z "$pkgs" ] && { _notify "Not found in installed packages"; return; }
    local choice; choice=$(echo "$pkgs" | _rofi "  Installed: $query")
    [ -z "$choice" ] && return
    _pkg_detail "$(echo "$choice" | awk '{print $1}')"
}

_check_broken_deps() {
    _notify "Checking for broken dependencies..."
    local broken; broken=$(pacman -Dk 2>&1 | grep -v ": all dependencies satisfied")
    [ -z "$broken" ] && { _notify "No broken dependencies found!"; return; }
    local count; count=$(echo "$broken" | wc -l)
    echo "$broken" | _rofi "  Broken deps ($count issues)"
}

_installed() {
    while true; do
        local total deps explicit foreign orphans
        total=$(pacman -Q    2>/dev/null | wc -l)
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
            *"All installed"*)   _browse_pkg_list "pacman -Q"  "  All installed" ;;
            *"Explicitly"*)      _browse_pkg_list "pacman -Qe" "  Explicit" ;;
            *"Dependencies only"*) _browse_pkg_list "pacman -Qd" "  Dependencies" ;;
            *"AUR / foreign"*)   _browse_pkg_list "pacman -Qm" "  AUR / foreign" ;;
            *"Orphan"*)          _browse_orphans ;;
            *"Upgradeable"*)     _browse_upgradeable ;;
            *"Browse by group"*) _browse_groups ;;
            *"Browse by repo"*)  _browse_repos ;;
            *"Search all"*)      _search_all_pacman ;;
            *"Search installed"*) _search_installed ;;
            *"Check broken"*)    _check_broken_deps ;;
        esac
    done
}
