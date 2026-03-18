#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Post-Install (existing Arch)                  ║
# ║  "Do not suffer before the time." — Seneca                  ║
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
WAYLAND_PKGS="hyprland waybar swaybg xdg-desktop-portal-hyprland"

# i3 (Xorg — fallback)
XORG_PKGS="i3-wm i3status xorg-server xorg-xinit picom"

# Launcher, notifications
UI_PKGS="rofi dunst"

# Browser + Notes (AUR)
BROWSER_PKGS="brave-bin"
NOTES_PKGS="obsidian"

# VPN (AUR)
VPN_PKGS="protonvpn-cli"

# Terminal, editor, wallpapers
APP_PKGS="alacritty neovim feh imagemagick"

# Stoic apps (minimalist)
STOA_APPS="zathura zathura-pdf-mupdf mpv imv lf btop thunar thunar-volman thunar-archive-plugin thunar-media-tags-plugin thunar-shares-plugin thunar-vcs-plugin tumbler ffmpegthumbnailer gvfs gvfs-mtp catfish qalculate-gtk calibre"

# Gaming — "Even a wise man needs rest." — Seneca
GAMING_PKGS="steam lib32-vulkan-icd-loader vulkan-icd-loader lib32-mesa"

# Screenshot — Wayland + Xorg
SCREENSHOT_PKGS="grim slurp maim"

# Stoatools (OCR, paste, resize, rename, locksmith)
STOATOOLS_PKGS="tesseract tesseract-data-eng tesseract-data-por lsof wtype"

# Cloud Drive (rclone — stream on-demand, Google Drive/OneDrive/Dropbox/S3)
CLOUD_PKGS="rclone"

# App Store (Flatpak — Flathub access from Stoa Store)
STORE_PKGS="flatpak"

# Lock screen
LOCK_PKGS="hyprlock i3lock-color"

# Clipboard — Wayland
CLIPBOARD_PKGS="wl-clipboard cliphist"

# Widgets (eww — AUR, Wayland)
WIDGET_PKGS="eww-wayland"

# Fonts and theme
FONT_PKGS="ttf-jetbrains-mono ttf-font-awesome"

# Toolkit unification (Qt = GTK appearance)
THEME_PKGS="qt5ct qt6ct"

# Audio + utilities
UTIL_PKGS="pipewire pipewire-pulse pipewire-alsa wireplumber brightnessctl jq curl"

# Developer tools
DEV_PKGS="github-cli"

# Shell and extras
SHELL_PKGS="zsh git base-devel"

ALL_PKGS="$WAYLAND_PKGS $XORG_PKGS $UI_PKGS $APP_PKGS $STOA_APPS $GAMING_PKGS $SCREENSHOT_PKGS $STOATOOLS_PKGS $CLOUD_PKGS $STORE_PKGS $LOCK_PKGS $CLIPBOARD_PKGS $FONT_PKGS $THEME_PKGS $UTIL_PKGS $DEV_PKGS $SHELL_PKGS"

echo -e "  ${S}Wayland:    ${WAYLAND_PKGS}${R}"
echo -e "  ${S}Xorg:       ${XORG_PKGS}${R}"
echo -e "  ${S}UI:         ${UI_PKGS}${R}"
echo -e "  ${S}Browser:    ${BROWSER_PKGS} (AUR)${R}"
echo -e "  ${S}Notes:      ${NOTES_PKGS} (AUR)${R}"
echo -e "  ${S}VPN:        ${VPN_PKGS} (AUR)${R}"
echo -e "  ${S}Apps:       ${APP_PKGS}${R}"
echo -e "  ${S}Stoic:      ${STOA_APPS}${R}"
echo -e "  ${S}Gaming:     ${GAMING_PKGS}${R}"
echo -e "  ${S}Screenshot: ${SCREENSHOT_PKGS}${R}"
echo -e "  ${S}Stoatools:  ${STOATOOLS_PKGS}${R}"
echo -e "  ${S}Cloud:      ${CLOUD_PKGS}${R}"
echo -e "  ${S}Store:      ${STORE_PKGS}${R}"
echo -e "  ${S}Lock:       ${LOCK_PKGS}${R}"
echo -e "  ${S}Clipboard:  ${CLIPBOARD_PKGS}${R}"
echo -e "  ${S}Fonts:      ${FONT_PKGS}${R}"
echo -e "  ${S}Theme:      ${THEME_PKGS}${R}"
echo -e "  ${S}Audio:      ${UTIL_PKGS}${R}"
echo -e "  ${S}Widgets:    ${WIDGET_PKGS} (AUR)${R}"
echo -e "  ${S}Dev:        ${DEV_PKGS}${R}"
echo -e "  ${S}Shell:      ${SHELL_PKGS}${R}"
echo ""

