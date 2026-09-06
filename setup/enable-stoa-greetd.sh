#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Enable Stoa Greetd (PAM keyring)              ║
# ║  "The form is the function."                                 ║
# ║                                                              ║
# ║  Replaces the hyprlock-as-greeter flow with a real PAM       ║
# ║  login via greetd. Greeter is picked automatically:          ║
# ║    noctalia-greeter → matches the Noctalia v5 shell          ║
# ║    tuigreet         → TUI fallback, Stoa bronze theme        ║
# ║  Force one with --greeter=noctalia | --greeter=tuigreet.     ║
# ║  Side effect: pam_gnome_keyring runs inside the PAM session, ║
# ║  so the keyring (browser passwords, etc.) destrava sozinho.  ║
# ║                                                              ║
# ║  Wires:                                                      ║
# ║    1. /etc/greetd/config.toml — greeter + Hyprland session   ║
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

# Colors
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

# ── Check that it is not root ──
# Everything privileged below goes through sudo on purpose: the rest writes
# into the invoking user's HOME (profile snippets, hyprland.lua, the keyring
# default). Under sudo, HOME is root's — the system half gets configured and
# the user half silently does not, leaving a machine that autologins into a
# bare shell.
if [ "$(id -u)" -eq 0 ]; then
    echo -e "  ${T}[!] Do not run as root. The script uses sudo when necessary.${R}"
    exit 1
fi

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
KEYRING_DEFAULT_FILE="${HOME}/.local/share/keyrings/default"
NOCTALIA_CLIPBOARD_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/noctalia/clipboard"
PROFILE_MARK="# StoaLinux: autostart Hyprland on tty1"
PROFILE_MARK_END="# StoaLinux: end autostart Hyprland block"
PAM_MARK="# StoaLinux: pam_gnome_keyring (added by enable-stoa-greetd.sh)"
HYPR_MARK="-- disabled by stoa-greetd"
# The autostart line as it appears inside the hl.on("hyprland.start", ...)
# callback in config/hypr/hyprland.lua. Indentation is captured and
# restored so the toggle round-trips to a byte-identical file.
HYPR_LOCK_CALL='hl.exec_cmd("hyprlock")'
HYPR_LOCK_LINE="${HYPR_LOCK_CALL} -- stoa-greetd toggles this line"

# Must stay in sync with enable-stoa-greeter.sh's copy: the greeter seeds a
# marker-delimited block, and deleting only "marker + 1 line" would leave a
# dangling `fi` behind — a syntax error in the login shell's profile.
# Handles the legacy two-line form too, for profiles seeded before that.
_unseed_profile() {
    local rc="$1"
    [ -f "$rc" ] || return 0
    grep -q "stoa-autostart-hyprland" "$rc" 2>/dev/null || return 0
    # Pick the form that is actually there. Running the block delete on a
    # legacy profile makes a range whose end marker never matches, and sed
    # deletes from the start marker to end of file — taking everything the
    # user keeps below the block with it.
    if grep -qF -- "$PROFILE_MARK_END" "$rc"; then
        sed -i "\|^${PROFILE_MARK}\$|,\|^${PROFILE_MARK_END}\$|d" "$rc"
    else
        sed -i "\|^${PROFILE_MARK}\$|,+1d" "$rc"
    fi
    echo -e "  ${O}[✓] $(basename "$rc") snippet removed.${R}"
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
        sed -i --follow-symlinks -E "s|^([[:space:]]*)hl\.exec_cmd\(\"hyprlock\"\).*\$|\1-- ${HYPR_LOCK_CALL} ${HYPR_MARK}|" "$HYPR_CONF"
        echo -e "  ${O}[✓] hyprland.lua: hyprlock autostart commented (greetd handles boot login).${R}"
    fi
}

_uncomment_hyprlock_exec_once() {
    [ -f "$HYPR_CONF" ] || return 0
    if grep -qE '^[[:space:]]*-- hl\.exec_cmd\("hyprlock"\).*disabled by stoa-greetd' "$HYPR_CONF"; then
        sed -i --follow-symlinks -E "s|^([[:space:]]*)-- hl\.exec_cmd\(\"hyprlock\"\).*disabled by stoa-greetd.*\$|\1${HYPR_LOCK_LINE}|" "$HYPR_CONF"
        echo -e "  ${O}[✓] hyprland.lua: hyprlock autostart restored.${R}"
    fi
}

# Which greeter to wire. Empty = auto-detect, preferring noctalia-greeter
# so the login screen matches the Noctalia v5 shell. Set by --greeter=.
GREETER="${GREETER:-}"

