#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Post-Install (existing Arch)                   ║
# ║  "Do not suffer before the time." — Seneca                   ║
# ║                                                              ║
# ║  Use this script on an existing Arch Linux to install        ║
# ║  all StoaLinux packages and dotfiles.                        ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USAGE:
#   git clone https://github.com/VictorGSchneider/StoaLinux.git
#   cd StoaLinux
#   chmod +x setup/post-install.sh
#   ./setup/post-install.sh

set -e

# ── Colors ──
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     STOA LINUX — Post-Install                        ║${R}"
echo -e "  ${B}║     Hyprland (Wayland) + i3 (Xorg) fallback          ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

# ── Check Arch Linux ──
if [ ! -f /etc/arch-release ]; then
    echo -e "  ${T}[!] This script is for Arch Linux.${R}"
    exit 1
fi

# ── Check that it is not root ──
if [ "$(id -u)" -eq 0 ]; then
    echo -e "  ${T}[!] Do not run as root. The script uses sudo when necessary.${R}"
    exit 1
fi

# ── Packages ──
echo -e "  ${F}StoaLinux packages:${R}"
echo ""

# Hyprland (Wayland — primary)
WAYLAND_PKGS="hyprland waybar swaybg xdg-desktop-portal-hyprland xdg-desktop-portal-gtk"

# i3 (Xorg — fallback)
XORG_PKGS="i3-wm i3status xorg-server xorg-xinit xorg-xrandr picom xclip xdotool polkit-gnome"

# Launcher, notifications
UI_PKGS="rofi dunst libnotify"

# Browser + Notes (AUR)
BROWSER_PKGS="brave-bin"
NOTES_PKGS="obsidian"

# Office (AUR)
OFFICE_PKGS="onlyoffice-bin"

# IDE (AUR)
IDE_PKGS="visual-studio-code-bin"

# Email (AUR)
EMAIL_PKGS="betterbird-bin"

# VPN (AUR)
VPN_PKGS="protonvpn-cli"

# Terminal, editor, wallpapers
APP_PKGS="kitty neovim feh imagemagick"

# Stoic apps (minimalist)
STOA_APPS="zathura zathura-pdf-mupdf mpv imv lf btop thunar thunar-volman thunar-archive-plugin thunar-media-tags-plugin thunar-shares-plugin thunar-vcs-plugin tumbler ffmpegthumbnailer gvfs gvfs-mtp catfish qalculate-gtk calibre"

# Gaming — "Even a wise man needs rest." — Seneca
GAMING_PKGS="steam lib32-vulkan-icd-loader vulkan-icd-loader lib32-mesa"

# Screenshot + Recording — Wayland + Xorg
SCREENSHOT_PKGS="grim slurp maim wf-recorder slop"

# Stoatools (OCR, paste, resize, rename, locksmith)
STOATOOLS_PKGS="tesseract tesseract-data-eng tesseract-data-por lsof wtype python-evdev words"

# Touchpad gestures + mouse DPI/polling + RGB
# GESTURE_PKGS="libinput-gestures"
MOUSE_PKGS="libratbag"
RGB_PKGS="openrgb"

# Cloud Drive (rclone — stream on-demand, Google Drive/OneDrive/Dropbox/S3)
CLOUD_PKGS="rclone"

# App Store (Flatpak — Flathub access from Stoa Store)
STORE_PKGS="flatpak"

# Lock screen
LOCK_PKGS="hyprlock"

# Clipboard — Wayland
CLIPBOARD_PKGS="wl-clipboard cliphist"

# Widgets (eww — AUR, Wayland)
WIDGET_PKGS="eww"

# Shell engine — Noctalia (Quickshell-based, AUR). Replaces waybar+eww+
# dunst+rofi+hyprlock+stoa-osd+cliphist as the visible shell. Pulls in
# the noctalia-qs fork of Quickshell as a dependency, so do NOT also
# install upstream quickshell-git on the same system.
SHELL_PKGS_QS="noctalia-shell"

