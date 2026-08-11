#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Enable Stoa Greetd (tuigreet + PAM keyring)   ║
# ║  "The form is the function."                                 ║
# ║                                                              ║
# ║  Replaces the hyprlock-as-greeter flow with a real PAM       ║
# ║  login via greetd + tuigreet, themed in the Stoa palette.    ║
# ║  Side effect: pam_gnome_keyring runs inside the PAM session, ║
# ║  so the keyring (browser passwords, etc.) destrava sozinho.  ║
# ║                                                              ║
# ║  Wires:                                                      ║
# ║    1. /etc/greetd/config.toml — tuigreet bronze, exec        ║
# ║       Hyprland on successful auth                            ║
# ║    2. /etc/pam.d/greetd — pam_gnome_keyring auth + session   ║
# ║    3. greetd.service enabled                                 ║
# ║    4. Stoa autologin drop-in removed (if present)            ║
# ║    5. Hyprland exec-once = hyprlock commented out (boot-     ║
# ║       lock is now greetd's job — uncommented on --disable).  ║
# ║                                                              ║
# ║  Idempotent. Re-run safely. Pass --disable to undo.          ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

STOA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET_USER="${SUDO_USER:-$(whoami)}"

# Colors
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

# Stoa palette (mirrors theme/colors.sh)
BRONZE="#c49a5c"
GOLD="#d4a84b"
MARBLE="#d4cfc4"
STONE="#6e6a62"
BG="#211e19"

GREETD_CONF="/etc/greetd/config.toml"
GREETD_PAM="/etc/pam.d/greetd"
DROPIN_FILE="/etc/systemd/system/getty@tty1.service.d/stoa-autologin.conf"
DROPIN_DIR="/etc/systemd/system/getty@tty1.service.d"
HYPR_CONF="${HOME}/.config/hypr/hyprland.lua"
PROFILE_MARK="# StoaLinux: autostart Hyprland on tty1"
PAM_MARK="# StoaLinux: pam_gnome_keyring (added by enable-stoa-greetd.sh)"
HYPR_MARK="-- disabled by stoa-greetd"
# The autostart line as it appears inside the hl.on("hyprland.start", ...)
# callback in config/hypr/hyprland.lua. Indentation is captured and
# restored so the toggle round-trips to a byte-identical file.
HYPR_LOCK_CALL='hl.exec_cmd("hyprlock")'
HYPR_LOCK_LINE="${HYPR_LOCK_CALL} -- stoa-greetd toggles this line"

_unseed_profile() {
    local rc="$1"
    [ -f "$rc" ] || return 0
    if grep -q "stoa-autostart-hyprland" "$rc" 2>/dev/null; then
        sed -i "/${PROFILE_MARK//\//\\/}/,+1d" "$rc"
        echo -e "  ${O}[✓] $(basename "$rc") snippet removed.${R}"
    fi
}

_disable_autologin() {
    if [ -e "$DROPIN_FILE" ]; then
        sudo rm -f "$DROPIN_FILE"
        sudo rmdir "$DROPIN_DIR" 2>/dev/null || true
        sudo systemctl daemon-reload
        echo -e "  ${O}[✓] Autologin drop-in removed.${R}"
    fi
}

_comment_hyprlock_exec_once() {
    [ -f "$HYPR_CONF" ] || return 0
    if grep -qE '^[[:space:]]*hl\.exec_cmd\("hyprlock"\)' "$HYPR_CONF"; then
        sed -i -E "s|^([[:space:]]*)hl\.exec_cmd\(\"hyprlock\"\).*\$|\1-- ${HYPR_LOCK_CALL} ${HYPR_MARK}|" "$HYPR_CONF"
        echo -e "  ${O}[✓] hyprland.lua: hyprlock autostart commented (greetd handles boot login).${R}"
    fi
}

_uncomment_hyprlock_exec_once() {
    [ -f "$HYPR_CONF" ] || return 0
    if grep -qE '^[[:space:]]*-- hl\.exec_cmd\("hyprlock"\).*disabled by stoa-greetd' "$HYPR_CONF"; then
        sed -i -E "s|^([[:space:]]*)-- hl\.exec_cmd\(\"hyprlock\"\).*disabled by stoa-greetd.*\$|\1${HYPR_LOCK_LINE}|" "$HYPR_CONF"
        echo -e "  ${O}[✓] hyprland.lua: hyprlock autostart restored.${R}"
    fi
}

