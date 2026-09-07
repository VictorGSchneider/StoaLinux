#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Doctor (Health Check)                         ║
# ║  "Know thyself." — inscribed at Delphi                       ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Runs at startup to verify that all binaries and services
# required by Stoa scripts are present and functional.
# Reports issues via desktop notifications (notify-send → Noctalia).

set -o pipefail

STOA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa"
LOG="${STOA_DIR}/doctor.log"
mkdir -p "$STOA_DIR"

ISSUES=()
WARNINGS=()

_ok()   { echo "[OK]   $1" >> "$LOG"; }
_warn() { echo "[WARN] $1" >> "$LOG"; WARNINGS+=("$1"); }
_fail() { echo "[FAIL] $1" >> "$LOG"; ISSUES+=("$1"); }

_check_bin() {
    local bin="$1"
    local desc="${2:-$1}"
    if command -v "$bin" &>/dev/null; then
        _ok "$desc ($bin)"
    else
        _fail "$desc — '$bin' not found"
    fi
}

_check_optional() {
    local bin="$1"
    local desc="${2:-$1}"
    if command -v "$bin" &>/dev/null; then
        _ok "$desc ($bin)"
    else
        _warn "$desc — '$bin' not found (optional)"
    fi
}

# Like _check_bin, but also accepts the binary at an explicit path.
#
# This script runs from the Hyprland session, whose PATH does not include
# ~/.local/bin — which is exactly why every ~/.local/bin entry point in
# config/hypr/hyprland.lua is invoked by absolute path, this script included.
# A bare `command -v` therefore reports a perfectly healthy user-local
# install as missing.
_check_bin_at() {
    local bin="$1"
    local path="$2"
    local desc="${3:-$1}"
    if command -v "$bin" &>/dev/null || [ -x "$path" ]; then
        _ok "$desc ($bin)"
    else
        _fail "$desc — '$bin' not found (looked on PATH and at ${path})"
    fi
}

# ── Start ──
{
    echo "════════════════════════════════════════"
    echo "  Stoa Doctor — $(date '+%Y-%m-%d %H:%M:%S')"
    echo "════════════════════════════════════════"
} > "$LOG"

# ══════════════════════════════════════════
#   Core binaries
# ══════════════════════════════════════════

_check_bin notify-send  "Notifications (libnotify)"
_check_bin jq           "JSON parser (jq)"
_check_bin eww          "Widgets (eww)"
_check_bin noctalia     "Shell (Noctalia)"

# ── Display / WM (Stoa is Wayland-only — Hyprland is the only session) ──
_check_bin hyprctl      "Hyprland control (hyprctl)"
_check_bin grim         "Screenshot (grim)"
_check_bin slurp        "Region select (slurp)"
_check_bin wf-recorder  "Screen recording (wf-recorder)"
_check_bin wl-paste     "Clipboard (wl-clipboard)"
_check_optional satty   "Screenshot editor (satty)"
# Noctalia v5 ships its own polkit agent (shell.polkit_agent in
# config.toml), so a standalone agent is no longer required — only
# accepted as an alternative when the shell is not the one running.
if command -v noctalia &>/dev/null \
    || command -v hyprpolkitagent &>/dev/null \
    || command -v lxpolkit &>/dev/null; then
    echo "[OK] Polkit agent present" >> "$LOG"
else
    echo "[WARN] No polkit authentication agent found" >> "$LOG"
fi

# ── Did the Stoa polkit rule actually load? ──
# An agent being present says nothing about the rule being in effect, and
# this failure is silent by construction: the file is installed, the agent
# answers, every check reads green, and yet not one of the wheel-group
# grants applies — polkit falls back to its defaults and asks for a
# password on things Stoa means to allow.
#
# Seen in the wild: install.sh symlinks the rule into
# /etc/polkit-1/rules.d/, and polkitd drops privileges to the unprivileged
# "polkitd" user, which cannot follow that link into $HOME. polkitd says
# so once, at boot, and then never again:
#     polkitd[N]: Error loading script /etc/polkit-1/rules.d/50-stoa-wheel.rules
#
# The journal is authoritative, so ask it first. Members of wheel can read
# the system journal through systemd's ACLs; where that is not true, fall
# back to reproducing polkitd's own read — every directory on the resolved
# path must be world-executable and the file world-readable.
_POLKIT_RULE="/etc/polkit-1/rules.d/50-stoa-wheel.rules"

