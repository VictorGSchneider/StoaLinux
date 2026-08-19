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
SYNC_LIST="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/drive-sync.list"
SYNC_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/stoa/drive-sync"
SYNC_UNIT="stoa-drive-sync"

# ── VFS cache settings ──
# Override any of these in ~/.config/stoa/stoa.conf:
#   RCLONE_CACHE_SIZE=20G        (default: 5G; use "off" for unlimited)
#   RCLONE_CACHE_MODE=full       (default: full — caches all reads for reliable offline use)
#   RCLONE_CACHE_MAX_AGE=720h    (default: 720h = 30 days; "off" = never evict by age)
#   RCLONE_DIR_CACHE_TIME=24h    (default: 24h — how long directory listings stay cached)
#   RCLONE_ATTR_TIMEOUT=1h       (default: 1h — how long file stat()s stay cached)
#   RCLONE_POLL_INTERVAL=1m      (default: 1m — how often to poll remote for changes)
#   STOA_DRIVE_PREWARM=true      (default: true — walk dir tree after mount to pre-fill cache)
#   STOA_SYNC_INTERVAL=5min      (default: 5min — bisync timer interval; systemd OnUnitActiveSec)
#   STOA_SYNC_CONFLICT=newer     (default: newer — newer|older|larger|smaller|path1|path2|none)
[ -f "$STOA_CONF" ] && source "$STOA_CONF" 2>/dev/null
_VFS_CACHE_SIZE="${RCLONE_CACHE_SIZE:-5G}"
_VFS_CACHE_MODE="${RCLONE_CACHE_MODE:-full}"
_VFS_CACHE_AGE="${RCLONE_CACHE_MAX_AGE:-720h}"
_DIR_CACHE_TIME="${RCLONE_DIR_CACHE_TIME:-24h}"
_ATTR_TIMEOUT="${RCLONE_ATTR_TIMEOUT:-1h}"
_POLL_INTERVAL="${RCLONE_POLL_INTERVAL:-1m}"
_PREWARM="${STOA_DRIVE_PREWARM:-true}"
_SYNC_INTERVAL="${STOA_SYNC_INTERVAL:-5min}"
_SYNC_CONFLICT="${STOA_SYNC_CONFLICT:-newer}"

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

    # Exclude paths that are mirrored via bisync — avoids the mount and the
    # local sync target fighting over the same files.
    local excludes=()
    while IFS=$'\t' read -r rp _lp; do
        [ -z "$rp" ] && continue
        [[ "$rp" == \#* ]] && continue
        local rname="${rp%%:*}"
        local rpath="${rp#*:}"
        [ "$rname" = "$remote" ] && [ -n "$rpath" ] && excludes+=(--exclude "/${rpath}/**")
    done < <([ -f "$SYNC_LIST" ] && cat "$SYNC_LIST")

    rclone mount "${remote}:" "$mountpoint" \
        --vfs-cache-mode     "$_VFS_CACHE_MODE" \
        --vfs-cache-max-size "$_VFS_CACHE_SIZE" \
        --vfs-cache-max-age  "$_VFS_CACHE_AGE"  \
        --vfs-read-chunk-size 16M \
        --vfs-read-chunk-size-limit 256M \
        --vfs-fast-fingerprint \
        --dir-cache-time "$_DIR_CACHE_TIME" \
        --attr-timeout   "$_ATTR_TIMEOUT" \
        --poll-interval  "$_POLL_INTERVAL" \
        "${excludes[@]}" \
        --allow-non-empty \
        --daemon \
        2>/dev/null

    if [ $? -eq 0 ]; then
        _notify "Mounted: ${remote} → ~/Drive/${remote}"
        [ "$_PREWARM" = "true" ] && _prewarm_mount "$remote"
    else
        _notify "Failed to mount ${remote}"
        rmdir "$mountpoint" 2>/dev/null
        return 1
    fi
}

# ── Pre-warm dir cache ──
# rclone's --dir-cache-time only lives in RAM, so every fresh mount starts
# cold — the first time you browse a folder, it stalls waiting for the API.
# We walk the whole tree in the background right after mount so that by the
# time the user opens Thunar the cache is already populated. Time grows with
# folder count; ~5k folders ≈ a few seconds, ~50k ≈ ~1min.
_prewarm_mount() {
    local remote="$1"
    local mountpoint="${DRIVE_DIR}/${remote}"
    (
        sleep 2
        local started ended dirs
        started=$(date +%s)
        dirs=$(find "$mountpoint" -mindepth 1 -type d 2>/dev/null | wc -l)
        ended=$(date +%s)
        _notify "${remote}: cache warmed (${dirs} dirs in $((ended - started))s)"
    ) &
    disown
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
#   BISYNC — keep a local folder mirrored to a remote path
# ══════════════════════════════════════════════════════════════
#
# Pairs live in ~/.config/stoa/drive-sync.list, one per line, TAB-separated:
#     gdrive:Obsidian<TAB>/home/zeno/Obsidian
# Lines starting with # are ignored.
#
# State (workdir + first-sync marker) lives under ~/.cache/stoa/drive-sync/.
# When a pair is registered, the path is also auto-excluded from the
# rclone mount of that remote — so the mounted view and the synced copy
# do not collide.

_pair_id() {
    # Stable, filesystem-safe identifier for a pair (used as cache subdir name).
    printf '%s' "$1__$2" | tr '/:' '__' | tr -cd 'a-zA-Z0-9_.-'
}

_pair_workdir() {
    echo "${SYNC_CACHE}/$(_pair_id "$1" "$2")"
}

_list_sync_pairs() {
    # Emit "remote:path<TAB>local-path" for each configured pair.
    [ ! -f "$SYNC_LIST" ] && return
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        printf '%s\n' "$line"
    done < "$SYNC_LIST"
}

_run_sync() {
    local remote_path="$1"
    local local_path="$2"
    local quiet="${3:-0}"

    local remote="${remote_path%%:*}"
    if ! rclone listremotes 2>/dev/null | grep -qF "${remote}:"; then
        [ "$quiet" = "0" ] && _notify "Sync: remote '${remote}' not configured"
        return 1
    fi

    mkdir -p "$local_path"
    local workdir
    workdir=$(_pair_workdir "$remote_path" "$local_path")
    mkdir -p "$workdir"

    local marker="${workdir}/.first-sync-done"
    local logfile="${workdir}/last.log"
    local lockfile="${workdir}/.lock"
    local resync_flag=()
    [ ! -f "$marker" ] && resync_flag=(--resync)

    # Per-pair flock: if a previous run (usually the timer firing while a big
    # resync is still ongoing) is still holding the lock, skip silently.
    # Overlapping bisync invocations against the same workdir corrupt the
    # listing state and force a manual --resync to recover.
    local rc
    (
        flock -n 9 || exit 200
        rclone bisync "$local_path" "$remote_path" \
            --workdir "$workdir" \
            --conflict-resolve "$_SYNC_CONFLICT" \
            --conflict-loser num \
            --create-empty-src-dirs \
            --compare size,modtime \
            --fast-list \
            "${resync_flag[@]}" \
            >"$logfile" 2>&1
    ) 9>"$lockfile"
    rc=$?

    case "$rc" in
        200)
            [ "$quiet" = "0" ] && _notify "Sync busy: ${remote_path} — another run in progress"
            return 0
            ;;
        0)
            touch "$marker"
            [ "$quiet" = "0" ] && _notify "Synced: ${local_path}  ⇄  ${remote_path}"
            return 0
            ;;
        *)
            [ "$quiet" = "0" ] && _notify "Sync failed for ${remote_path}. See ${logfile}"
            return 1
            ;;
    esac
}