# Fonts and theme
FONT_PKGS="ttf-jetbrains-mono ttf-font-awesome"

# Toolkit unification (Qt = GTK appearance)
THEME_PKGS="qt5ct qt6ct"

# Firewall
FIREWALL_PKGS="nftables"

# Bluetooth
BLUETOOTH_PKGS="bluez bluez-utils"

# XDG + hardware utils
XDG_PKGS="xdg-utils v4l-utils"

# Night light (blue light filter — Wayland)
NIGHTLIGHT_PKGS="gammastep"

# Power management (power profiles)
POWER_MGMT_PKGS="power-profiles-daemon lm_sensors"

# Printing (CUPS)
PRINT_PKGS="cups cups-pdf system-config-printer"

# Audio equalizer (PipeWire)
EQUALIZER_PKGS="easyeffects"

# WinApps (Windows apps via KVM/QEMU + FreeRDP)
WINAPPS_PKGS="qemu-full libvirt virt-manager dnsmasq edk2-ovmf freerdp"

# Audio + utilities
UTIL_PKGS="pipewire pipewire-pulse pipewire-alsa wireplumber brightnessctl jq curl ffmpeg zip unzip fastfetch"

# DFM — Dotfile Manager (GTK4/libadwaita GUI)
DFM_PKGS="python python-gobject gtk4 libadwaita"

# Developer tools
DEV_PKGS="github-cli gnupg"

# Shell and extras — zsh is the Stoa default login shell; bash stays available
# as a fallback (and is already pulled in by `base`, but listed here for intent).
SHELL_PKGS="zsh bash git base-devel"

ALL_PKGS="$WAYLAND_PKGS $XORG_PKGS $UI_PKGS $APP_PKGS $STOA_APPS $GAMING_PKGS $SCREENSHOT_PKGS $STOATOOLS_PKGS $GESTURE_PKGS $MOUSE_PKGS $RGB_PKGS $CLOUD_PKGS $STORE_PKGS $LOCK_PKGS $CLIPBOARD_PKGS $FIREWALL_PKGS $BLUETOOTH_PKGS $XDG_PKGS $NIGHTLIGHT_PKGS $POWER_MGMT_PKGS $PRINT_PKGS $EQUALIZER_PKGS $WINAPPS_PKGS $DFM_PKGS $FONT_PKGS $THEME_PKGS $UTIL_PKGS $DEV_PKGS $SHELL_PKGS"