read -rp "  Install packages? (y/n) [y]: " INSTALL_PKGS
INSTALL_PKGS="${INSTALL_PKGS:-y}"

if [ "$INSTALL_PKGS" = "y" ]; then
    # Enable multilib repository (required for Steam/lib32 packages)
    if ! grep -q "^\[multilib\]" /etc/pacman.conf 2>/dev/null; then
        echo -e "  ${F}Enabling multilib repository (required for Steam)...${R}"
        sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
        sudo pacman -Sy
        echo -e "  ${O}[✓] multilib enabled.${R}"
    fi

    sudo pacman -S --needed $ALL_PKGS
    echo -e "  ${O}[✓] Official packages installed.${R}"

    # Brave Browser (AUR)
    echo ""
    if ! command -v brave &>/dev/null; then
        echo -e "  ${F}Installing Brave Browser (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm brave-bin
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm brave-bin
        else
            echo -e "  ${S}Installing Brave manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/brave-bin.git "$_tmpdir/brave-bin"
            (cd "$_tmpdir/brave-bin" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] Brave installed.${R}"
    else
        echo -e "  ${S}[~] Brave already installed.${R}"
    fi

    # Obsidian (AUR)
    echo ""
    if ! command -v obsidian &>/dev/null; then
        echo -e "  ${F}Installing Obsidian (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm obsidian
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm obsidian
        else
            echo -e "  ${S}Installing Obsidian manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/obsidian.git "$_tmpdir/obsidian"
            (cd "$_tmpdir/obsidian" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] Obsidian installed.${R}"
    else
        echo -e "  ${S}[~] Obsidian already installed.${R}"
    fi

    # Satty — Screenshot editor (AUR)
    echo ""
    if ! command -v satty &>/dev/null; then
        echo -e "  ${F}Installing Satty (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm satty
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm satty
        else
            echo -e "  ${S}Installing Satty manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/satty.git "$_tmpdir/satty"
            (cd "$_tmpdir/satty" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] Satty installed.${R}"
    else
        echo -e "  ${S}[~] Satty already installed.${R}"
    fi

    # eww — Widget system (AUR, Wayland)
    echo ""
    if ! command -v eww &>/dev/null; then
        echo -e "  ${F}Installing eww-wayland (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm eww-wayland
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm eww-wayland
        else
            echo -e "  ${S}Installing eww-wayland manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/eww-wayland.git "$_tmpdir/eww-wayland"
            (cd "$_tmpdir/eww-wayland" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] eww-wayland installed.${R}"
    else
        echo -e "  ${S}[~] eww already installed.${R}"
    fi

    # Enpass — Password manager (AUR)
    echo ""
    if ! command -v enpass &>/dev/null; then
        echo -e "  ${F}Installing Enpass (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm enpass-bin
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm enpass-bin
        else
            echo -e "  ${S}Installing Enpass manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/enpass-bin.git "$_tmpdir/enpass-bin"
            (cd "$_tmpdir/enpass-bin" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] Enpass installed.${R}"
    else
        echo -e "  ${S}[~] Enpass already installed.${R}"
    fi

    # YACReader — Comic book reader (AUR)
    echo ""
    if ! command -v YACReader &>/dev/null; then
        echo -e "  ${F}Installing YACReader (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm yacreader
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm yacreader
        else
            echo -e "  ${S}Installing YACReader manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/yacreader.git "$_tmpdir/yacreader"
            (cd "$_tmpdir/yacreader" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] YACReader installed.${R}"
    else
        echo -e "  ${S}[~] YACReader already installed.${R}"
    fi

    # EB Garamond font (AUR)
    echo ""
    if ! fc-list | grep -qi "EB Garamond" 2>/dev/null; then
        echo -e "  ${F}Installing EB Garamond font (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm otf-eb-garamond
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm otf-eb-garamond
        else
            echo -e "  ${S}Installing EB Garamond manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/otf-eb-garamond.git "$_tmpdir/otf-eb-garamond"
            (cd "$_tmpdir/otf-eb-garamond" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] EB Garamond installed.${R}"
    else
        echo -e "  ${S}[~] EB Garamond already installed.${R}"
    fi

    # Colloid icon theme (AUR)
    echo ""
    if [ ! -d /usr/share/icons/Colloid-dark ] && [ ! -d "$HOME/.local/share/icons/Colloid-dark" ]; then
        echo -e "  ${F}Installing Colloid icon theme (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm colloid-icon-theme-git
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm colloid-icon-theme-git
        else
            echo -e "  ${S}Installing Colloid icons manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/colloid-icon-theme-git.git "$_tmpdir/colloid-icon-theme-git"
            (cd "$_tmpdir/colloid-icon-theme-git" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] Colloid icons installed.${R}"
    else
        echo -e "  ${S}[~] Colloid icons already installed.${R}"
    fi

    # Colloid cursors (AUR)
    echo ""
    if [ ! -d /usr/share/icons/Colloid-cursors ] && [ ! -d "$HOME/.local/share/icons/Colloid-cursors" ]; then
        echo -e "  ${F}Installing Colloid cursors (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm colloid-cursors-git
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm colloid-cursors-git
        else
            echo -e "  ${S}Installing Colloid cursors manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/colloid-cursors-git.git "$_tmpdir/colloid-cursors-git"
            (cd "$_tmpdir/colloid-cursors-git" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] Colloid cursors installed.${R}"
    else
        echo -e "  ${S}[~] Colloid cursors already installed.${R}"
    fi

    # howdy — Face recognition (AUR)
    echo ""
    if ! command -v howdy &>/dev/null; then
        echo -e "  ${F}Installing howdy — face recognition (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm howdy
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm howdy
        else
            echo -e "  ${S}Installing howdy manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/howdy.git "$_tmpdir/howdy"
            (cd "$_tmpdir/howdy" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] howdy installed.${R}"
        echo -e "  ${S}    To set up face recognition: sudo stoa-face setup${R}"
    else
        echo -e "  ${S}[~] howdy already installed.${R}"
    fi

    # ProtonVPN CLI (AUR) — "The wise man guards his retreat." — Seneca
    echo ""
    if ! command -v protonvpn-cli &>/dev/null; then
        echo -e "  ${F}Installing ProtonVPN CLI (AUR)...${R}"
        if command -v yay &>/dev/null; then
            yay -S --needed --noconfirm protonvpn-cli
        elif command -v paru &>/dev/null; then
            paru -S --needed --noconfirm protonvpn-cli
        else
            echo -e "  ${S}Installing ProtonVPN CLI manually via makepkg...${R}"
            _tmpdir=$(mktemp -d)
            git clone https://aur.archlinux.org/protonvpn-cli.git "$_tmpdir/protonvpn-cli"
            (cd "$_tmpdir/protonvpn-cli" && makepkg -si --noconfirm)
            rm -rf "$_tmpdir"
        fi
        echo -e "  ${O}[✓] ProtonVPN CLI installed.${R}"
        echo -e "  ${S}    To login: protonvpn-cli login <username>${R}"
        echo -e "  ${S}    Or use: Super+I → VPN${R}"
    else
        echo -e "  ${S}[~] ProtonVPN CLI already installed.${R}"
    fi