_run_all_syncs() {
    local pairs
    pairs=$(_list_sync_pairs)
    [ -z "$pairs" ] && { [ "${1:-}" != "quiet" ] && _notify "No sync pairs configured"; return; }

    local ok=0 fail=0
    while IFS=$'\t' read -r rp lp; do
        [ -z "$rp" ] && continue
        if _run_sync "$rp" "$lp" 1; then ((ok++)); else ((fail++)); fi
    done <<< "$pairs"

    if [ "${1:-}" = "quiet" ]; then
        return 0
    fi
    if [ "$fail" -eq 0 ]; then
        _notify "Synced ${ok} pair(s)"
    else
        _notify "Synced ${ok}, failed ${fail}. Check ${SYNC_CACHE}/*/last.log"
    fi
}

_add_sync_pair() {
    local remotes
    remotes=$(_list_remotes)
    [ -z "$remotes" ] && { _notify "No accounts configured"; return; }

    local items=()
    while IFS= read -r r; do
        [ -n "$r" ] && items+=("  $r")
    done <<< "$remotes"
    items+=("  Back")

    local choice
    choice=$(_rofi_select "  Remote" "${items[@]}")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return
    local remote
    remote=$(echo "$choice" | sed 's/^  //')

    local rpath
    rpath=$(_rofi_input "  Remote path (e.g. Obsidian)")
    [ -z "$rpath" ] && return
    rpath="${rpath#/}"; rpath="${rpath%/}"

    local lpath
    lpath=$(_rofi_input "  Local path (e.g. ~/Obsidian)")
    [ -z "$lpath" ] && return
    lpath="${lpath/#\~/$HOME}"

    local entry="${remote}:${rpath}"$'\t'"${lpath}"
    mkdir -p "$(dirname "$SYNC_LIST")"
    touch "$SYNC_LIST"

    if grep -qF "$entry" "$SYNC_LIST" 2>/dev/null; then
        _notify "Pair already exists"
        return
    fi

    echo "$entry" >> "$SYNC_LIST"
    _notify "Added: ${remote}:${rpath}  ⇄  ${lpath}"

    if _rofi_confirm "Run first sync now? (Will --resync)"; then
        _run_sync "${remote}:${rpath}" "$lpath"
    fi
}

