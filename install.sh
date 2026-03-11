#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Instalador de Dotfiles                        ║
# ║  "A ação é a marca da sabedoria." — Sêneca                  ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

STOA_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${HOME}/.config"

# Cores
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

echo ""
echo -e "  ${B}╔══════════════════════════════════════════╗${R}"
echo -e "  ${B}║     STOA LINUX — Instalador              ║${R}"
echo -e "  ${B}║     Dotfiles Estoicos para Arch Linux     ║${R}"
echo -e "  ${B}╚══════════════════════════════════════════╝${R}"
echo ""

_link() {
    local src="$1"
    local dst="$2"

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        local backup="${dst}.bak.$(date +%s)"
        echo -e "  ${S}[~] Backup: ${dst} → ${backup}${R}"
        mv "$dst" "$backup"
    fi

    mkdir -p "$(dirname "$dst")"
    ln -sf "$src" "$dst"
    echo -e "  ${O}[+] ${dst}${R}"
}

echo -e "${F}Criando symlinks...${R}"
echo ""

# Alacritty
_link "${STOA_DIR}/alacritty/alacritty.toml" "${CONFIG_DIR}/alacritty/alacritty.toml"

# i3
_link "${STOA_DIR}/i3/config"         "${CONFIG_DIR}/i3/config"
_link "${STOA_DIR}/i3/i3status.conf"  "${CONFIG_DIR}/i3/i3status.conf"

# Neovim
_link "${STOA_DIR}/nvim/init.vim"         "${CONFIG_DIR}/nvim/init.vim"
_link "${STOA_DIR}/nvim/colors/stoa.vim"  "${CONFIG_DIR}/nvim/colors/stoa.vim"

# Rofi
_link "${STOA_DIR}/rofi/config.rasi" "${CONFIG_DIR}/rofi/config.rasi"

# Dunst
_link "${STOA_DIR}/dunst/dunstrc" "${CONFIG_DIR}/dunst/dunstrc"

# Picom
_link "${STOA_DIR}/picom/picom.conf" "${CONFIG_DIR}/picom/picom.conf"

# Neofetch
_link "${STOA_DIR}/neofetch/config.conf" "${CONFIG_DIR}/neofetch/config.conf"

# GTK 3.0
_link "${STOA_DIR}/gtk-3.0/settings.ini" "${CONFIG_DIR}/gtk-3.0/settings.ini"

# Stoa wallpapers dir
mkdir -p "${CONFIG_DIR}/stoa/wallpapers"

# Scripts
mkdir -p "${HOME}/.local/bin"
_link "${STOA_DIR}/scripts/stoa-fetch.sh" "${HOME}/.local/bin/stoa-fetch"
_link "${STOA_DIR}/scripts/stoa-walls.sh" "${HOME}/.local/bin/stoa-walls"
chmod +x "${HOME}/.local/bin/stoa-fetch" "${HOME}/.local/bin/stoa-walls"

echo ""
echo -e "${F}Configurações do shell:${R}"
echo ""

# Shell configs (não sobrescreve, apenas sugere)
echo -e "  ${S}Os arquivos de shell não são linkados automaticamente.${R}"
echo -e "  ${S}Para usar, adicione ao final do seu .zshrc ou .bashrc:${R}"
echo ""
echo -e "  ${B}Zsh:${R}  source ${STOA_DIR}/zsh/.zshrc"
echo -e "  ${B}Bash:${R} source ${STOA_DIR}/zsh/.bashrc"
echo ""

echo -e "${F}Dependências recomendadas:${R}"
echo ""
echo -e "  ${B}sudo pacman -S alacritty i3-wm i3status rofi dunst picom feh neovim${R}"
echo -e "  ${S}Fontes: ttf-jetbrains-mono ttf-font-awesome${R}"
echo -e "  ${S}Wallpapers: imagemagick (para gerar com stoa-walls)${R}"
echo ""
echo -e "  ${O}Pronto! O caminho do sábio está preparado.${R}"
echo -e "  ${S}Execute 'stoa-fetch' para ver o fetch estoico.${R}"
echo -e "  ${S}Execute 'stoa-walls' para gerar wallpapers.${R}"
echo ""
