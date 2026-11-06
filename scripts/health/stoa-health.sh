#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — System Health                                  ║
# ║  "First, do not lose your own peace." — Marcus Aurelius       ║
# ║                                                                ║
# ║  Doctor diagnostics, package snapshots, config backups and    ║
# ║  system maintenance — the menu the v4 Noctalia panel used to  ║
# ║  show inline. Data comes from stoa-vitals-status.             ║
# ╚══════════════════════════════════════════════════════════════╝

# ── --help ──
case "${1:-}" in
    -h|--help|help)
        cat <<'STOA_HELP'
stoa-health — system health actions (the System Health panel, also usable from a shell).

USAGE
  stoa-health [COMMAND]               no command opens the health menu

COMMANDS
  doctor             run stoa-doctor
  status             health status as JSON
  hardware           hardware report: SSD SMART, memory, CPU, GPUs, display, battery
  smart-test [KIND] [DRIVE]
                     SMART self-test (short|extended) through polkit — asks for your password
  smart-report [DRIVE]
                     full smartctl report in a terminal — asks for your password
  snapshot           take a package snapshot (stoa-pkg-snapshot)
  backup             back up the configs (stoa-maintain --backup)
  cleanup            full cleanup (stoa-maintain --cleanup) — opens a terminal, where sudo asks
                     for your password; stoa-maintain refuses to run it without one
  cleanup-dry-run    preview the cleanup (stoa-maintain --cleanup --dry-run) in a terminal
  cleanup-user       cleanup of your own files only (stoa-maintain --cleanup --user);
                     needs no sudo, so it runs in the background
  schedule           schedule the cleanup at boot (stoa-maintain --schedule) — in a terminal
  unschedule         remove the boot cleanup, however it was scheduled — in a terminal
  update-all         pacman -Syu then yay -Sua — in a terminal
  update-system      pacman -Syu — in a terminal
  update-aur         yay -Syu — in a terminal
  locksmith          open stoa-locksmith (find and end what holds a file or folder open)
  help               show this help

OPTIONS
  -h, --help    show this help

Anything that needs root (updates, cleanup, schedule) opens a terminal, where sudo asks
for your password: run in the background there is nothing to answer, and every prompt-less
sudo counts as a failed login to pam_faillock.

SETTINGS
  STOA_HEALTH_PRIVILEGE=pkexec|sudo-n   how stoa-snapshot gets root for a system snapshot
                                        (default: pkexec; sudo-n needs a NOPASSWD sudoers rule)

RESUMO RÁPIDO
  stoa-health
  stoa-health doctor | status | hardware | snapshot | locksmith
  stoa-health smart-test | smart-test extended nvme0 | smart-report
  stoa-health backup | cleanup | cleanup-dry-run | cleanup-user
  stoa-health schedule | unschedule
  stoa-health update-all | update-system | update-aur
  stoa-health -h | --help | help
STOA_HELP
        exit 0
        ;;
esac

STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"
STOA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa"
TERM_CMD="${TERMINAL:-kitty}"
DOCTOR_LOG="${STOA_DIR}/doctor.log"
BIN="${HOME}/.local/bin"

[ -f "$STOA_CONF" ] && source "$STOA_CONF" 2>/dev/null

# ── Root actions run in a terminal ──
# Updates, cleanup and the boot schedule need root. A background process
# cannot answer sudo: with no terminal every sudo is a PAM "conversation
# failed", pam_faillock counts each one, and three lock the account out of
# sudo, polkit and the login screen. (pkexec would ask graphically, but a
# yay/makepkg run escalates by itself half-way through.) So they open a
# terminal where sudo can prompt — and where the output can be read.
_UPDATE_SYSTEM='sudo pacman -Syu --noconfirm'
_UPDATE_AUR='if command -v yay >/dev/null; then yay -Syu --noconfirm; else echo "yay is not installed"; exit 1; fi'
# The AUR step follows a successful pacman -Syu, so the repos are already
# synced: -Sua skips the second sync.
_UPDATE_ALL='sudo pacman -Syu --noconfirm || exit 1
if command -v yay >/dev/null; then yay -Sua --noconfirm; else echo "yay is not installed — AUR skipped"; fi'

# Everything that could be the boot cleanup, however it was scheduled:
# root systemd timer (--schedule), systemd --user timer or your crontab
# (--schedule --user), root's crontab (no-systemd fallback), legacy BRCS.
# Narrow on purpose: it must not take an unrelated stoa-maintain line
# (say, a nightly --backup) with it.
_CLEANUP_CRON_RE='(stoa-maintain|BRCS\.sh|brcs-cleanup).*--cleanup'