echo -e "  ${S}Wayland:    ${WAYLAND_PKGS}${R}"
echo -e "  ${S}Xorg:       ${XORG_PKGS}${R}"
echo -e "  ${S}UI:         ${UI_PKGS}${R}"
echo -e "  ${S}Browser:    ${BROWSER_PKGS} (AUR)${R}"
echo -e "  ${S}Notes:      ${NOTES_PKGS} (AUR)${R}"
echo -e "  ${S}IDE:        ${IDE_PKGS} (AUR)${R}"
echo -e "  ${S}Office:     ${OFFICE_PKGS} (AUR)${R}"
echo -e "  ${S}Email:      ${EMAIL_PKGS} (AUR)${R}"
echo -e "  ${S}VPN:        ${VPN_PKGS} (AUR)${R}"
echo -e "  ${S}Apps:       ${APP_PKGS}${R}"
echo -e "  ${S}Stoic:      ${STOA_APPS}${R}"
echo -e "  ${S}Gaming:     ${GAMING_PKGS}${R}"
echo -e "  ${S}Screenshot: ${SCREENSHOT_PKGS}${R}"
echo -e "  ${S}Stoatools:  ${STOATOOLS_PKGS}${R}"
echo -e "  ${S}Mouse:      ${MOUSE_PKGS}${R}"
echo -e "  ${S}RGB:        ${RGB_PKGS}${R}"
echo -e "  ${S}Cloud:      ${CLOUD_PKGS}${R}"
echo -e "  ${S}Store:      ${STORE_PKGS}${R}"
echo -e "  ${S}Lock:       ${LOCK_PKGS}${R}"
echo -e "  ${S}Clipboard:  ${CLIPBOARD_PKGS}${R}"
echo -e "  ${S}Fonts:      ${FONT_PKGS}${R}"
echo -e "  ${S}Theme:      ${THEME_PKGS}${R}"
echo -e "  ${S}Gestures:   ${GESTURE_PKGS}${R}"
echo -e "  ${S}Firewall:   ${FIREWALL_PKGS}${R}"
echo -e "  ${S}Bluetooth:  ${BLUETOOTH_PKGS}${R}"
echo -e "  ${S}XDG/HW:     ${XDG_PKGS}${R}"
echo -e "  ${S}Night:      ${NIGHTLIGHT_PKGS}${R}"
echo -e "  ${S}Power:      ${POWER_MGMT_PKGS}${R}"
echo -e "  ${S}Print:      ${PRINT_PKGS}${R}"
echo -e "  ${S}Equalizer:  ${EQUALIZER_PKGS}${R}"
echo -e "  ${S}WinApps:    ${WINAPPS_PKGS}${R}"
echo -e "  ${S}DFM:        ${DFM_PKGS}${R}"
echo -e "  ${S}Audio:      ${UTIL_PKGS}${R}"
echo -e "  ${S}Widgets:    ${WIDGET_PKGS} (AUR)${R}"
echo -e "  ${S}Shell:      ${SHELL_PKGS_QS} (AUR — Quickshell-based)${R}"
echo -e "  ${S}Dev:        ${DEV_PKGS}${R}"
echo -e "  ${S}Shell:      ${SHELL_PKGS}${R}"
echo ""

read -rp "  Install packages? (y/n) [y]: " INSTALL_PKGS
INSTALL_PKGS="${INSTALL_PKGS:-y}"

# ── AUR helper ──
# shellcheck source=lib/aur.sh
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib/aur.sh"

