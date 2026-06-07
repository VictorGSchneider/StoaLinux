#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Cloud Drive                                  ║
# ║  "The wise man carries his possessions within him." — Bias   ║
# ║                                                              ║
# ║  Manage cloud drives via rclone (Google Drive, OneDrive,     ║
# ║  Dropbox, S3, etc). Streams on-demand — no full download.   ║
# ╚══════════════════════════════════════════════════════════════╝

ROFI=(rofi -dmenu -config ~/.config/rofi/config.rasi)
STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
DRIVE_DIR="${HOME}/Drive"

# ── VFS cache settings ──
# Override any of these in ~/.config/stoa/stoa.conf:
#   RCLONE_CACHE_SIZE=20G        (default: 5G; use "off" for unlimited)
#   RCLONE_CACHE_MODE=full       (default: full — caches all reads for reliable offline use)
#   RCLONE_CACHE_MAX_AGE=720h    (default: 720h = 30 days; "off" = never evict by age)
[ -f "$STOA_CONF" ] && source "$STOA_CONF" 2>/dev/null
_VFS_CACHE_SIZE="${RCLONE_CACHE_SIZE:-5G}"
_VFS_CACHE_MODE="${RCLONE_CACHE_MODE:-full}"
_VFS_CACHE_AGE="${RCLONE_CACHE_MAX_AGE:-720h}"

# ── Helpers ──

_notify() { notify-send -t 2500 "Stoa Drive" "$1" 2>/dev/null; }

_rofi_select() {
    local prompt="$1"
    shift
    printf '%s\n' "$@" | "${ROFI[@]}" -p "$prompt"
}

_rofi_input() {
    local prompt="$1"
    echo "" | "${ROFI[@]}" -p "$prompt"
}

_rofi_confirm() {
    local msg="$1"
    local choice
    choice=$(_rofi_select "$msg" "  Yes" "  No")
    [[ "$choice" == *"Yes"* ]]
}

# ── rclone check ──

_check_rclone() {
    if ! command -v rclone &>/dev/null; then
        _notify "rclone not installed. Run: sudo pacman -S rclone"
        return 1
    fi
    return 0
}

# ── List configured remotes ──

_list_remotes() {
    rclone listremotes 2>/dev/null | sed 's/:$//'
}

# ── Check if a remote is currently mounted ──

_is_mounted() {
    local remote="$1"
    mount | grep -qF "${remote}: on ${DRIVE_DIR}/${remote}" 2>/dev/null
}

# ── Mount a remote ──

_mount_remote() {
    local remote="$1"
    local mountpoint="${DRIVE_DIR}/${remote}"

    if _is_mounted "$remote"; then
        _notify "${remote} is already mounted"
        return 0
    fi

    mkdir -p "$mountpoint"

    rclone mount "${remote}:" "$mountpoint" \
        --vfs-cache-mode     "$_VFS_CACHE_MODE" \
        --vfs-cache-max-size "$_VFS_CACHE_SIZE" \
        --vfs-cache-max-age  "$_VFS_CACHE_AGE"  \
        --vfs-read-chunk-size 16M \
        --vfs-read-chunk-size-limit 256M \
        --dir-cache-time 5m \
        --poll-interval 30s \
        --allow-non-empty \
        --daemon \
        2>/dev/null

    if [ $? -eq 0 ]; then
        _notify "Mounted: ${remote} → ~/Drive/${remote}"
    else
        _notify "Failed to mount ${remote}"
        rmdir "$mountpoint" 2>/dev/null
        return 1
    fi
}

# ── Unmount a remote ──

_unmount_remote() {
    local remote="$1"
    local mountpoint="${DRIVE_DIR}/${remote}"

    if ! _is_mounted "$remote"; then
        _notify "${remote} is not mounted"
        return 0
    fi

    fusermount -u "$mountpoint" 2>/dev/null

    if [ $? -eq 0 ]; then
        rmdir "$mountpoint" 2>/dev/null
        _notify "Unmounted: ${remote}"
    else
        _notify "Failed to unmount ${remote}. Try: fusermount -uz ~/Drive/${remote}"
    fi
}

# ── Mount all remotes ──