# /etc/polkit-1/rules.d is root:polkitd 0750 — polkit locks it down so that
# ordinary users cannot read the rules. This script runs as the user, so
# `[ -e ]` on anything inside it is false for a rule that is perfectly well
# installed, and a naive presence test reports "not installed" for a healthy
# machine. Ask the journal instead: polkitd names the file when it refuses
# it, and members of wheel read the system journal through systemd's ACLs.
#
# Probe that access with an entry PID 1 always writes — journalctl exits 0
# for an unprivileged reader too, it just shows nothing, so the exit code
# cannot be used to tell access apart from silence.
if [ -n "$(journalctl -b -n1 --no-pager -q _PID=1 2>/dev/null)" ]; then
    # Only the running instance counts. Grepping the whole boot keeps
    # reporting a failure that has already been fixed: install.sh repairs
    # the rule, polkit is restarted and loads it cleanly, and the original
    # complaint still sits in this boot's journal until the next reboot.
    # polkitd prints "Started polkitd version N" on every start, so drop
    # everything up to and including the last one. With no such marker the
    # whole log is kept, which errs toward reporting.
    if journalctl -b _COMM=polkitd --no-pager -q -o cat 2>/dev/null \
            | awk '/Started polkitd version/ { out=""; next }
                   { out = out $0 ORS }
                   END { printf "%s", out }' \
            | grep -qF "Error loading script ${_POLKIT_RULE}"; then
        _fail "polkitd refused ${_POLKIT_RULE} — no wheel-group grant is in effect"
    else
        # Deliberately worded as what was observed. polkitd says nothing when
        # a rule loads, and says nothing when there is no rule at all, so a
        # quiet journal cannot distinguish the two from here.
        _ok "Stoa polkit rule — polkitd raised no complaint this boot"
    fi
elif [ -e "$_POLKIT_RULE" ]; then
    # No journal access, but the rule is readable from here (a machine that
    # loosened rules.d). Reproduce polkitd's own read: it drops privileges to
    # the unprivileged "polkitd" user, so every directory on the resolved
    # path must be world-executable and the file world-readable. That is
    # exactly what install.sh's old symlink into $HOME failed.
    #
    # stat -c %A renders the mode as drwxr-xr-x; the last three characters
    # are the "other" triad. A directory passes on x or t (sticky), a file
    # on r.
    _other_has() {   # _other_has <path> <r|x>
        local mode; mode="$(stat -c '%A' "$1" 2>/dev/null)" || return 0
        [ -z "$mode" ] && return 0
        case "$2" in
            r) [ "${mode: -3:1}" = "r" ] ;;
            x) case "${mode: -1}" in x|t) return 0 ;; *) return 1 ;; esac ;;
        esac
    }

    _rule_target="$(readlink -f "$_POLKIT_RULE" 2>/dev/null || echo "$_POLKIT_RULE")"
    _unreadable=""
    if ! _other_has "$_rule_target" r; then
        _unreadable="$_rule_target"
    else
        _dir="$(dirname "$_rule_target")"
        while [ "$_dir" != "/" ] && [ -n "$_dir" ]; do
            _other_has "$_dir" x || { _unreadable="$_dir"; break; }
            _dir="$(dirname "$_dir")"
        done
    fi

    if [ -n "$_unreadable" ]; then
        _fail "polkitd cannot read ${_POLKIT_RULE} (blocked at ${_unreadable}) — rule not in effect"
    else
        # install.sh copies this rule rather than symlinking it (polkitd
        # cannot follow a link into $HOME), so unlike every other Stoa
        # config it does not follow a `git pull`. Say so when it drifts.
        _repo_rule="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")/config/polkit/50-stoa-wheel.rules"
        if [ -f "$_repo_rule" ] && ! cmp -s "$_repo_rule" "$_POLKIT_RULE" 2>/dev/null; then
            _warn "Installed polkit rule differs from the repo — run install.sh"
        else
            _ok "Stoa polkit rule loaded"
        fi
    fi
