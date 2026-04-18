#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Face Recognition Setup (howdy)               ║
# ║  "Know thyself." — Socrates                                 ║
# ║                                                              ║
# ║  Windows Hello-style facial authentication for Linux.        ║
# ║  Works with: lock screen, sudo, login, any PAM service.     ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USAGE:
#   stoa-face setup    — Install howdy + detect camera + enroll face
#   stoa-face add      — Add a new face model
#   stoa-face remove   — Remove a face model
#   stoa-face list     — List enrolled face models
#   stoa-face test     — Test face recognition
#   stoa-face disable  — Disable face recognition (keep data)
#   stoa-face enable   — Re-enable face recognition
#   stoa-face status   — Show current status

# ── Colors ──
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

_banner() {
    echo ""
    echo -e "  ${B}╔══════════════════════════════════════════╗${R}"
    echo -e "  ${B}║     STOA — Face Recognition (howdy)      ║${R}"
    echo -e "  ${B}╚══════════════════════════════════════════╝${R}"
    echo ""
}

_need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "  ${T}[!] This command requires sudo.${R}"
        echo -e "  ${S}    sudo stoa-face $1${R}"
        exit 1
    fi
}

_check_howdy() {
    if ! command -v howdy &>/dev/null; then
        echo -e "  ${T}[!] howdy is not installed.${R}"
        echo -e "  ${S}    Run: stoa-face setup${R}"
        exit 1
    fi
}

# ── Detect camera device ──
_detect_camera() {
    local cam=""

    # Prefer IR camera (Windows Hello compatible)
    if [ -d /sys/class/video4linux ]; then
        for dev in /sys/class/video4linux/video*; do
            local name
            name=$(cat "$dev/name" 2>/dev/null)
            local devpath="/dev/$(basename "$dev")"

            # Check if it's an IR camera
            if echo "$name" | grep -iq "ir\|infrared"; then
                cam="$devpath"
                echo -e "  ${O}[✓] IR camera detected: ${name} (${devpath})${R}" >&2
                echo "$cam"
                return 0
            fi
        done

        # Fallback: first available camera
        for dev in /sys/class/video4linux/video*; do
            local devpath="/dev/$(basename "$dev")"
            # Check if it can capture video (not metadata-only)
            if v4l2-ctl -d "$devpath" --all 2>/dev/null | grep -q "Video Capture"; then
                local name
                name=$(cat "$dev/name" 2>/dev/null)
                cam="$devpath"
                echo -e "  ${S}[~] Webcam detected: ${name} (${devpath})${R}" >&2
                echo "$cam"
                return 0
            fi
        done
    fi

    echo -e "  ${T}[!] No camera detected.${R}" >&2
    return 1
}

# ── Setup PAM for a service ──
_setup_pam() {
    local service="$1"
    local pam_file="/etc/pam.d/${service}"

    if [ ! -f "$pam_file" ]; then
        return 1
    fi

    # Check if howdy is already configured
    if grep -q "pam_howdy.so" "$pam_file" 2>/dev/null; then
        echo -e "  ${S}[~] PAM already configured for ${service}${R}"
        return 0
    fi

    # Backup original before modifying — a broken /etc/pam.d/sudo can
    # lock you out of privilege escalation, so keep a restorable copy.
    local backup="${pam_file}.stoa-bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$pam_file" "$backup" || {
        echo -e "  ${T}[!] Could not create backup ${backup}${R}" >&2
        return 1
    }

    # Stage the new file INSIDE /etc/pam.d so the final mv is a same-
    # filesystem atomic rename (mktemp defaults to /tmp which may be a
    # different mount, making mv a copy+delete that could leave the
    # target truncated on failure).
    local tmpfile
    tmpfile=$(mktemp "${pam_file}.stoa.XXXXXX") || {
        echo -e "  ${T}[!] Could not create temp file next to ${pam_file}${R}" >&2
        return 1
    }
    {
        echo "auth      sufficient pam_howdy.so"
        cat "$pam_file"
    } > "$tmpfile" || {
        rm -f "$tmpfile"
        echo -e "  ${T}[!] Failed to write new PAM config${R}" >&2
        return 1
    }
    chmod 644 "$tmpfile"
    mv "$tmpfile" "$pam_file" || {
        rm -f "$tmpfile"
        echo -e "  ${T}[!] Failed to replace ${pam_file} (backup at ${backup})${R}" >&2
        return 1
    }

    echo -e "  ${O}[✓] PAM configured for ${service} (backup: ${backup})${R}"
}