if [ "$INSTALL_PKGS" = "y" ]; then
    # Enable multilib repository (required for Steam/lib32 packages)
    if ! grep -q "^\[multilib\]" /etc/pacman.conf 2>/dev/null; then
        echo -e "  ${F}Enabling multilib repository (required for Steam)...${R}"
        sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
        sudo pacman -Syu
        echo -e "  ${O}[✓] multilib enabled.${R}"
    fi

    sudo pacman -S --needed $ALL_PKGS
    echo -e "  ${O}[✓] Official packages installed.${R}"

    # ── AUR packages (common pattern) ──
    _install_aur brave-bin              "Brave Browser"         brave
    _install_aur obsidian               "Obsidian"              obsidian
    _install_aur satty                  "Satty"                 satty
    _install_aur glslviewer             "glslViewer (GPU shaders)" glslViewer
    _install_aur eww                    "eww"                   eww
    _install_aur noctalia-shell         "Noctalia Shell"        noctalia-shell
    _install_aur hyprswitch             "Hyprswitch (Alt+Tab)"  hyprswitch
    _install_aur enpass-bin             "Enpass"                enpass
    _install_aur yacreader              "YACReader"             YACReader
    _install_aur onlyoffice-bin         "OnlyOffice"            desktopeditors
    _install_aur betterbird-bin         "Betterbird"            betterbird
    _install_aur visual-studio-code-bin "Visual Studio Code"    code
    _install_aur howdy-git              "howdy"                 howdy
    if [ "$_aur_fresh" = 1 ]; then
        echo -e "  ${S}    To set up face recognition: sudo stoa-face setup${R}"
    fi
    _install_aur libinput-gestures      "libinput-gestures"     libinput-gestures
    _install_aur protonvpn-cli          "ProtonVPN CLI"         protonvpn-cli
    if [ "$_aur_fresh" = 1 ]; then
        echo -e "  ${S}    To login: protonvpn-cli login <username>${R}"
        echo -e "  ${S}    Or use: Super+I → VPN${R}"
    fi

    # ── AUR packages with custom already-installed checks ──

    # i3lock-color needs the -color variant specifically
    if ! command -v i3lock &>/dev/null || ! i3lock --version 2>&1 | grep -q "color"; then
        _install_aur i3lock-color "i3lock-color"
    else
        echo ""
        echo -e "  ${S}[~] i3lock-color already installed.${R}"
    fi

    # EB Garamond — font, no binary to probe
    if ! fc-list | grep -qi "EB Garamond" 2>/dev/null; then
        _install_aur otf-eb-garamond "EB Garamond font"
    else
        echo ""
        echo -e "  ${S}[~] EB Garamond already installed.${R}"
    fi

    # Colloid icons + cursors — identified by directory presence
    if [ ! -d /usr/share/icons/Colloid-dark ] && [ ! -d "$HOME/.local/share/icons/Colloid-dark" ]; then
        _install_aur colloid-icon-theme-git "Colloid icon theme"
    else
        echo ""
        echo -e "  ${S}[~] Colloid icons already installed.${R}"
    fi
    if [ ! -d /usr/share/icons/Colloid-cursors ] && [ ! -d "$HOME/.local/share/icons/Colloid-cursors" ]; then
        _install_aur colloid-cursors-git "Colloid cursors"
    else
        echo ""
        echo -e "  ${S}[~] Colloid cursors already installed.${R}"
    fi

    # ── Div Acer Manager Max (DAMX) — only on Acer hardware ──
    # DFM is installed by install.sh from the in-tree fork; no separate step needed here.
    echo ""
    _vendor=""
    [ -r /sys/class/dmi/id/sys_vendor ] && _vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
    if [[ "$_vendor" == *Acer* ]]; then
        if [ -d /opt/damx ] || [ -f /etc/systemd/system/damx-daemon.service ]; then
            echo -e "  ${S}[~] Div Acer Manager Max already installed.${R}"
            echo -e "  ${S}    Update later with: stoa-store → Acer apps → Update DAMX${R}"
        else
            echo -e "  ${F}Detected Acer laptop (${_vendor}).${R}"
            read -rp "  Install Div Acer Manager Max (DAMX)? (y/n) [y]: " INSTALL_DAMX
            INSTALL_DAMX="${INSTALL_DAMX:-y}"
            if [ "$INSTALL_DAMX" = "y" ]; then
                echo -e "  ${F}Installing DAMX (downloads installer from GitHub, requires sudo)...${R}"
                _damx_tmp=$(mktemp -d)
                if curl -fsSL \
                    https://raw.githubusercontent.com/PXDiv/Div-Acer-Manager-Max/refs/heads/main/scripts/remoteSetup.sh \
                    -o "$_damx_tmp/setup.sh"; then
                    chmod +x "$_damx_tmp/setup.sh"
                    # remoteSetup.sh is interactive; feed "1" (full install) then "q".
                    (cd "$_damx_tmp" && printf '1\nq\n' | sudo bash ./setup.sh) \
                        && echo -e "  ${O}[✓] DAMX installed — launch with the DAMX command.${R}" \
                        || echo -e "  ${T}[!] DAMX installer reported errors; check the output above.${R}"
                else
                    echo -e "  ${T}[!] Failed to download DAMX installer. Skipping.${R}"
                fi
                rm -rf "$_damx_tmp"
            else
                echo -e "  ${S}[~] DAMX skipped. Install later via: stoa-store → Acer apps${R}"
            fi
        fi
    fi
    unset _vendor _damx_tmp
else
    echo -e "  ${S}[~] Packages skipped.${R}"
fi
echo ""
# ── Input group (required for stoa-predict) ──
if ! groups 2>/dev/null | grep -qw input; then
    echo -e "  ${F}Adding user to 'input' group (for text prediction)...${R}"
    sudo usermod -aG input "$(whoami)"
    echo -e "  ${O}[✓] Added to input group (takes effect after next login).${R}"
