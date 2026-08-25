#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — System Health                                  ║
# ║  "First, do not lose your own peace." — Marcus Aurelius       ║
# ║                                                                ║
# ║  Doctor diagnostics, package snapshots, config backups and    ║
# ║  system maintenance — the menu the v4 Noctalia panel used to  ║
# ║  show inline. Data comes from stoa-vitals-status.             ║
# ╚══════════════════════════════════════════════════════════════╝

ROFI=(rofi -dmenu -config ~/.config/rofi/config.rasi)
STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
STOA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa"
DOCTOR_LOG="${STOA_DIR}/doctor.log"
SNAPSHOT_DIR="${STOA_DIR}/pkg-snapshots"
BIN="${HOME}/.local/bin"

# ── Privilege for update/schedule actions ──
# Override in ~/.config/stoa/stoa.conf:
#   STOA_HEALTH_PRIVILEGE=sudo-n   (default: pkexec — graphical prompt)
# sudo-n requires a NOPASSWD sudoers rule for the commands below.
[ -f "$STOA_CONF" ] && source "$STOA_CONF" 2>/dev/null
_PRIVILEGE="${STOA_HEALTH_PRIVILEGE:-pkexec}"
_sudo() { [ "$_PRIVILEGE" = "sudo-n" ] && echo "sudo -n " || echo "pkexec "; }

# ── Helpers ──

_notify() { notify-send -t 2500 "Stoa Health" "$1" 2>/dev/null; }

_rofi_select() {
    local prompt="$1"
    shift
    printf '%s\n' "$@" | "${ROFI[@]}" -p "$prompt"
}

# Runs a command in the background with Running/Done/Failed notifications,
# same contract the old QML panel's _runBg had.
_run_bg() {
    local label="$1"
    local cmd="$2"
    (
        _notify "Running: ${label}"
        if eval "$cmd"; then
            _notify "Done: ${label}"
        else
            notify-send -u critical -t 2500 "Stoa Health" "Failed: ${label}" 2>/dev/null
        fi
    ) &
    disown
}

# ── Status (from stoa-vitals-status) ──

_status_json() {
    "${BIN}/stoa-vitals-status" 2>/dev/null
}

_jq_or() {
    # $1 = jq filter, $2 = json, $3 = fallback
    if command -v jq >/dev/null 2>&1; then
        local out
        out=$(printf '%s' "$2" | jq -r "$1" 2>/dev/null)
        [ -n "$out" ] && [ "$out" != "null" ] && { echo "$out"; return; }
    fi
    echo "$3"
}

_summary_line() {
    local json
    json=$(_status_json)
    [ -z "$json" ] && { echo "status unavailable"; return; }

    local issues warnings failed
    issues=$(_jq_or '.doctor.issues' "$json" "-1")
    warnings=$(_jq_or '.doctor.warnings' "$json" "0")
    failed=$(_jq_or '.failedUnits' "$json" "0")

    if [ "$issues" = "-1" ]; then
        echo "doctor not run"
    elif [ "$((issues + failed))" -gt 0 ]; then
        echo "$((issues + failed)) issue(s)"
    elif [ "$warnings" -gt 0 ]; then
        echo "${warnings} warning(s)"
    else
        echo "all systems nominal"
    fi
}

# ── Vitals tab ──

_vitals_menu() {
    local json
    json=$(_status_json)

    local lines=()
    if [ -n "$json" ]; then
        lines+=("  Doctor: $(_jq_or '"\(.doctor.issues) issues · \(.doctor.warnings) warnings"' "$json" "not run")")
        lines+=("  Failed units: $(_jq_or '.failedUnits' "$json" "0")")
        lines+=("  CPU: $(_jq_or '"\(.cpu.tempC)°C · \(.cpu.loadPct)% load"' "$json" "—")")
        lines+=("  GPU: $(_jq_or '"\(.gpu.tempC)°C"' "$json" "—")")
        lines+=("  Memory: $(_jq_or '"\(.memory.usedGiB) / \(.memory.totalGiB) GiB (\(.memory.usedPct)%)"' "$json" "—")")
        lines+=("  Disk /: $(_jq_or '"\(.disk.usedPct)% used · \(.disk.freeGiB) GiB free"' "$json" "—")")
        lines+=("  Updates: $(_jq_or '.updates' "$json" "0") pending")
        lines+=("  Uptime: $(_jq_or '.uptime' "$json" "—")")
        lines+=("")
    fi
    lines+=("  Run Doctor")
    lines+=("  Open Log")
    lines+=("  Back")

    local choice
    choice=$(_rofi_select "  Vitals" "${lines[@]}")
    case "$choice" in
        *"Run Doctor"*) _run_bg "Doctor" "${BIN}/stoa-doctor" ;;
        *"Open Log"*)   xdg-open "$DOCTOR_LOG" & disown ;;
    esac
}