# ══════════════════════════════════════════════════════════════
# Commands
# ══════════════════════════════════════════════════════════════

cmd_setup() {
    _need_root "setup"
    _banner

    echo -e "  ${F}Step 1: Installing howdy...${R}"
    echo ""

    # Check for AUR helper
    local aur_cmd=""
    if command -v yay &>/dev/null; then
        aur_cmd="yay"
    elif command -v paru &>/dev/null; then
        aur_cmd="paru"
    fi

    if ! command -v howdy &>/dev/null; then
        if [ -n "$aur_cmd" ]; then
            # Run AUR helper as the actual user (not root)
            local real_user="${SUDO_USER:-$USER}"
            su - "$real_user" -c "$aur_cmd -S --needed --noconfirm howdy" || {
                echo -e "  ${T}[!] Failed to install howdy via ${aur_cmd}.${R}"
                echo -e "  ${S}    Install manually: ${aur_cmd} -S howdy${R}"
                exit 1
            }
        else
            echo -e "  ${T}[!] No AUR helper found (yay/paru).${R}"
            echo -e "  ${S}    Install yay first, then run stoa-face setup again.${R}"
            exit 1
        fi
    fi
    echo -e "  ${O}[✓] howdy installed.${R}"
    echo ""

    # ── Detect camera ──
    echo -e "  ${F}Step 2: Detecting camera...${R}"
    local cam_output
    cam_output=$(_detect_camera)
    local cam_device
    cam_device=$(echo "$cam_output" | tail -1)

    if [ -z "$cam_device" ]; then
        echo -e "  ${T}[!] No camera found. Connect a webcam and try again.${R}"
        exit 1
    fi
    echo ""

    # ── Configure howdy ──
    echo -e "  ${F}Step 3: Configuring howdy...${R}"

    local howdy_config="/lib/security/howdy/config.ini"
    if [ -f "$howdy_config" ]; then
        # Set device path
        sed -i "s|^device_path = .*|device_path = ${cam_device}|" "$howdy_config"

        # Set timeout (faster recognition)
        sed -i "s|^timeout = .*|timeout = 4|" "$howdy_config"

        # Set certainty (lower = more strict, 3.5 is good balance)
        sed -i "s|^certainty = .*|certainty = 3.5|" "$howdy_config"

        # Dark threshold for low light
        sed -i "s|^dark_threshold = .*|dark_threshold = 60|" "$howdy_config"

        echo -e "  ${O}[✓] howdy configured (device: ${cam_device})${R}"
    else
        echo -e "  ${T}[!] howdy config not found at ${howdy_config}${R}"
        echo -e "  ${S}    Config may be at a different path. Check: find / -name config.ini -path '*/howdy/*'${R}"
    fi
    echo ""

    # ── Setup PAM ──
    echo -e "  ${F}Step 4: Configuring PAM (face auth for sudo, login, lock screen)...${R}"
    _setup_pam "sudo"
    _setup_pam "login"
    _setup_pam "hyprlock"
    _setup_pam "i3lock"
    _setup_pam "system-auth"
    echo ""

    # ── Enroll face ──
    echo -e "  ${F}Step 5: Enrolling your face...${R}"
    echo -e "  ${S}  Look at the camera. Stay still for a few seconds.${R}"
    echo ""

    howdy add -y || {
        echo ""
        echo -e "  ${T}[!] Face enrollment failed.${R}"
        echo -e "  ${S}    Try again with: sudo howdy add${R}"
        echo -e "  ${S}    Check camera with: sudo howdy test${R}"
        exit 1
    }

    echo ""
    echo -e "  ${O}[✓] Face enrolled successfully!${R}"
    echo ""
    echo -e "  ${B}╔══════════════════════════════════════════╗${R}"
    echo -e "  ${B}║     Face recognition is ready!            ║${R}"
    echo -e "  ${B}╚══════════════════════════════════════════╝${R}"
    echo ""
    echo -e "  ${F}How it works:${R}"
    echo -e "  ${S}  Lock screen   — looks at camera, unlocks if recognized${R}"
    echo -e "  ${S}  sudo          — face replaces password (or type password)${R}"
    echo -e "  ${S}  login         — face authentication at login${R}"
    echo ""
    echo -e "  ${F}Commands:${R}"
    echo -e "  ${S}  stoa-face add     — Add another face model (different angle/light)${R}"
    echo -e "  ${S}  stoa-face test    — Test recognition${R}"
    echo -e "  ${S}  stoa-face list    — List enrolled models${R}"
    echo -e "  ${S}  stoa-face remove  — Remove a model${R}"
    echo -e "  ${S}  stoa-face disable — Temporarily disable${R}"
    echo ""
    echo -e "  ${O}\"Know thyself.\" — Socrates${R}"
    echo ""
}