else
    echo -e "  ${S}[~] Already in input group.${R}"
fi
# ── ratbagd service (required for mouse DPI/polling control) ──
if command -v ratbagctl &>/dev/null; then
    if ! systemctl is-enabled ratbagd.service &>/dev/null; then
        echo -e "  ${F}Enabling ratbagd (mouse DPI/polling control)...${R}"
        sudo systemctl enable --now ratbagd.service 2>/dev/null
        echo -e "  ${O}[✓] ratbagd enabled.${R}"
    else
        echo -e "  ${S}[~] ratbagd already enabled.${R}"
    fi
fi
echo ""
# ── Flatpak (Flathub) ──
if command -v flatpak &>/dev/null; then
    if ! flatpak remote-list 2>/dev/null | grep -q flathub; then
        echo -e "  ${F}Adding Flathub remote...${R}"
        flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
        echo -e "  ${O}[✓] Flathub configured.${R}"
    else
        echo -e "  ${S}[~] Flathub already configured.${R}"
    fi
fi

# ── Dotfiles ──
echo -e "  ${F}Installing dotfiles...${R}"
echo ""

STOA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "${STOA_DIR}/install.sh"

# ── Shell ──
echo ""
echo -e "  ${F}Shell configuration:${R}"
echo ""
echo -e "  ${S}  1) zsh   (default — login shell; bash kept as fallback)${R}"
echo -e "  ${S}  2) bash  (login shell; zsh rc still seeded)${R}"
echo -e "  ${S}  3) Skip${R}"
read -rp "  Choose [1]: " SHELL_CHOICE
SHELL_CHOICE="${SHELL_CHOICE:-1}"

# Seed both rc files regardless of the login-shell choice. Stoa ships configs
# for both, and we want `bash` invoked from a zsh terminal (or vice versa) to
# still pick up the Stoa prompt/aliases.
_seed_rc() {
    local rc="$1" src="$2"
    if ! grep -q "StoaLinux" "$rc" 2>/dev/null; then
        echo "source ${src}" >> "$rc"
        echo -e "  ${O}[✓] $(basename "$rc") configured.${R}"
    else
        echo -e "  ${S}[~] $(basename "$rc") already contains StoaLinux.${R}"
    fi
}

case "$SHELL_CHOICE" in
    1)
        _seed_rc "$HOME/.zshrc" "${STOA_DIR}/shell/.zshrc"
        _seed_rc "$HOME/.bashrc" "${STOA_DIR}/shell/.bashrc"
        if [ "$SHELL" != "/bin/zsh" ] && [ "$SHELL" != "/usr/bin/zsh" ]; then
            echo -e "  ${S}Changing login shell to zsh...${R}"
            chsh -s /bin/zsh
            echo -e "  ${O}[✓] Login shell changed to zsh.${R}"
        fi
        ;;
    2)
        _seed_rc "$HOME/.bashrc" "${STOA_DIR}/shell/.bashrc"
        _seed_rc "$HOME/.zshrc" "${STOA_DIR}/shell/.zshrc"
        if [ "$SHELL" = "/bin/zsh" ] || [ "$SHELL" = "/usr/bin/zsh" ]; then
            echo -e "  ${S}Changing login shell to bash...${R}"
            chsh -s /bin/bash
            echo -e "  ${O}[✓] Login shell changed to bash.${R}"
        fi
        ;;
    3)
        echo -e "  ${S}[~] Shell skipped.${R}"
        ;;
esac

# ── .xinitrc (Xorg fallback) ──
echo ""
if [ ! -f "$HOME/.xinitrc" ]; then
    echo "exec i3" > "$HOME/.xinitrc"
    echo -e "  ${O}[✓] .xinitrc created (exec i3 — Xorg fallback).${R}"
else
    echo -e "  ${S}[~] .xinitrc already exists.${R}"
fi