_install_pkgs() {
    local need=()
    command -v greetd   >/dev/null 2>&1 || need+=(greetd)
    command -v tuigreet >/dev/null 2>&1 || need+=(greetd-tuigreet)
    # gnome-keyring is the package; pam_gnome_keyring.so ships with it
    [ -f /usr/lib/security/pam_gnome_keyring.so ] || need+=(gnome-keyring libsecret)
    if [ ${#need[@]} -gt 0 ]; then
        echo -e "  ${F}Installing: ${need[*]}${R}"
        sudo pacman -S --needed --noconfirm "${need[@]}"
    fi
}

_write_greetd_conf() {
    local theme="border=${BRONZE};text=${MARBLE};prompt=${BRONZE};time=${GOLD};container=${BG};greet=${MARBLE};input=${MARBLE};action=${GOLD};button=${BRONZE}"
    sudo mkdir -p "$(dirname "$GREETD_CONF")"
    sudo tee "$GREETD_CONF" >/dev/null <<EOF
# Managed by StoaLinux — setup/enable-stoa-greetd.sh
# Reverting to autologin: run setup/enable-stoa-greetd.sh --disable

[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session --asterisks --greeting 'Memento Mori.' --cmd Hyprland --theme '${theme}'"
user = "greeter"
EOF
    echo -e "  ${O}[✓] ${GREETD_CONF}${R}"
}

_write_greetd_pam() {
    # Only inject if our marker isn't already present.
    if sudo grep -q "${PAM_MARK}" "$GREETD_PAM" 2>/dev/null; then
        echo -e "  ${S}[~] /etc/pam.d/greetd already wired for gnome-keyring.${R}"
        return
    fi

    # If the file doesn't exist, write a minimal stack that includes system-login
    # plus the keyring hooks. If it exists, append our two lines at the end.
    if [ ! -f "$GREETD_PAM" ]; then
        sudo tee "$GREETD_PAM" >/dev/null <<EOF
# Managed by StoaLinux — setup/enable-stoa-greetd.sh
auth       include    system-login
account    include    system-login
password   include    system-login
session    include    system-login

${PAM_MARK}
auth       optional   pam_gnome_keyring.so
session    optional   pam_gnome_keyring.so auto_start
EOF
    else
        sudo tee -a "$GREETD_PAM" >/dev/null <<EOF

${PAM_MARK}
auth       optional   pam_gnome_keyring.so
session    optional   pam_gnome_keyring.so auto_start
EOF
    fi
    echo -e "  ${O}[✓] ${GREETD_PAM} — pam_gnome_keyring wired.${R}"
}

_unwrite_greetd_pam() {
    [ -f "$GREETD_PAM" ] || return 0
    if sudo grep -q "${PAM_MARK}" "$GREETD_PAM" 2>/dev/null; then
        # Strip our marker block (marker line + the next 2 lines).
        sudo sed -i "/${PAM_MARK//\//\\/}/,+2d" "$GREETD_PAM"
        echo -e "  ${O}[✓] pam_gnome_keyring lines removed from ${GREETD_PAM}.${R}"
    fi
}

if [ "${1:-}" = "--disable" ]; then
    echo ""
    echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "  ${B}║     Disabling Stoa Greetd                           ║${R}"
    echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
    sudo systemctl disable --now greetd.service 2>/dev/null || true
    echo -e "  ${O}[✓] greetd.service stopped and disabled.${R}"
    _unwrite_greetd_pam
    _uncomment_hyprlock_exec_once
    echo ""
    echo -e "  ${F}Note:${R} ${S}${GREETD_CONF} kept on disk for reference.${R}"
    echo -e "        ${S}Re-enable with: ${F}bash ${STOA_DIR}/setup/enable-stoa-greetd.sh${R}"
    echo -e "        ${S}To go back to hyprlock-as-greeter (no PAM keyring):${R}"
    echo -e "        ${F}bash ${STOA_DIR}/setup/enable-stoa-greeter.sh${R}"
    echo ""
    exit 0
fi

echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     Enabling Stoa Greetd                            ║${R}"
echo -e "  ${B}║     greetd → tuigreet (bronze) → PAM → Hyprland      ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

if ! command -v Hyprland >/dev/null 2>&1; then
    echo -e "  ${T}[!] Hyprland not found in PATH. Install it before enabling greetd.${R}"
    exit 1
fi

_install_pkgs

# Tear down the hyprlock-as-greeter wiring if it's currently active —
# the two flows are mutually exclusive (both fight over tty1).
_disable_autologin
_unseed_profile "$HOME/.zprofile"
_unseed_profile "$HOME/.bash_profile"

_write_greetd_conf
_write_greetd_pam
_comment_hyprlock_exec_once

sudo systemctl enable --now greetd.service
echo -e "  ${O}[✓] greetd.service enabled.${R}"

echo ""
echo -e "  ${F}Done. On next boot:${R}"
echo -e "    ${S}1. greetd renders tuigreet in Stoa bronze on tty1${R}"
echo -e "    ${S}2. you type your password — PAM authenticates the session${R}"
echo -e "    ${S}3. pam_gnome_keyring unlocks the keyring with that password${R}"
echo -e "    ${S}4. Hyprland starts; browsers stop asking for the keyring${R}"
echo ""
echo -e "  ${S}To undo: ${F}bash ${STOA_DIR}/setup/enable-stoa-greetd.sh --disable${R}"
echo ""