_remove_sync_pair() {
    local pairs
    pairs=$(_list_sync_pairs)
    [ -z "$pairs" ] && { _notify "No sync pairs configured"; return; }

    local items=()
    while IFS=$'\t' read -r rp lp; do
        [ -z "$rp" ] && continue
        items+=("  ${rp}  ⇄  ${lp}")
    done <<< "$pairs"
    items+=("  Back")

    local choice
    choice=$(_rofi_select "  Remove sync pair" "${items[@]}")
    [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

    local clean="${choice#  }"
    local rp="${clean%%  ⇄  *}"
    local lp="${clean##*  ⇄  }"

    _rofi_confirm "Remove pair '${rp}  ⇄  ${lp}'?" || return

    local tmp
    tmp=$(mktemp)
    grep -vxF "${rp}"$'\t'"${lp}" "$SYNC_LIST" > "$tmp" || true
    mv "$tmp" "$SYNC_LIST"

    if _rofi_confirm "Also delete sync state for this pair?"; then
        rm -rf "$(_pair_workdir "$rp" "$lp")"
    fi
    _notify "Removed pair"
}

_auto_sync_enabled() {
    systemctl --user is-enabled "${SYNC_UNIT}.timer" &>/dev/null
}

_install_sync_units() {
    local unit_dir="${HOME}/.config/systemd/user"
    mkdir -p "$unit_dir"

    cat > "${unit_dir}/${SYNC_UNIT}.service" <<EOF
[Unit]
Description=Stoa Drive — bisync registered pairs
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=%h/.local/bin/stoa-drive sync-all-quiet
EOF

    cat > "${unit_dir}/${SYNC_UNIT}.timer" <<EOF
[Unit]
Description=Stoa Drive — periodic bisync

[Timer]
OnBootSec=2min
OnUnitActiveSec=${_SYNC_INTERVAL}
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl --user daemon-reload
}

_enable_auto_sync() {
    _install_sync_units
    systemctl --user enable --now "${SYNC_UNIT}.timer" 2>/dev/null
    _notify "Auto-sync enabled (every ${_SYNC_INTERVAL})"
}

_disable_auto_sync() {
    systemctl --user disable --now "${SYNC_UNIT}.timer" 2>/dev/null
    _notify "Auto-sync disabled"
}

_sync_status() {
    local lines=()
    if _auto_sync_enabled; then
        local next
        next=$(systemctl --user list-timers "${SYNC_UNIT}.timer" --no-pager 2>/dev/null \
            | awk 'NR==2 {print $1, $2}')
        lines+=("  Auto-sync: ON (every ${_SYNC_INTERVAL})")
        [ -n "$next" ] && lines+=("    next run: ${next}")
    else
        lines+=("  Auto-sync: OFF")
    fi
    lines+=("")

    local pairs
    pairs=$(_list_sync_pairs)
    if [ -z "$pairs" ]; then
        lines+=("  No sync pairs configured")
    else
        lines+=("  Pairs:")
        while IFS=$'\t' read -r rp lp; do
            [ -z "$rp" ] && continue
            local wd marker="off"
            wd=$(_pair_workdir "$rp" "$lp")
            [ -f "${wd}/.first-sync-done" ] && marker="ready" || marker="pending --resync"
            lines+=("    ${rp}  ⇄  ${lp}  [${marker}]")
        done <<< "$pairs"
    fi

    printf '%s\n' "${lines[@]}" | "${ROFI[@]}" -p "  Sync Status"
}

_sync_menu() {
    while true; do
        local auto="OFF"
        _auto_sync_enabled && auto="ON"

        local pair_count
        pair_count=$(_list_sync_pairs | grep -c .)

        local choice
        choice=$(_rofi_select "  Folder Sync (${pair_count} pair(s), auto: ${auto})" \
            "  Sync now (all)" \
            "  Add pair" \
            "  Remove pair" \
            "  Enable auto-sync" \
            "  Disable auto-sync" \
            "  Status" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"Sync now"*)         _run_all_syncs ;;
            *"Add pair"*)         _add_sync_pair ;;
            *"Remove pair"*)      _remove_sync_pair ;;
            *"Enable"*)           _enable_auto_sync ;;
            *"Disable"*)          _disable_auto_sync ;;
            *"Status"*)           _sync_status ;;
        esac
    done
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
            "  Folder Sync" \
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
            *"Folder Sync"*)   _sync_menu ;;
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
    sync)
        _check_rclone || exit 1
        if [ -n "$2" ] && [ -n "$3" ]; then
            _run_sync "$2" "$3"
        else
            echo "Usage: stoa-drive sync <remote:path> <local-path>"
            exit 1
        fi
        ;;
    prewarm)
        _check_rclone || exit 1
        if [ -n "$2" ]; then
            _is_mounted "$2" || { echo "Not mounted: $2"; exit 1; }
            _prewarm_mount "$2"
        else
            remotes=$(_list_remotes)
            while IFS= read -r r; do
                [ -z "$r" ] && continue
                _is_mounted "$r" && _prewarm_mount "$r"
            done <<< "$remotes"
        fi
        ;;
    sync-all)         _check_rclone && _run_all_syncs ;;
    sync-all-quiet)   _check_rclone && _run_all_syncs quiet ;;
    sync-enable)      _enable_auto_sync ;;
    sync-disable)     _disable_auto_sync ;;
    sync-status)
        _check_rclone || exit 1
        if _auto_sync_enabled; then echo "Auto-sync: ON (every ${_SYNC_INTERVAL})"
        else echo "Auto-sync: OFF"; fi
        _list_sync_pairs | while IFS=$'\t' read -r rp lp; do
            [ -z "$rp" ] && continue
            wd=$(_pair_workdir "$rp" "$lp")
            state="pending --resync"
            [ -f "${wd}/.first-sync-done" ] && state="ready"
            echo "  ${rp}  ⇄  ${lp}  [${state}]"
        done
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
        echo "Usage: stoa-drive [mount-all|unmount-all|mount <name>|unmount <name>"
        echo "                   |prewarm [<name>]|sync <remote:path> <local>|sync-all"
        echo "                   |sync-enable|sync-disable|sync-status|status]"
        exit 1
        ;;
esac