else
    # Neither readable. Saying nothing beats claiming the rule is missing:
    # rules.d being unreadable is the normal, correct state.
    echo "[INFO] Stoa polkit rule: not verifiable from this session (no journal access, ${_POLKIT_RULE} not readable)" >> "$LOG"
fi

# ── Hyprland lua config installed? ──
# Stoa ships hyprland.lua and install.sh symlinks it. Pulling the repo
# past the lua migration without re-running install.sh leaves no
# hyprland.lua and a dangling hyprland.conf symlink from the old
# install, so Hyprland starts with no config at all and writes its own
# stub — the session comes up with upstream defaults instead of Stoa,
# which reads as "my desktop reverted" rather than a missing symlink.
_HYPR_CFG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
if [ ! -e "${_HYPR_CFG_DIR}/hyprland.lua" ]; then
    _warn "hyprland.lua is not installed (${_HYPR_CFG_DIR}) — run install.sh"
elif grep -qs 'autogenerated' "${_HYPR_CFG_DIR}/hyprland.conf"; then
    # hyprland.lua wins when both exist, so this is not breaking the
    # session — but the stub means Hyprland booted configless at least
    # once, and the stale .conf is worth clearing out.
    _warn "Stale autogenerated hyprland.conf alongside hyprland.lua — safe to delete"
fi

# ── Hyprland version check ──
if command -v hyprctl &>/dev/null; then
    HYPR_VER=$(hyprctl version -j 2>/dev/null | jq -r '.tag // .version // empty' 2>/dev/null | head -1)
    if [ -n "$HYPR_VER" ]; then
        echo "[INFO] Hyprland version: ${HYPR_VER}" >> "$LOG"

        # Test hyprctl getoption format (changed between versions)
        _test_output=$(hyprctl getoption general:border_size 2>/dev/null)
        if echo "$_test_output" | grep -q "int:"; then
            echo "[INFO] hyprctl getoption: legacy format (int:/float:/str:)" >> "$LOG"
            echo "legacy" > "${STOA_DIR}/hyprctl-format"
        elif echo "$_test_output" | grep -qE "^[0-9]"; then
            echo "[INFO] hyprctl getoption: new format (raw value)" >> "$LOG"
            echo "raw" > "${STOA_DIR}/hyprctl-format"
        else
            _warn "hyprctl getoption returned unexpected format"
            echo "unknown" > "${STOA_DIR}/hyprctl-format"
        fi

        # Save version for scripts to check
        echo "$HYPR_VER" > "${STOA_DIR}/hyprland-version"

        # ── Lua config floor ──
        # Stoa ships config/hypr/hyprland.lua. Hyprland only reads it
        # from 0.55 onward; older builds silently ignore it and fall
        # back to their own defaults (or a stale hyprland.conf), which
        # looks like "my whole desktop reverted" rather than an error.
        _hypr_major=$(echo "$HYPR_VER" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f1)
        _hypr_minor=$(echo "$HYPR_VER" | grep -oE '[0-9]+\.[0-9]+' | head -1 | cut -d. -f2)
        if [ -n "$_hypr_minor" ] \
            && [ "${_hypr_major:-0}" -eq 0 ] && [ "$_hypr_minor" -lt 55 ]; then
            _warn "Hyprland ${HYPR_VER} predates 0.55 — hyprland.lua is ignored. Upgrade Hyprland."
        fi
    else
        _warn "Could not detect Hyprland version"
    fi
fi

