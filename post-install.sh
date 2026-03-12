#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Post-Install (Arch já instalado)             ║
# ║  "Não sofras antes do tempo." — Sêneca                     ║
# ║                                                              ║
# ║  Use este script em um Arch Linux já instalado para          ║
# ║  instalar todos os pacotes e dotfiles do StoaLinux.          ║
# ╚══════════════════════════════════════════════════════════════╝
#
# USO:
#   git clone https://github.com/VictorGSchneider/StoaLinux.git
#   cd StoaLinux
#   chmod +x post-install.sh
#   ./post-install.sh

set -e

# ── Cores ──
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

# ── Verificar Arch Linux ──
if [ ! -f /etc/arch-release ]; then
    echo -e "  ${T}[!] Este script é para Arch Linux.${R}"
    exit 1
fi

# ── Verificar que não é root ──
if [ "$(id -u)" -eq 0 ]; then
    echo -e "  ${T}[!] Não execute como root. O script usa sudo quando necessário.${R}"
    exit 1
fi

# ── Pacotes ──
echo -e "  ${F}Pacotes do StoaLinux:${R}"
echo ""

# Hyprland (Wayland — primário)
WAYLAND_PKGS="hyprland waybar swaybg xdg-desktop-portal-hyprland"

# i3 (Xorg — fallback)
XORG_PKGS="i3-wm i3status xorg-server xorg-xinit picom"

# Launcher, notificações
UI_PKGS="rofi dunst"

# Terminal, editor, wallpapers
APP_PKGS="alacritty neovim feh imagemagick"

# Screenshot — Wayland + Xorg
SCREENSHOT_PKGS="grim slurp maim"

# Fontes e tema
FONT_PKGS="ttf-jetbrains-mono ttf-font-awesome papirus-icon-theme"

# Áudio + utilidades
UTIL_PKGS="pipewire pipewire-pulse wireplumber brightnessctl"

# Shell e extras
SHELL_PKGS="zsh git"

ALL_PKGS="$WAYLAND_PKGS $XORG_PKGS $UI_PKGS $APP_PKGS $SCREENSHOT_PKGS $FONT_PKGS $UTIL_PKGS $SHELL_PKGS"

echo -e "  ${S}Wayland:    ${WAYLAND_PKGS}${R}"
echo -e "  ${S}Xorg:       ${XORG_PKGS}${R}"
echo -e "  ${S}UI:         ${UI_PKGS}${R}"
echo -e "  ${S}Apps:       ${APP_PKGS}${R}"
echo -e "  ${S}Screenshot: ${SCREENSHOT_PKGS}${R}"
echo -e "  ${S}Fontes:     ${FONT_PKGS}${R}"
echo -e "  ${S}Áudio:      ${UTIL_PKGS}${R}"
echo -e "  ${S}Shell:      ${SHELL_PKGS}${R}"
echo ""

read -rp "  Instalar pacotes? (s/n) [s]: " INSTALL_PKGS
INSTALL_PKGS="${INSTALL_PKGS:-s}"

if [ "$INSTALL_PKGS" = "s" ]; then
    sudo pacman -S --needed $ALL_PKGS
    echo -e "  ${O}[✓] Pacotes instalados.${R}"
else
    echo -e "  ${S}[~] Pacotes pulados.${R}"
fi

echo ""

# ── Dotfiles ──
echo -e "  ${F}Instalando dotfiles...${R}"
echo ""

STOA_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "${STOA_DIR}/install.sh"

# ── Shell ──
echo ""
echo -e "  ${F}Configuração do shell:${R}"
echo ""
echo -e "  ${S}  1) Configurar zsh (adicionar source ao .zshrc)${R}"
echo -e "  ${S}  2) Configurar bash (adicionar source ao .bashrc)${R}"
echo -e "  ${S}  3) Pular${R}"
read -rp "  Escolha [1]: " SHELL_CHOICE
SHELL_CHOICE="${SHELL_CHOICE:-1}"

case "$SHELL_CHOICE" in
    1)
        ZSHRC="$HOME/.zshrc"
        if ! grep -q "StoaLinux" "$ZSHRC" 2>/dev/null; then
            echo "source ${STOA_DIR}/zsh/.zshrc" >> "$ZSHRC"
            echo -e "  ${O}[✓] .zshrc configurado.${R}"
        else
            echo -e "  ${S}[~] .zshrc já contém StoaLinux.${R}"
        fi
        if [ "$SHELL" != "/bin/zsh" ] && [ "$SHELL" != "/usr/bin/zsh" ]; then
            echo -e "  ${S}Trocando shell para zsh...${R}"
            chsh -s /bin/zsh
            echo -e "  ${O}[✓] Shell alterado para zsh.${R}"
        fi
        ;;
    2)
        BASHRC="$HOME/.bashrc"
        if ! grep -q "StoaLinux" "$BASHRC" 2>/dev/null; then
            echo "source ${STOA_DIR}/zsh/.bashrc" >> "$BASHRC"
            echo -e "  ${O}[✓] .bashrc configurado.${R}"
        else
            echo -e "  ${S}[~] .bashrc já contém StoaLinux.${R}"
        fi
        ;;
    3)
        echo -e "  ${S}[~] Shell pulado.${R}"
        ;;
esac

# ── .xinitrc (fallback Xorg) ──
echo ""
if [ ! -f "$HOME/.xinitrc" ]; then
    echo "exec i3" > "$HOME/.xinitrc"
    echo -e "  ${O}[✓] .xinitrc criado (exec i3 — fallback Xorg).${R}"
else
    echo -e "  ${S}[~] .xinitrc já existe.${R}"
fi

# ── Fim ──
echo ""
echo -e "  ${B}╔══════════════════════════════════════════════════════╗${R}"
echo -e "  ${B}║     StoaLinux instalado!                             ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════════════════╝${R}"
echo ""
echo -e "  ${F}Para iniciar:${R}"
echo -e "  ${B}  Hyprland (Wayland):   Hyprland${R}"
echo -e "  ${B}  i3 (Xorg fallback):   startx${R}"
echo ""
echo -e "  ${F}Comandos do Stoa:${R}"
echo -e "  ${S}  stoa-fetch  — System fetch estoico${R}"
echo -e "  ${S}  stoa-walls  — Gerar wallpapers${R}"
echo ""
echo -e "  ${O}\"O caminho do sábio está preparado.\" — Sêneca${R}"
echo ""