_detect_greeter() {
    if [ -n "$GREETER" ]; then
        echo "$GREETER"
        return 0
    fi
    if command -v noctalia-greeter-session >/dev/null 2>&1; then
        echo noctalia
    else
        echo tuigreet
    fi
}

_install_pkgs() {
    local greeter="$1"
    local need=()
    command -v greetd >/dev/null 2>&1 || need+=(greetd)
    # gnome-keyring is the package; pam_gnome_keyring.so ships with it
    [ -f /usr/lib/security/pam_gnome_keyring.so ] || need+=(gnome-keyring libsecret)
    if [ ${#need[@]} -gt 0 ]; then
        echo -e "  ${F}Installing: ${need[*]}${R}"
        sudo pacman -S --needed --noconfirm "${need[@]}"
    fi

    if [ "$greeter" = "tuigreet" ]; then
        command -v tuigreet >/dev/null 2>&1 || \
            sudo pacman -S --needed --noconfirm greetd-tuigreet
        return 0
    fi

    # noctalia-greeter lives in the AUR, so pacman cannot reach it.
    if command -v noctalia-greeter-session >/dev/null 2>&1; then
        return 0
    fi
    local aur=""
    command -v yay  >/dev/null 2>&1 && aur=yay
    [ -z "$aur" ] && command -v paru >/dev/null 2>&1 && aur=paru
    if [ -n "$aur" ]; then
        echo -e "  ${F}Installing noctalia-greeter via ${aur}...${R}"
        "$aur" -S --needed --noconfirm noctalia-greeter
    else
        echo -e "  ${T}[!] noctalia-greeter not installed and no AUR helper (yay/paru) found.${R}"
        echo -e "  ${S}    Install it, or run with --greeter=tuigreet.${R}"
        exit 1
    fi
}

_write_greetd_conf() {
    local greeter="$1"
    local command

    if [ "$greeter" = "noctalia" ]; then
        # noctalia-greeter-session starts the bundled wlroots compositor and
        # runs the greeter UI inside it. Flags for the greeter itself go
        # after `--`; --session takes the desktop-entry Name (not the
        # .desktop filename), which for Hyprland is "Hyprland".
        # `noctalia-greeter sessions` lists the valid names.
        local bin
        bin="$(command -v noctalia-greeter-session)"
        command="${bin} -- --session Hyprland"
    else
        local theme="border=${BRONZE};text=${MARBLE};prompt=${BRONZE};time=${GOLD};container=${BG};greet=${MARBLE};input=${MARBLE};action=${GOLD};button=${BRONZE}"
        command="tuigreet --time --remember --remember-session --asterisks --greeting 'Memento Mori.' --cmd Hyprland --theme '${theme}'"
    fi

    sudo mkdir -p "$(dirname "$GREETD_CONF")"
    sudo tee "$GREETD_CONF" >/dev/null <<EOF
# Managed by StoaLinux — setup/enable-stoa-greetd.sh
# Greeter: ${greeter}
# Reverting to autologin: run setup/enable-stoa-greetd.sh --disable

[terminal]
vt = 1

[default_session]
command = "${command}"
user = "greeter"
EOF
    echo -e "  ${O}[✓] ${GREETD_CONF} (greeter: ${greeter})${R}"
}

# Push the shell's look to the greeter. Noctalia v5 owns this: Sync copies
# wallpaper, palette, theme mode, font and monitor layout into
# /var/lib/noctalia-greeter, escalating through pkexec/run0.
#
# shell.greeter_sync.auto_sync in config/noctalia/config.toml keeps it
# current afterwards; this is only the first push, since auto-sync fires on
# change and a fresh install has not changed anything yet.
#
# Deliberately NOT writing a greeter.toml with an [appearance.palette]:
# upstream documents that a declarative greeter.toml is never overwritten by
# Sync and wins over it, so pinning colours there would freeze the login
# screen and silently ignore every later palette change.
_sync_greeter_appearance() {
    if ! command -v noctalia >/dev/null 2>&1; then
        return 0
    fi
    if ! pgrep -x noctalia >/dev/null 2>&1; then
        echo -e "  ${S}[~] Noctalia is not running — skipping the first greeter sync.${R}"
        echo -e "  ${S}    Run once from your session: ${F}noctalia msg greeter-sync${R}"
        return 0
    fi
    echo -e "  ${F}Syncing the Stoa look to the greeter (may prompt via polkit)...${R}"
    if noctalia msg greeter-sync >/dev/null 2>&1; then
        echo -e "  ${O}[✓] Greeter appearance synced from the shell.${R}"
    else
        echo -e "  ${S}[~] Sync did not complete. Retry from your session with:${R}"
        echo -e "  ${S}    ${F}noctalia msg greeter-sync${R}"
        echo -e "  ${S}    or Settings → Security → Noctalia Greeter → Sync Now.${R}"
    fi
}

# pam_gnome_keyring only ever unlocks the keyring literally named "login" —
# it has no idea what the Secret Service's current default collection is.
# If something else (e.g. a leftover "Default_keyring" from an older
# gnome-keyring bootstrap, or a keyring created by hand before this script
# ever ran) is set as the default, PAM auto-unlocks "login" successfully on
# every boot while every app asking the Secret Service for "the default
# collection" — Noctalia's encrypted clipboard pins included — still finds
# it locked. No visible error anywhere: writes just silently never land.
#
# Only touches the file when it already exists and disagrees with "login" —
# a brand-new account with no keyrings yet gets "login" as the default the
# first time pam_gnome_keyring creates one, with nothing to correct here.
_fix_keyring_default() {
    [ -f "$KEYRING_DEFAULT_FILE" ] || return 0

    local current
    current="$(cat "$KEYRING_DEFAULT_FILE" 2>/dev/null)"
    [ "$current" = "login" ] && return 0

    cp "$KEYRING_DEFAULT_FILE" "${KEYRING_DEFAULT_FILE}.bak"
    printf '%s' "login" > "$KEYRING_DEFAULT_FILE"
    echo -e "  ${O}[✓] Default keyring: '${current}' -> 'login' (the one pam_gnome_keyring actually unlocks).${R}"

    # Any encrypted Noctalia clipboard history on disk was sealed with a
    # storage key stored under the OLD default collection — now
    # unreachable, since that collection is no longer what "default" means.
    # Noctalia's storage_key_provider refuses to mint a replacement key
    # while it sees encrypted data it can't decrypt (a corruption guard),
    # so persistence stays permanently broken until that stale state is
    # out of the way. Moved aside rather than deleted; whatever was pinned
    # under the old broken default was never actually persisted anyway
    # (the collection was locked the whole time), so there is nothing
    # recoverable in it — this is just being cautious with someone else's
    # files rather than assuming that.
    if [ -d "$NOCTALIA_CLIPBOARD_STATE" ]; then
        mv "$NOCTALIA_CLIPBOARD_STATE" "${NOCTALIA_CLIPBOARD_STATE}.bak-$(date +%s)"
        echo -e "  ${O}[✓] Cleared orphaned encrypted clipboard state so Noctalia can mint a fresh key.${R}"
    fi
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

DISABLE=0
for arg in "$@"; do
    case "$arg" in
        --disable) DISABLE=1 ;;
        --greeter=noctalia|--greeter=tuigreet) GREETER="${arg#--greeter=}" ;;
        --greeter=*)
            echo -e "  ${T}[!] Unknown greeter: ${arg#--greeter=} (use noctalia or tuigreet)${R}" >&2
            exit 1
            ;;
    esac