_unschedule_run() {
    local unit=stoa-maintain-cleanup removed=0 udir="${HOME}/.config/systemd/user"

    if systemctl --user is-enabled "$unit.timer" &>/dev/null || [ -e "$udir/$unit.timer" ]; then
        systemctl --user disable --now "$unit.timer" 2>/dev/null
        rm -f "$udir/$unit.service" "$udir/$unit.timer"
        systemctl --user daemon-reload 2>/dev/null
        echo "Removed the systemd --user timer."; removed=1
    fi
    if command -v crontab &>/dev/null && crontab -l 2>/dev/null | grep -qE "$_CLEANUP_CRON_RE"; then
        crontab -l 2>/dev/null | grep -vE "$_CLEANUP_CRON_RE" | crontab -
        echo "Removed the cleanup line from your crontab."; removed=1
    fi
    if systemctl is-enabled "$unit.timer" &>/dev/null || [ -e "/etc/systemd/system/$unit.timer" ]; then
        sudo systemctl disable --now "$unit.timer"
        sudo rm -f "/etc/systemd/system/$unit.service" "/etc/systemd/system/$unit.timer"
        sudo systemctl daemon-reload
        echo "Removed the root systemd timer."; removed=1
    fi
    # Root's crontab is only where the job lives without systemd; asking
    # for sudo just to look would be a password prompt for nothing.
    if ! command -v systemctl &>/dev/null && command -v crontab &>/dev/null \
            && sudo crontab -l 2>/dev/null | grep -qE "$_CLEANUP_CRON_RE"; then
        sudo crontab -l 2>/dev/null | grep -vE "$_CLEANUP_CRON_RE" | sudo crontab -
        echo "Removed the cleanup line from root's crontab."; removed=1
    fi
    [ "$removed" -eq 1 ] || echo "No boot cleanup schedule found."
}

# ── Helpers ──

_notify() { notify-send -t 2500 "Stoa Health" "$1" 2>/dev/null; }

_STOA_YAD_LIB="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/stoa-yad.sh"
# shellcheck source=lib/stoa-yad.sh
[ -r "$_STOA_YAD_LIB" ] && source "$_STOA_YAD_LIB"

_yad_select() {
    local prompt="$1"
    shift
    printf '%s\n' "$@" | stoa_yad_list "$prompt"
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

# Opens a terminal for output that needs reading (and for pkexec prompts
# that fall back to the terminal when no polkit agent is up).
_in_terminal() { # <title> <command...>
    local title="$1"; shift
    local cmd
    printf -v cmd '%q ' "$@"
    nohup "$TERM_CMD" --title "$title" -e bash -c \
        "${cmd}; echo; read -rp 'Press Enter to close…' _" >/dev/null 2>&1 &
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

    local issues warnings failed hw_issues hw_warnings
    issues=$(_jq_or '.doctor.issues' "$json" "-1")
    warnings=$(_jq_or '.doctor.warnings' "$json" "0")
    failed=$(_jq_or '.failedUnits' "$json" "0")
    hw_issues=$(_jq_or '.hardware.issues' "$json" "0")
    hw_warnings=$(_jq_or '.hardware.warnings' "$json" "0")
    [ "$issues" != "-1" ] && issues=$((issues + hw_issues))
    warnings=$((warnings + hw_warnings))

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
        lines+=("  Hardware: $(_jq_or '"\(.hardware.issues) issues · \(.hardware.warnings) warnings"' "$json" "not checked")")
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
    lines+=("  Hardware report")
    lines+=("  SMART self-test (asks password)")
    lines+=("  Back")

    local choice
    choice=$(_yad_select "  Vitals" "${lines[@]}")
    case "$choice" in
        *"Run Doctor"*) _run_bg "Doctor" "${BIN}/stoa-doctor" ;;
        *"Open Log"*)   xdg-open "$DOCTOR_LOG" & disown ;;
        *"Hardware report"*) _in_terminal "Stoa — Hardware" "${BIN}/stoa-hardware" report --fresh ;;
        *"SMART self-test"*) _run_bg "SMART self-test" "${BIN}/stoa-hardware smart-test --notify" ;;
    esac
}

# ── Snapshots tab ──