# ── Snapshots tab ──

_snapshots_menu() {
    local json snapshots backups
    json=$(_status_json)
    snapshots=$(_jq_or '.snapshots' "$json" "0")
    backups=$(_jq_or '.backups' "$json" "0")

    local choice
    choice=$(_rofi_select "  Snapshots (${snapshots} packages · ${backups} configs)" \
        "  Snapshot packages now" \
        "  Backup configs now" \
        "  Browse snapshots" \
        "  Browse backups" \
        "  Back")
    case "$choice" in
        *"Snapshot packages"*) _run_bg "Package snapshot" "${BIN}/stoa-pkg-snapshot" ;;
        *"Backup configs"*)    _run_bg "Backup configs" "${BIN}/stoa-maintain --backup" ;;
        *"Browse snapshots"*)  xdg-open "$SNAPSHOT_DIR" & disown ;;
        *"Browse backups"*)    xdg-open "$HOME" & disown ;;
    esac
}

# ── Maintenance tab ──

_maintenance_menu() {
    local json updates scheduled sched_str
    json=$(_status_json)
    updates=$(_jq_or '.updates' "$json" "0")
    scheduled=$(_jq_or '.scheduled' "$json" "false")
    sched_str="disabled"
    [ "$scheduled" = "true" ] && sched_str="enabled"

    local choice
    choice=$(_rofi_select "  Maintenance (${updates} updates pending · auto-cleanup ${sched_str})" \
        "  Update all (pacman + AUR)" \
        "  Update system (pacman)" \
        "  Update AUR (yay)" \
        "  Cleanup (dry run)" \
        "  Cleanup (apply)" \
        "  Toggle boot schedule" \
        "  Firewall (locksmith)" \
        "  Back")
    case "$choice" in
        *"Update all"*)    _run_bg "Update all" "$(_sudo)pacman -Syu --noconfirm && yay -Syu --noconfirm" ;;
        *"Update system"*) _run_bg "Update system" "$(_sudo)pacman -Syu --noconfirm" ;;
        *"Update AUR"*)    _run_bg "Update AUR" "yay -Syu --noconfirm" ;;
        *"dry run"*)       _run_bg "Cleanup (dry-run)" "${BIN}/stoa-maintain --cleanup --dry-run" ;;
        *"apply"*)         _run_bg "Cleanup" "${BIN}/stoa-maintain --cleanup" ;;
        *"boot schedule"*) _run_bg "Toggle schedule" "$(_sudo)${BIN}/stoa-maintain --schedule" ;;
        *"Firewall"*)      _run_bg "Firewall" "${BIN}/stoa-locksmith" ;;
    esac
}

# ── Main menu ──

menu_health() {
    while true; do
        local choice
        choice=$(_rofi_select "  Stoa Health ($(_summary_line))" \
            "  Vitals" \
            "  Snapshots" \
            "  Maintenance" \
            "  Back")
        [ -z "$choice" ] || [[ "$choice" == *"Back"* ]] && return

        case "$choice" in
            *"Vitals"*)      _vitals_menu ;;
            *"Snapshots"*)   _snapshots_menu ;;
            *"Maintenance"*) _maintenance_menu ;;
        esac
    done
}

# ── CLI interface ──
# The bar widget calls these directly instead of opening the full menu.

case "${1:-}" in
    doctor) "${BIN}/stoa-doctor" ;;
    status) _status_json ;;
    "")     menu_health ;;
    *)
        echo "Usage: stoa-health [doctor|status]"
        exit 1
        ;;
esac