# ── Stoa Greeter (autologin → Hyprland → hyprlock) ──
echo ""
echo -e "  ${F}Stoa Greeter — boot straight into hyprlock as the login screen?${R}"
echo -e "  ${S}  Configures tty1 autologin and exec's Hyprland from .zprofile/.bash_profile.${R}"
echo -e "  ${S}  hyprlock runs as the first exec-once, so the password prompt is the greeter.${R}"
read -rp "  Enable now? [y/N]: " GREETER_CHOICE
if [ "${GREETER_CHOICE,,}" = "y" ] || [ "${GREETER_CHOICE,,}" = "yes" ]; then
    bash "${STOA_DIR}/setup/enable-stoa-greeter.sh"
else
    echo -e "  ${S}[~] Skipped. Enable later with: bash ${STOA_DIR}/setup/enable-stoa-greeter.sh${R}"
fi

# ── Done ──
echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     StoaLinux installed!                             ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""
echo -e "  ${F}To start:${R}"
echo -e "  ${B}  Hyprland (Wayland):   Hyprland${R}"
echo -e "  ${B}  i3 (Xorg fallback):   startx${R}"
echo ""
echo -e "  ${F}Stoa commands:${R}"
echo -e "  ${S}  stoa-fetch        — Stoic system fetch${R}"
echo -e "  ${S}  stoa-walls        — Generate wallpapers${R}"
echo -e "  ${S}  stoa-memento      — Memento Mori widget${R}"
echo -e "  ${S}  stoa-quotes-sync  — Fetch Stoic quotes from the internet${R}"
echo -e "  ${S}  stoa-face setup   — Face recognition (Windows Hello-style)${R}"
echo -e "  ${S}  stoa-settings     — Settings panel (Super+I)${R}"
echo -e "  ${S}  stoa-settings     → VPN — ProtonVPN quick connect/country/P2P${R}"
echo -e "  ${S}  stoa-drive         — Cloud Drive manager (Google Drive, OneDrive, etc)${R}"
echo -e "  ${S}  stoa-store        — App store / package manager (Super+A)${R}"
echo -e "  ${S}  stoa-firewall     — Firewall & port monitor (Super+I → Firewall)${R}"
echo -e "  ${S}  stoa-maintain     — Backup, restore & cleanup (Super+I → Maintenance)${R}"
echo -e "  ${S}  stoa-predict      — Text prediction + emoji suggestions (Super+Shift+S)${R}"
echo -e "  ${S}  stoa-settings     → Fan & Performance — fan mode, speed, profiles, GPU (Super+I → Power → Fan)${R}"
echo -e "  ${S}  stoa-winapps      — Windows apps via KVM/RDP (Super+W)${R}"
echo -e "  ${S}  dfm               — Dotfile Manager GUI (Super+G)${R}"
if [ -d /opt/damx ] || [ -f /etc/systemd/system/damx-daemon.service ]; then
    echo -e "  ${S}  DAMX              — Div Acer Manager Max (Acer profiles, fans, battery)${R}"
    echo -e "  ${S}                      updates via: stoa-store → Acer apps → Update DAMX${R}"
fi
echo ""
echo -e "  ${F}Leisure:${R}"
echo -e "  ${S}  steam             — Gaming (Proton enabled for Windows games)${R}"
echo -e "  ${S}  calibre           — eBook library manager and reader${R}"
echo -e "  ${S}  YACReader         — Comic book reader (CBR/CBZ)${R}"
echo ""
echo -e "  ${F}Stoatools (also available as Thunar right-click actions):${R}"
echo -e "  ${S}  stoa-ocr          — Extract text from screen or image (OCR)${R}"
echo -e "  ${S}  stoa-paste        — Paste with advanced formatting${R}"
echo -e "  ${S}  stoa-resize       — Batch resize images${R}"
echo -e "  ${S}  stoa-rename       — Rename files with regex${R}"
echo -e "  ${S}  stoa-locksmith    — See who is locking a file${R}"
echo ""
echo -e "  ${O}\"The path of the wise is prepared.\" — Seneca${R}"
echo ""
