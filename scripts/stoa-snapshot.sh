#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — System snapshots (Btrfs + Snapper + Limine)    ║
# ║  "Nothing is ours except time." — Seneca                     ║
# ╚══════════════════════════════════════════════════════════════╝
#
# The business logic behind the "System" section of the stoa-health
# panel, same split as stoa-health / stoa-drive: the panel only calls
# these non-interactive subcommands and renders what `status` prints.
#
#   stoa-snapshot status          JSON, never prompts, safe to poll
#   stoa-snapshot create [desc]   snapshot / now (no password once set up)
#   stoa-snapshot setup           open setup/enable-limine-snapshots.sh in a terminal
#   stoa-snapshot restore         open limine-snapper-restore in a terminal
#   stoa-snapshot list            open the snapshot list in a terminal
#
# `status` fields:
#   available   Btrfs root and Limine installed — snapshots can work here
#   reason      why not, when available is false
#   configured  a Snapper config for / exists
#   bootMenu    limine-snapper-sync.service is enabled
#   readable    this user may list/create without a password (ALLOW_USERS)
#   count       snapshots of / (-1 when not readable)
#   latest      date of the newest one, "" when none or not readable

STOA_REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)"
SETUP="${STOA_REPO}/setup/enable-limine-snapshots.sh"
TERM_CMD="${TERMINAL:-kitty}"
SNAPPER_ROOT_CONFIG="${SNAPPER_ROOT_CONFIG:-/etc/snapper/configs/root}"

# Same knob as stoa-health (~/.config/stoa/stoa.conf): graphical pkexec
# prompt by default, sudo -n with a NOPASSWD rule.
_STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
# shellcheck source=/dev/null
[ -f "$_STOA_CONF" ] && source "$_STOA_CONF" 2>/dev/null
_PRIVILEGE="${STOA_HEALTH_PRIVILEGE:-pkexec}"
_priv() { if [ "$_PRIVILEGE" = "sudo-n" ]; then sudo -n "$@"; else pkexec "$@"; fi; }

_notify() { notify-send -t 3000 "Stoa Snapshots" "$1" 2>/dev/null || true; }

_has_limine() { command -v limine &>/dev/null || pacman -Qq limine &>/dev/null; }
_root_btrfs() { [ "$(findmnt -no FSTYPE / 2>/dev/null)" = "btrfs" ]; }
_configured() { [ -f "$SNAPPER_ROOT_CONFIG" ]; }
_boot_menu()  { systemctl is-enabled limine-snapper-sync.service &>/dev/null; }

# snapper's JSON for config "root", or nothing when this user may not read it.
_list_json() {
    snapper --jsonout -c root list 2>/dev/null
}

# Run a command in a terminal that stays open until Enter, so the output
# (and any sudo prompt) is not lost when it finishes.
_in_terminal() { # <title> <command...>
    local title="$1"; shift
    local cmd
    printf -v cmd '%q ' "$@"
    nohup "$TERM_CMD" --title "$title" -e bash -c \
        "${cmd}; echo; read -rp 'Press Enter to close…' _" >/dev/null 2>&1 &
}

_status() {
    local available=false reason="" configured=false boot=false readable=false
    local count=-1 latest=""

    if ! _root_btrfs; then
        reason="root is not Btrfs"
    elif ! _has_limine; then
        reason="Limine is not the bootloader"
    else
        available=true
    fi
    _configured && configured=true
    _boot_menu && boot=true

    if $configured; then
        local json
        json=$(_list_json)
        if [ -n "$json" ] && echo "$json" | jq -e '.root' >/dev/null 2>&1; then
            readable=true
            # Snapshot 0 is snapper's name for the live system, not a snapshot.
            count=$(echo "$json" | jq '[.root[] | select(.number != 0)] | length')
            latest=$(echo "$json" | jq -r '[.root[] | select(.number != 0)] | last | .date // ""')
        fi
    fi

    jq -nc \
        --argjson available "$available" --arg reason "$reason" \
        --argjson configured "$configured" --argjson bootMenu "$boot" \
        --argjson readable "$readable" --argjson count "$count" --arg latest "$latest" \
        '{available:$available, reason:$reason, configured:$configured,
          bootMenu:$bootMenu, readable:$readable, count:$count, latest:$latest}'
}

_create() {
    local desc="${1:-stoa: manual snapshot}"
    if ! _configured; then
        _notify "Snapshots are not set up yet"
        return 1
    fi
    # "number" cleanup lets snapper prune these like every other snapshot.
    local args=(-c root create --cleanup-algorithm number -d "$desc")
    # Without a password when setup granted ALLOW_USERS, else ask.
    if snapper "${args[@]}" 2>/dev/null || _priv snapper "${args[@]}"; then
        _notify "Snapshot created: ${desc}"
    else
        _notify "Snapshot failed"
        return 1
    fi
}

case "${1:-}" in
    status)  _status ;;
    create)  shift; _create "$*" ;;
    setup)
        [ -x "$SETUP" ] || { _notify "Setup script not found: ${SETUP}"; exit 1; }
        _in_terminal "Stoa — Boot snapshots" bash "$SETUP"
        ;;
    restore)
        command -v limine-snapper-restore &>/dev/null || { _notify "limine-snapper-restore is not installed"; exit 1; }
        _in_terminal "Stoa — Restore snapshot" sudo limine-snapper-restore
        ;;
    list)
        if command -v limine-snapper-list &>/dev/null; then
            _in_terminal "Stoa — Snapshots" limine-snapper-list
        else
            _in_terminal "Stoa — Snapshots" snapper -c root list
        fi
        ;;
    *)
        echo "Usage: stoa-snapshot [status|create [description]|setup|restore|list]" >&2
        exit 2
        ;;
esac