done

# Scanned rather than checked as $1: --greeter= may legitimately come first.
if [ "$DISABLE" -eq 1 ]; then
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
echo -e "  ${B}║     greetd → greeter → PAM → Hyprland                ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

if ! command -v Hyprland >/dev/null 2>&1; then
    echo -e "  ${T}[!] Hyprland not found in PATH. Install it before enabling greetd.${R}"
    exit 1
fi

GREETER_CHOICE="$(_detect_greeter)"
echo -e "  ${F}Greeter:${R} ${GREETER_CHOICE}"
_install_pkgs "$GREETER_CHOICE"

# Tear down the hyprlock-as-greeter wiring if it's currently active —
# the two flows are mutually exclusive (both fight over tty1).
_disable_autologin
_unseed_profile "$HOME/.zprofile"
_unseed_profile "$HOME/.bash_profile"

_write_greetd_conf "$GREETER_CHOICE"
if [ "$GREETER_CHOICE" = "noctalia" ]; then
    _sync_greeter_appearance
fi
_write_greetd_pam
_fix_keyring_default
_comment_hyprlock_exec_once

sudo systemctl enable --now greetd.service
echo -e "  ${O}[✓] greetd.service enabled.${R}"

echo ""
echo -e "  ${F}Done. On next boot:${R}"
echo -e "    ${S}1. greetd renders ${GREETER_CHOICE} on tty1${R}"
echo -e "    ${S}2. you type your password — PAM authenticates the session${R}"
echo -e "    ${S}3. pam_gnome_keyring unlocks the keyring with that password${R}"
echo -e "    ${S}4. Hyprland starts; browsers stop asking for the keyring${R}"
echo ""
echo -e "  ${S}To undo: ${F}bash ${STOA_DIR}/setup/enable-stoa-greetd.sh --disable${R}"
echo ""