else
    echo -e "  ${S}[~] Packages skipped.${R}"
fi

echo ""

# ── Dotfiles ──
echo -e "  ${F}Installing dotfiles...${R}"
echo ""

STOA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "${STOA_DIR}/install.sh"

# ── Shell ──
echo ""
echo -e "  ${F}Shell configuration:${R}"
echo ""
echo -e "  ${S}  1) Configure zsh (add source to .zshrc)${R}"
echo -e "  ${S}  2) Configure bash (add source to .bashrc)${R}"
echo -e "  ${S}  3) Skip${R}"
read -rp "  Choose [1]: " SHELL_CHOICE
SHELL_CHOICE="${SHELL_CHOICE:-1}"

case "$SHELL_CHOICE" in
    1)
        ZSHRC="$HOME/.zshrc"
        if ! grep -q "StoaLinux" "$ZSHRC" 2>/dev/null; then
            echo "source ${STOA_DIR}/shell/.zshrc" >> "$ZSHRC"
            echo -e "  ${O}[✓] .zshrc configured.${R}"
        else
            echo -e "  ${S}[~] .zshrc already contains StoaLinux.${R}"
        fi
        if [ "$SHELL" != "/bin/zsh" ] && [ "$SHELL" != "/usr/bin/zsh" ]; then
            echo -e "  ${S}Changing shell to zsh...${R}"
            chsh -s /bin/zsh
            echo -e "  ${O}[✓] Shell changed to zsh.${R}"
        fi
        ;;
    2)
        BASHRC="$HOME/.bashrc"
        if ! grep -q "StoaLinux" "$BASHRC" 2>/dev/null; then
            echo "source ${STOA_DIR}/shell/.bashrc" >> "$BASHRC"
            echo -e "  ${O}[✓] .bashrc configured.${R}"
        else
            echo -e "  ${S}[~] .bashrc already contains StoaLinux.${R}"
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

# ── Done ──
echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     StoaLinux installed!                              ║${R}"
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
