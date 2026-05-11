#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Enable Stoa Greeter                           ║
# ║  "The lock page IS the login."                               ║
# ║                                                              ║
# ║  Wires three pieces together so the machine boots straight   ║
# ║  into a hyprlock prompt themed like Super+Esc:               ║
# ║                                                              ║
# ║    1. systemd autologin on tty1 → drops the user into a      ║
# ║       shell without password (the password is asked next).   ║
# ║    2. ~/.zprofile and ~/.bash_profile → exec Hyprland on     ║
# ║       tty1 (sourced helper at shell/stoa-autostart-hyprland).║
# ║    3. hyprland.conf already runs `exec-once = hyprlock` as   ║
# ║       its first autostart entry, so the session locks before ║
# ║       any other process renders.                             ║
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

DROPIN_DIR="/etc/systemd/system/getty@tty1.service.d"
DROPIN_FILE="${DROPIN_DIR}/stoa-autologin.conf"
PROFILE_MARK="# StoaLinux: autostart Hyprland on tty1"
PROFILE_SRC="${STOA_DIR}/shell/stoa-autostart-hyprland.sh"

_seed_profile() {
    local rc="$1"
    if [ ! -e "$rc" ]; then
        : > "$rc"
    fi
    if grep -q "stoa-autostart-hyprland" "$rc" 2>/dev/null; then
        echo -e "  ${S}[~] $(basename "$rc") already wired.${R}"
        return
    fi
    {
        echo ""
        echo "$PROFILE_MARK"
        echo "[ -f \"${PROFILE_SRC}\" ] && . \"${PROFILE_SRC}\""
    } >> "$rc"
    echo -e "  ${O}[✓] $(basename "$rc") wired to start Hyprland on tty1.${R}"
}

_unseed_profile() {
    local rc="$1"
    [ -f "$rc" ] || return 0
    if grep -q "stoa-autostart-hyprland" "$rc" 2>/dev/null; then
        # Strip the two-line block (marker + source line)
        sed -i "/${PROFILE_MARK//\//\\/}/,+1d" "$rc"
        echo -e "  ${O}[✓] $(basename "$rc") snippet removed.${R}"
    fi
}

_enable_autologin() {
    echo -e "  ${F}Configuring systemd autologin for ${TARGET_USER} on tty1...${R}"
    sudo mkdir -p "$DROPIN_DIR"
    sudo tee "$DROPIN_FILE" >/dev/null <<EOF
# Managed by StoaLinux — setup/enable-stoa-greeter.sh
# Removing this file disables the Stoa greeter (use --disable).
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin ${TARGET_USER} %I \$TERM
EOF
    sudo systemctl daemon-reload
    echo -e "  ${O}[✓] /etc/systemd/system/getty@tty1.service.d/stoa-autologin.conf${R}"
}

_disable_autologin() {
    if [ -e "$DROPIN_FILE" ]; then
        sudo rm -f "$DROPIN_FILE"
        # If the drop-in dir is now empty, clean it up.
        sudo rmdir "$DROPIN_DIR" 2>/dev/null || true
        sudo systemctl daemon-reload
        echo -e "  ${O}[✓] Autologin drop-in removed.${R}"
    else
        echo -e "  ${S}[~] No Stoa autologin drop-in present.${R}"
    fi
}

if [ "${1:-}" = "--disable" ]; then
    echo ""
    echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
    echo -e "  ${B}║     Disabling Stoa Greeter                          ║${R}"
    echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
    echo ""
    _disable_autologin
    _unseed_profile "$HOME/.zprofile"
    _unseed_profile "$HOME/.bash_profile"
    echo ""
    echo -e "  ${F}Note:${R} ${S}hyprlock is still wired as the first exec-once in hyprland.conf —${R}"
    echo -e "        ${S}edit it manually if you no longer want the session to lock on start.${R}"
    echo ""
    exit 0
fi

echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     Enabling Stoa Greeter                           ║${R}"
echo -e "  ${B}║     autologin → Hyprland → hyprlock                  ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

if ! command -v Hyprland >/dev/null 2>&1; then
    echo -e "  ${T}[!] Hyprland not found in PATH. Install it before enabling the greeter.${R}"
    exit 1
fi
if ! command -v hyprlock >/dev/null 2>&1; then
    echo -e "  ${T}[!] hyprlock not found in PATH. Install it before enabling the greeter.${R}"
    exit 1
fi

_enable_autologin
_seed_profile "$HOME/.zprofile"
_seed_profile "$HOME/.bash_profile"

echo ""
echo -e "  ${F}Done. On next boot:${R}"
echo -e "    ${S}1. tty1 logs in as ${TARGET_USER} without prompting${R}"
echo -e "    ${S}2. the login shell exec's Hyprland${R}"
echo -e "    ${S}3. hyprlock renders immediately — type your password to enter${R}"
echo ""
echo -e "  ${S}To undo: ${F}bash ${STOA_DIR}/setup/enable-stoa-greeter.sh --disable${R}"
echo ""