# ── Settings/Store standalone apps (replace the old rofi menus) ──
_check_optional wdisplays           "Display layout (wdisplays)"
_check_optional pwvucontrol         "Audio mixer (pwvucontrol)"
_check_optional nm-connection-editor "Network editor (nm-connection-editor)"
_check_optional blueman-manager     "Bluetooth manager (blueman)"
_check_optional gnome-disks         "Disk utility (gnome-disk-utility)"
_check_optional nwg-look            "GTK theme editor (nwg-look)"
_check_optional bauh                "Package manager GUI (bauh)"

# ── Audio ──
_check_bin wpctl        "Audio control (WirePlumber)"
_check_optional pactl   "PulseAudio ctl (pactl)"

# ── Brightness ──
_check_bin brightnessctl "Brightness control"

# ── Network ──
_check_bin nmcli        "NetworkManager (nmcli)"
_check_optional iwctl   "iwd Wi-Fi (iwctl)"
_check_optional bluetoothctl "Bluetooth (bluetoothctl)"

# ── File manager ──
_check_bin thunar       "File manager (Thunar)"
_check_bin yad          "Stoatools dialogs (yad)"

# ── Terminal ──
_terminal_found=""
for _t in kitty alacritty foot wezterm ghostty xterm konsole gnome-terminal xfce4-terminal; do
    if command -v "$_t" &>/dev/null; then
        _terminal_found="$_t"
        break
    fi
done
if [ -n "$_terminal_found" ]; then
    _ok "Terminal ($_terminal_found)"
else
    _warn "Terminal — no terminal emulator found"
fi
unset _t _terminal_found

# ── Utilities ──
_check_bin curl         "HTTP client (curl)"
_check_bin tesseract    "OCR (tesseract)"

# ── Dotfile Manager (Super+G) ──
_check_bin_at dfm "${HOME}/.local/bin/dfm" "Dotfile Manager (dfm)"

# ══════════════════════════════════════════
#   Service checks
# ══════════════════════════════════════════

# PipeWire
if pgrep -x pipewire &>/dev/null; then
    _ok "PipeWire is running"
else
    _warn "PipeWire is not running — audio may not work"
fi

# Notification daemon — Noctalia owns org.freedesktop.Notifications on
# the Hyprland/Wayland path.
if pgrep -x 'noctalia' &>/dev/null; then
    _ok "Noctalia is running (notifications)"
else
    _warn "Noctalia is not running — notifications won't show"
fi

# ══════════════════════════════════════════
#   Directories
# ══════════════════════════════════════════

for dir in \
    "${HOME}/Pictures/screenshots" \
    "${HOME}/Videos/recordings" \
    "${STOA_DIR}/wallpapers" \
    "${STOA_DIR}/pkg-snapshots"; do
    if [ -d "$dir" ]; then
        _ok "Directory exists: $dir"
    else
        mkdir -p "$dir"
        _warn "Created missing directory: $dir"
    fi
done

# ══════════════════════════════════════════
#   Report
# ══════════════════════════════════════════

{
    echo "────────────────────────────────────────"
    echo "  Issues: ${#ISSUES[@]}  |  Warnings: ${#WARNINGS[@]}"
    echo "────────────────────────────────────────"
} >> "$LOG"

# Notify user of problems
if [ ${#ISSUES[@]} -gt 0 ]; then
    msg="Missing: ${#ISSUES[@]} required\n"
    for issue in "${ISSUES[@]:0:5}"; do
        msg+="• ${issue}\n"
    done
    [ ${#ISSUES[@]} -gt 5 ] && msg+="… and $((${#ISSUES[@]} - 5)) more (see doctor.log)"

    if command -v notify-send &>/dev/null; then
        notify-send -r 9990 -u critical -t 10000 "Stoa Doctor" "$msg"
    else
        echo -e "STOA DOCTOR:\n$msg" >&2
    fi
elif [ ${#WARNINGS[@]} -gt 0 ]; then
    if command -v notify-send &>/dev/null; then
        notify-send -r 9990 -u low -t 5000 "Stoa Doctor" "${#WARNINGS[@]} warnings — see ~/.config/stoa/doctor.log"
    fi
fi

# Quiet exit if all good
[ ${#ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ] && {
    echo "[INFO] All checks passed." >> "$LOG"
}

exit 0