_snapshots_menu() {
    local json snapshots backups
    json=$(_status_json)
    snapshots=$(_jq_or '.snapshots' "$json" "0")
    backups=$(_jq_or '.backups' "$json" "0")

    # System (Btrfs) entries depend on what this machine can do — see
    # stoa-snapshot status.
    local sys sys_entries=()
    sys=$("${BIN}/stoa-snapshot" status 2>/dev/null)
    if [ "$(_jq_or '.available' "$sys" "false")" = "true" ]; then
        if [ "$(_jq_or '.configured' "$sys" "false")" = "true" ]; then
            sys_entries+=("  Create system snapshot" "  Restore system snapshot")
            [ "$(_jq_or '.bootMenu' "$sys" "false")" = "true" ] || sys_entries+=("  Enable boot snapshots")
        else
            sys_entries+=("  Enable boot snapshots")
        fi
    fi

    local choice
    choice=$(_yad_select "  Snapshots (${snapshots} packages · ${backups} configs)" \
        "${sys_entries[@]}" \
        "  Snapshot packages now" \
        "  Backup configs now" \
        "  See what's inside (snapshot browser)" \
        "  Back")
    case "$choice" in
        *"Create system snapshot"*)  "${BIN}/stoa-snapshot" create "stoa: manual snapshot" & disown ;;
        *"Restore system snapshot"*) "${BIN}/stoa-snapshot" restore ;;
        *"Enable boot snapshots"*)   "${BIN}/stoa-snapshot" setup ;;
        *"Snapshot packages"*) _run_bg "Package snapshot" "${BIN}/stoa-pkg-snapshot" ;;
        *"Backup configs"*)    _run_bg "Backup configs" "${BIN}/stoa-maintain --backup" ;;
        *"snapshot browser"*)  "${BIN}/stoa-snapshots" & disown ;;
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
    choice=$(_yad_select "  Maintenance (${updates} updates pending · auto-cleanup ${sched_str})" \
        "  Update all (pacman + AUR)" \
        "  Update system (pacman)" \
        "  Update AUR (yay)" \
        "  Cleanup (dry run)" \
        "  Cleanup (apply)" \
        "  Cleanup (my files, no sudo)" \
        "  Schedule cleanup at boot" \
        "  Remove boot schedule" \
        "  File locksmith" \
        "  Back")
    case "$choice" in
        *"Update all"*)    _in_terminal "Stoa — Update all" bash -c "$_UPDATE_ALL" ;;
        *"Update system"*) _in_terminal "Stoa — Update system" bash -c "$_UPDATE_SYSTEM" ;;
        *"Update AUR"*)    _in_terminal "Stoa — Update AUR" bash -c "$_UPDATE_AUR" ;;
        *"dry run"*)       _in_terminal "Stoa — Cleanup preview" "${BIN}/stoa-maintain" --cleanup --dry-run ;;
        *"apply"*)         _in_terminal "Stoa — Cleanup" "${BIN}/stoa-maintain" --cleanup ;;
        *"my files"*)      _run_bg "Cleanup (my files)" "${BIN}/stoa-maintain --cleanup --user" ;;
        *"Schedule cleanup"*) _in_terminal "Stoa — Schedule cleanup" "${BIN}/stoa-maintain" --schedule ;;
        *"Remove boot"*)   _in_terminal "Stoa — Remove schedule" "$(readlink -f "${BASH_SOURCE[0]}")" unschedule-run ;;
        *"locksmith"*)     "${BIN}/stoa-locksmith" & disown ;;
    esac
}

# ── Main menu ──

menu_health() {
    while true; do
        local choice
        choice=$(_yad_select "  Stoa Health ($(_summary_line))" \
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
# The bar widget and its native panel (theme/noctalia-plugins/stoa-health/
# panel.luau) call these directly instead of opening the yad menu above —
# same split as stoa-drive: business logic (incl. the pkexec/sudo-n
# privilege choice) stays here, the panel is a thin dispatcher. The yad
# menu itself is kept as a CLI fallback for anyone invoking stoa-health
# bare outside Noctalia.

case "${1:-}" in
    doctor)          "${BIN}/stoa-doctor" ;;
    status)           _status_json ;;
    hardware)         "${BIN}/stoa-hardware" report --fresh ;;
    smart-test)       "${BIN}/stoa-hardware" smart-test "${@:2}" ;;
    smart-report)     _in_terminal "Stoa — SMART report" "${BIN}/stoa-hardware" smart-report "${@:2}" ;;
    snapshot)         "${BIN}/stoa-pkg-snapshot" ;;
    backup)           "${BIN}/stoa-maintain" --backup ;;
    # In a terminal, not in the background: stoa-maintain --cleanup runs a
    # dozen sudo calls and refuses to start without a terminal to prompt on
    # (each prompt-less sudo would be a failed login to pam_faillock). The
    # preview is output you read, so it gets one too.
    cleanup)          _in_terminal "Stoa — Cleanup" "${BIN}/stoa-maintain" --cleanup ;;
    cleanup-dry-run)  _in_terminal "Stoa — Cleanup preview" "${BIN}/stoa-maintain" --cleanup --dry-run ;;
    # No sudo anywhere in this one, so no terminal is needed either.
    cleanup-user)     "${BIN}/stoa-maintain" --cleanup --user ;;
    schedule)         _in_terminal "Stoa — Schedule cleanup" "${BIN}/stoa-maintain" --schedule ;;
    unschedule)       _in_terminal "Stoa — Remove schedule" "$(readlink -f "${BASH_SOURCE[0]}")" unschedule-run ;;
    unschedule-run)   _unschedule_run ;;
    update-all)       _in_terminal "Stoa — Update all" bash -c "$_UPDATE_ALL" ;;
    update-system)    _in_terminal "Stoa — Update system" bash -c "$_UPDATE_SYSTEM" ;;
    update-aur)       _in_terminal "Stoa — Update AUR" bash -c "$_UPDATE_AUR" ;;
    locksmith)        "${BIN}/stoa-locksmith" ;;
    "")               menu_health ;;
    *)
        echo "Usage: stoa-health [doctor|status|hardware|smart-test|smart-report|snapshot|backup|cleanup|cleanup-dry-run|cleanup-user|schedule|unschedule|update-all|update-system|update-aur|locksmith]"
        exit 1
        ;;
esac