_mount_all() {
    local remotes
    remotes=$(_list_remotes)
    [ -z "$remotes" ] && { _notify "No accounts configured"; return; }

    local count=0
    while IFS= read -r remote; do
        [ -z "$remote" ] && continue
        if ! _is_mounted "$remote"; then
            _mount_remote "$remote" && ((count++))
        fi
    done <<< "$remotes"

    [ "$count" -eq 0 ] && _notify "All drives already mounted" || _notify "Mounted ${count} drive(s)"
}

# ── Unmount all remotes ──

_unmount_all() {
    local remotes
    remotes=$(_list_remotes)
    [ -z "$remotes" ] && return

    local count=0
    while IFS= read -r remote; do
        [ -z "$remote" ] && continue
        if _is_mounted "$remote"; then
            _unmount_remote "$remote" && ((count++))
        fi
    done <<< "$remotes"

    [ "$count" -eq 0 ] && _notify "No drives were mounted" || _notify "Unmounted ${count} drive(s)"
}

# ── Add a new account ──

_add_account() {
    local providers
    providers=$(_rofi_select "  Provider" \
        "  Google Drive" \
        "  OneDrive" \
        "  Dropbox" \
        "  S3 (AWS, Minio, etc)" \
        "  Other (manual)")
    [ -z "$providers" ] && return

    local provider_type=""
    case "$providers" in
        *Google*)  provider_type="drive" ;;
        *OneDrive*) provider_type="onedrive" ;;
        *Dropbox*) provider_type="dropbox" ;;
        *S3*)      provider_type="s3" ;;
        *Other*)   provider_type="" ;;
    esac

    local name
    name=$(_rofi_input "  Account name (e.g. personal, work)")
    [ -z "$name" ] && return

    # Sanitize name
    name=$(echo "$name" | tr ' ' '-' | tr -cd 'a-zA-Z0-9_-')
    [ -z "$name" ] && { _notify "Invalid name"; return; }

    # Check if already exists
    if rclone listremotes 2>/dev/null | grep -q "^${name}:$"; then
        _notify "Account '${name}' already exists"
        return
    fi

    _notify "Opening browser for authentication..."

    if [ -n "$provider_type" ]; then
        kitty -e bash -c "
            echo '╔══════════════════════════════════════════╗'
            echo '║  Stoa Drive — Account Setup              ║'
            echo '╚══════════════════════════════════════════╝'
            echo ''
            echo 'Follow the instructions below.'
            echo 'A browser window will open for authentication.'
            echo ''
            rclone config create '${name}' '${provider_type}' 2>&1
            echo ''
            echo 'Done! Press Enter to close.'
            read
        " &
        disown
    else
        kitty -e bash -c "
            echo '╔══════════════════════════════════════════╗'
            echo '║  Stoa Drive — Manual Configuration       ║'
            echo '╚══════════════════════════════════════════╝'
            echo ''
            rclone config
            echo ''
            echo 'Done! Press Enter to close.'
            read
        " &
        disown
    fi
}

# ── Remove an account ──

_remove_account() {
    local remotes
    remotes=$(_list_remotes)
    [ -z "$remotes" ] && { _notify "No accounts configured"; return; }

    local items=()
    while IFS= read -r r; do
        [ -n "$r" ] && items+=("  $r")
    done <<< "$remotes"
    items+=("  Back")

    local choice
    choice=$(_rofi_select "  Remove account" "${items[@]}")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local remote
    remote=$(echo "$choice" | sed 's/^  //')

    _rofi_confirm "Remove '${remote}'?" || return

    # Unmount first
    _is_mounted "$remote" && _unmount_remote "$remote"

    rclone config delete "$remote" 2>/dev/null
    _notify "Removed: ${remote}"
}

# ── Status ──

_show_status() {
    local remotes
    remotes=$(_list_remotes)

    if [ -z "$remotes" ]; then
        echo "No accounts configured" | "${ROFI[@]}" -p "  Drive Status"
        return
    fi

    local lines=()
    while IFS= read -r remote; do
        [ -z "$remote" ] && continue
        local type
        type=$(rclone config show "$remote" 2>/dev/null | grep "^type" | awk '{print $3}')
        if _is_mounted "$remote"; then
            lines+=("  ${remote} (${type}) — mounted at ~/Drive/${remote}")
        else
            lines+=("  ${remote} (${type}) — not mounted")
        fi
    done <<< "$remotes"

    printf '%s\n' "${lines[@]}" | "${ROFI[@]}" -p "  Drive Status"
}

# ── Open in Thunar ──

