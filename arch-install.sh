#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Arch Install                                  ║
# ║  "Action is the mark of wisdom." — Seneca                   ║
# ║                                                              ║
# ║  Uses the standard archinstall with StoaLinux config.        ║
# ║  Disks and user are configured manually via TUI.             ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USAGE (from Arch Linux live ISO):
#
#   curl -LO https://raw.githubusercontent.com/VictorGSchneider/StoaLinux/main/arch-install.sh
#   chmod +x arch-install.sh
#   ./arch-install.sh
#
# What happens:
#   1. Downloads StoaLinux JSON config
#   2. Opens standard archinstall with pre-selected packages
#      → Disks, user and password are chosen by YOU in the TUI
#      → Bootloader, packages, audio, locale are already configured
#   3. After archinstall finishes, installs StoaLinux dotfiles

set -e

# ── Colors ──
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

# ── Banner ──
echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     STOA LINUX — Arch Installer                      ║${R}"
echo -e "  ${B}║     archinstall + Hyprland/Wayland + i3/Xorg          ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""

# ── Check root ──
if [ "$(id -u)" -ne 0 ]; then
    echo -e "  ${T}[!] Run as root (live ISO).${R}"
    exit 1
fi

# ── Check connection ──
echo -e "  ${S}Checking connection...${R}"
if ! ping -c 1 archlinux.org &>/dev/null; then
    echo -e "  ${T}[!] No connection. Connect via:${R}"
    echo -e "  ${S}    Wi-Fi:  iwctl station wlan0 connect NETWORK_NAME${R}"
    echo -e "  ${S}    Cable:  dhcpcd${R}"
    exit 1
fi
echo -e "  ${O}[✓] Connected.${R}"
echo ""

# ══════════════════════════════════════════════════════════════
# PHASE 1: Download StoaLinux config
# ══════════════════════════════════════════════════════════════

STOA_REPO="https://raw.githubusercontent.com/VictorGSchneider/StoaLinux/main"
CONFIG_DIR="/tmp/stoa-archinstall"
mkdir -p "$CONFIG_DIR"

echo -e "  ${B}[1/4] Downloading StoaLinux config...${R}"
curl -sL "${STOA_REPO}/archinstall/user_configuration.json" -o "${CONFIG_DIR}/user_configuration.json"
echo -e "  ${O}[✓] Config downloaded.${R}"
echo ""

# ── Show what is pre-configured ──
echo -e "  ${F}Pre-configured by StoaLinux:${R}"
echo -e "  ${S}  Bootloader:  EFISTUB (direct UEFI boot)${R}"
echo -e "  ${S}  Audio:       PipeWire${R}"
echo -e "  ${S}  Network:     NetworkManager${R}"
echo -e "  ${S}  Locale:      pt_BR.UTF-8 / keyboard br${R}"
echo -e "  ${S}  Timezone:    America/Sao_Paulo${R}"
echo -e "  ${S}  Packages:    Hyprland, Waybar, i3, Alacritty, Neovim, Rofi...${R}"
echo ""
echo -e "  ${F}You configure in archinstall TUI:${R}"
echo -e "  ${B}  → Disks (partitioning and formatting)${R}"
echo -e "  ${B}  → User and password${R}"
echo -e "  ${B}  → Video driver (if needed)${R}"
echo ""
echo -e "  ${S}All fields can be changed in the TUI.${R}"
echo ""

read -rp "  Start archinstall? (y/n) [y]: " START
START="${START:-y}"
if [ "$START" != "y" ]; then
    echo -e "  ${S}Cancelled.${R}"
    exit 0
fi

# ══════════════════════════════════════════════════════════════
# PHASE 2: Run archinstall
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${B}[2/4] Starting archinstall...${R}"
echo -e "  ${S}Configure disks, user and video driver in the TUI.${R}"
echo ""

archinstall --config "${CONFIG_DIR}/user_configuration.json"

# ── Detect installed system ──

INSTALL_ROOT="/mnt/archinstall"
if [ ! -d "$INSTALL_ROOT" ] || ! mountpoint -q "$INSTALL_ROOT" 2>/dev/null; then
    INSTALL_ROOT="/mnt"
fi