cmd_add() {
    _need_root "add"
    _check_howdy
    _banner
    echo -e "  ${F}Adding a new face model...${R}"
    echo -e "  ${S}  Look at the camera. Try a different angle or lighting.${R}"
    echo ""
    howdy add -y
    echo ""
    echo -e "  ${O}[✓] Face model added.${R}"
}

cmd_remove() {
    _need_root "remove"
    _check_howdy
    _banner
    echo -e "  ${F}Enrolled face models:${R}"
    echo ""
    howdy list
    echo ""
    read -rp "  Model ID to remove: " model_id
    if [ -n "$model_id" ]; then
        howdy remove "$model_id"
        echo -e "  ${O}[✓] Model removed.${R}"
    fi
}

cmd_list() {
    _need_root "list"
    _check_howdy
    _banner
    echo -e "  ${F}Enrolled face models:${R}"
    echo ""
    howdy list
}

cmd_test() {
    _need_root "test"
    _check_howdy
    _banner
    echo -e "  ${F}Testing face recognition...${R}"
    echo -e "  ${S}  Look at the camera. Press Ctrl+C to stop.${R}"
    echo ""
    howdy test
}

cmd_disable() {
    _need_root "disable"
    _check_howdy
    _banner
    howdy disable 1
    echo -e "  ${O}[✓] Face recognition disabled.${R}"
    echo -e "  ${S}    Re-enable with: sudo stoa-face enable${R}"
}

cmd_enable() {
    _need_root "enable"
    _check_howdy
    _banner
    howdy disable 0
    echo -e "  ${O}[✓] Face recognition enabled.${R}"
}

cmd_status() {
    _banner
    if ! command -v howdy &>/dev/null; then
        echo -e "  ${T}  howdy: not installed${R}"
        echo -e "  ${S}  Run: stoa-face setup${R}"
        echo ""
        return
    fi

    echo -e "  ${O}  howdy: installed${R}"

    # Check PAM
    for svc in sudo hyprlock login; do
        if grep -q "pam_howdy.so" "/etc/pam.d/$svc" 2>/dev/null; then
            echo -e "  ${O}  PAM ($svc): configured${R}"
        else
            echo -e "  ${S}  PAM ($svc): not configured${R}"
        fi
    done

    # Check if disabled
    local howdy_config="/lib/security/howdy/config.ini"
    if [ -f "$howdy_config" ]; then
        if grep -q "^disabled = true" "$howdy_config" 2>/dev/null; then
            echo -e "  ${T}  Status: disabled${R}"
        else
            echo -e "  ${O}  Status: enabled${R}"
        fi
    fi
    echo ""
}

cmd_help() {
    _banner
    echo -e "  ${F}Usage: stoa-face <command>${R}"
    echo ""
    echo -e "  ${B}  setup${R}    ${S}Install howdy + detect camera + enroll face${R}"
    echo -e "  ${B}  add${R}      ${S}Add a new face model${R}"
    echo -e "  ${B}  remove${R}   ${S}Remove a face model${R}"
    echo -e "  ${B}  list${R}     ${S}List enrolled face models${R}"
    echo -e "  ${B}  test${R}     ${S}Test face recognition${R}"
    echo -e "  ${B}  disable${R}  ${S}Disable face recognition${R}"
    echo -e "  ${B}  enable${R}   ${S}Re-enable face recognition${R}"
    echo -e "  ${B}  status${R}   ${S}Show current status${R}"
    echo ""
}

# ── Main ──
case "${1:-help}" in
    setup)   cmd_setup ;;
    add)     cmd_add ;;
    remove)  cmd_remove ;;
    list)    cmd_list ;;
    test)    cmd_test ;;
    disable) cmd_disable ;;
    enable)  cmd_enable ;;
    status)  cmd_status ;;
    *)       cmd_help ;;
esac