_open_in_thunar() {
    local remotes
    remotes=$(_list_remotes)
    [ -z "$remotes" ] && { _notify "No accounts configured"; return; }

    local mounted=()
    while IFS= read -r remote; do
        [ -z "$remote" ] && continue
        if _is_mounted "$remote"; then
            mounted+=("  ${remote}")
        fi
    done <<< "$remotes"

    if [ ${#mounted[@]} -eq 0 ]; then
        _notify "No drives mounted"
        return
    fi

    mounted+=("  Open ~/Drive")
    mounted+=("  Back")

    local choice
    choice=$(_rofi_select "  Open in Thunar" "${mounted[@]}")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    if [[ "$choice" == *"Open ~/Drive"* ]]; then
        thunar "$DRIVE_DIR" &
    else
        local remote
        remote=$(echo "$choice" | sed 's/^  //')
        thunar "${DRIVE_DIR}/${remote}" &
    fi
    disown
}

# ══════════════════════════════════════════════════════════════
#   MAIN MENU
# ══════════════════════════════════════════════════════════════

menu_drive() {
    _check_rclone || return

    while true; do
        local remotes
        remotes=$(_list_remotes)
        local count=0
        local mounted=0
        if [ -n "$remotes" ]; then
            count=$(echo "$remotes" | wc -l)
            while IFS= read -r r; do
                _is_mounted "$r" && ((mounted++))
            done <<< "$remotes"
        fi

        local status_str="${mounted}/${count} mounted"
        [ "$count" -eq 0 ] && status_str="no accounts"

        local choice
        choice=$(_rofi_select "  Cloud Drive (${status_str})" \
            "  Mount all" \
            "  Unmount all" \
            "  Mount / Unmount" \
            "  Add account" \
            "  Remove account" \
            "  Open in Thunar" \
            "  Status" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"Mount all"*)     _mount_all ;;
            *"Unmount all"*)   _unmount_all ;;
            *"Mount / Un"*)    _mount_unmount_menu ;;
            *"Add account"*)   _add_account ;;
            *"Remove"*)        _remove_account ;;
            *"Thunar"*)        _open_in_thunar ;;
            *"Status"*)        _show_status ;;
        esac
    done
}

# ── Mount / Unmount individual ──

_mount_unmount_menu() {
    local remotes
    remotes=$(_list_remotes)
    [ -z "$remotes" ] && { _notify "No accounts configured"; return; }

    while true; do
        local items=()
        while IFS= read -r remote; do
            [ -z "$remote" ] && continue
            if _is_mounted "$remote"; then
                items+=("  ${remote}  (mounted — click to unmount)")
            else
                items+=("  ${remote}  (click to mount)")
            fi
        done <<< "$remotes"
        items+=("  Back")

        local choice
        choice=$(_rofi_select "  Mount / Unmount" "${items[@]}")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        local remote
        remote=$(echo "$choice" | sed 's/^  //' | awk '{print $1}')

        if _is_mounted "$remote"; then
            _unmount_remote "$remote"
        else
            _mount_remote "$remote"
        fi
    done
}

# ── CLI interface ──

case "${1:-}" in
    mount-all)  _check_rclone && _mount_all ;;
    unmount-all) _check_rclone && _unmount_all ;;
    mount)
        _check_rclone || exit 1
        [ -z "$2" ] && { echo "Usage: stoa-drive mount <remote-name>"; exit 1; }
        _mount_remote "$2"
        ;;
    unmount)
        _check_rclone || exit 1
        [ -z "$2" ] && { echo "Usage: stoa-drive unmount <remote-name>"; exit 1; }
        _unmount_remote "$2"
        ;;
    status)
        _check_rclone || exit 1
        remotes=$(_list_remotes)
        if [ -z "$remotes" ]; then
            echo "No accounts configured. Run: stoa-drive (or Super+I → Cloud Drive)"
            exit 0
        fi
        while IFS= read -r remote; do
            [ -z "$remote" ] && continue
            type=$(rclone config show "$remote" 2>/dev/null | grep "^type" | awk '{print $3}')
            if _is_mounted "$remote"; then
                echo "  ${remote} (${type}) — mounted at ~/Drive/${remote}"
            else
                echo "  ${remote} (${type}) — not mounted"
            fi
        done <<< "$remotes"
        ;;
    "")
        menu_drive
        ;;
    *)
        echo "Usage: stoa-drive [mount-all|unmount-all|mount <name>|unmount <name>|status]"
        exit 1
        ;;
esac