if ! mountpoint -q "$INSTALL_ROOT" 2>/dev/null; then
    echo -e "  ${T}[!] Installed system not found mounted.${R}"
    echo -e "  ${S}Run post-install.sh after first boot.${R}"
    exit 0
fi

CREATED_USER=""
for userdir in "${INSTALL_ROOT}/home"/*/; do
    if [ -d "$userdir" ]; then
        CREATED_USER=$(basename "$userdir")
        break
    fi
done

if [ -z "$CREATED_USER" ]; then
    echo -e "  ${T}[!] No user found. Run post-install.sh after boot.${R}"
    exit 0
fi

echo -e "  ${S}User detected: ${B}${CREATED_USER}${R}"

# ══════════════════════════════════════════════════════════════
# PHASE 3: Install yay (AUR helper) + AUR packages
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${B}[3/4] Installing yay (AUR helper)...${R}"

# Ensure temporary passwordless sudo for makepkg in chroot
arch-chroot "$INSTALL_ROOT" bash -c \
    "echo '${CREATED_USER} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/stoa-temp" 2>/dev/null

arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c '
    cd /tmp
    git clone https://aur.archlinux.org/yay-bin.git
    cd yay-bin
    makepkg -si --noconfirm
    cd /tmp && rm -rf yay-bin
' 2>/dev/null

if arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c "yay --version" &>/dev/null; then
    echo -e "  ${O}[✓] yay installed.${R}"

    # ── AUR packages ──
    echo -e "  ${S}Installing AUR packages: brave-bin, obsidian, eww-wayland, satty...${R}"
    arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c \
        "yay -S --needed --noconfirm brave-bin obsidian eww-wayland satty" 2>/dev/null || true
    echo -e "  ${O}[✓] AUR packages installed.${R}"
else
    echo -e "  ${T}[!] yay could not be installed in chroot.${R}"
    echo -e "  ${S}Install after first boot:${R}"
    echo -e "  ${B}    cd /tmp && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si${R}"
    echo -e "  ${B}    yay -S brave-bin obsidian eww-wayland satty${R}"
fi

# Remove temporary sudo
arch-chroot "$INSTALL_ROOT" rm -f /etc/sudoers.d/stoa-temp 2>/dev/null

# ══════════════════════════════════════════════════════════════
# PHASE 4: Install StoaLinux dotfiles
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${B}[4/4] Installing StoaLinux dotfiles...${R}"

# Clone StoaLinux to user home
arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c \
    "git clone https://github.com/VictorGSchneider/StoaLinux.git ~/StoaLinux" 2>/dev/null || true

# Run install.sh (creates dotfile symlinks)
arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c \
    "cd ~/StoaLinux && chmod +x install.sh && bash install.sh" 2>/dev/null || true

# Configure zsh
arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c \
    "grep -q StoaLinux ~/.zshrc 2>/dev/null || echo 'source ~/StoaLinux/zsh/.zshrc' >> ~/.zshrc" 2>/dev/null || true

# .xinitrc for Xorg fallback
arch-chroot "$INSTALL_ROOT" su - "$CREATED_USER" -c \
    "[ -f ~/.xinitrc ] || echo 'exec i3' > ~/.xinitrc" 2>/dev/null || true

echo -e "  ${O}[✓] Dotfiles installed for ${CREATED_USER}.${R}"

# ── GPU + CPU Setup ──
echo ""
echo -e "  ${S}To configure GPU and CPU microcode:${R}"
echo -e "  ${B}    cd ~/StoaLinux && ./scripts/stoa-gpu-setup.sh${R}"

# ══════════════════════════════════════════════════════════════
# End
# ══════════════════════════════════════════════════════════════

echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     Installation complete!                            ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""
echo -e "  ${F}After reboot, login and start:${R}"
echo -e "  ${B}  Hyprland (Wayland):  Hyprland${R}"
echo -e "  ${B}  i3 (Xorg fallback):  startx${R}"
echo ""
echo -e "  ${F}Shortcuts:${R}"
echo -e "  ${S}  Super+Return  Terminal     Super+B  Brave${R}"
echo -e "  ${S}  Super+D       Launcher     Super+E  Files (lf)${R}"
echo -e "  ${S}  Super+N       Monitor      Super+Q  Close window${R}"
echo ""
echo -e "  ${O}\"The path of the wise is prepared.\" — Seneca${R}"
echo ""
