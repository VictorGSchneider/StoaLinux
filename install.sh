#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Dotfiles Installer                            ║
# ║  "Action is the mark of wisdom." — Seneca                   ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

STOA_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${HOME}/.config"

# Colors
B='\033[38;2;196;154;92m'
S='\033[38;2;110;106;98m'
F='\033[38;2;212;207;196m'
O='\033[38;2;138;154;108m'
T='\033[38;2;179;107;90m'
R='\033[0m'

echo ""
echo -e "  ${B}╔══════════════════════════════════════════╗${R}"
echo -e "  ${B}║     STOA LINUX — Installer               ║${R}"
echo -e "  ${B}║     Stoic Dotfiles for Arch Linux         ║${R}"
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

echo -e "${F}Creating symlinks...${R}"
echo ""

# ── Hyprland (Wayland — primary) ──
_link "${STOA_DIR}/hyprland/hyprland.conf" "${CONFIG_DIR}/hypr/hyprland.conf"

# ── Waybar ──
_link "${STOA_DIR}/waybar/config"     "${CONFIG_DIR}/waybar/config"
_link "${STOA_DIR}/waybar/style.css"  "${CONFIG_DIR}/waybar/style.css"

# ── i3 (Xorg — fallback) ──
_link "${STOA_DIR}/i3/config"         "${CONFIG_DIR}/i3/config"
_link "${STOA_DIR}/i3/i3status.conf"  "${CONFIG_DIR}/i3/i3status.conf"

# ── Picom (Xorg only) ──
_link "${STOA_DIR}/picom/picom.conf" "${CONFIG_DIR}/picom/picom.conf"

# ── Alacritty ──
_link "${STOA_DIR}/alacritty/alacritty.toml" "${CONFIG_DIR}/alacritty/alacritty.toml"

# ── Neovim ──
_link "${STOA_DIR}/nvim/init.vim"         "${CONFIG_DIR}/nvim/init.vim"
_link "${STOA_DIR}/nvim/colors/stoa.vim"  "${CONFIG_DIR}/nvim/colors/stoa.vim"

# ── Rofi ──
_link "${STOA_DIR}/rofi/config.rasi" "${CONFIG_DIR}/rofi/config.rasi"

# ── Dunst ──
_link "${STOA_DIR}/dunst/dunstrc" "${CONFIG_DIR}/dunst/dunstrc"

# ── Neofetch ──
_link "${STOA_DIR}/neofetch/config.conf" "${CONFIG_DIR}/neofetch/config.conf"

# ── GTK 3.0 + 4.0 ──
_link "${STOA_DIR}/gtk-3.0/settings.ini" "${CONFIG_DIR}/gtk-3.0/settings.ini"
_link "${STOA_DIR}/gtk-4.0/settings.ini" "${CONFIG_DIR}/gtk-4.0/settings.ini"

# ── Qt5/Qt6 (standardization with GTK) ──
_link "${STOA_DIR}/qt5ct/qt5ct.conf" "${CONFIG_DIR}/qt5ct/qt5ct.conf"
_link "${STOA_DIR}/qt6ct/qt6ct.conf" "${CONFIG_DIR}/qt6ct/qt6ct.conf"

# ── Thunar (Stoatools custom actions) ──
_link "${STOA_DIR}/thunar/uca.xml" "${CONFIG_DIR}/Thunar/uca.xml"

# ── Stoic apps ──
_link "${STOA_DIR}/zathura/zathurarc"  "${CONFIG_DIR}/zathura/zathurarc"
_link "${STOA_DIR}/mpv/mpv.conf"       "${CONFIG_DIR}/mpv/mpv.conf"
_link "${STOA_DIR}/btop/btop.conf"     "${CONFIG_DIR}/btop/btop.conf"
_link "${STOA_DIR}/lf/lfrc"            "${CONFIG_DIR}/lf/lfrc"
_link "${STOA_DIR}/imv/config"         "${CONFIG_DIR}/imv/config"

# ── eww (Memento Mori widget) ──
_link "${STOA_DIR}/eww/eww.yuck"  "${CONFIG_DIR}/eww/eww.yuck"
_link "${STOA_DIR}/eww/eww.scss"  "${CONFIG_DIR}/eww/eww.scss"

# ── Stoa wallpapers dir ──
mkdir -p "${CONFIG_DIR}/stoa/wallpapers"

# ── Screenshots directory ──
mkdir -p "${HOME}/Pictures/screenshots"

# ── Environment (toolkit unification) ──
_link "${STOA_DIR}/environment/stoa-env.sh" "${CONFIG_DIR}/stoa/stoa-env.sh"

# ── Stoa config (preserves user settings) ──
if [ ! -f "${CONFIG_DIR}/stoa/stoa.conf" ]; then
    cp "${STOA_DIR}/stoa.conf" "${CONFIG_DIR}/stoa/stoa.conf"
    echo -e "  ${O}[+] ${CONFIG_DIR}/stoa/stoa.conf${R}"
else
    echo -e "  ${S}[~] stoa.conf already exists (preserved)${R}"
fi

# ── Scripts ──
mkdir -p "${HOME}/.local/bin"
_link "${STOA_DIR}/scripts/stoa-fetch.sh"           "${HOME}/.local/bin/stoa-fetch"
_link "${STOA_DIR}/scripts/stoa-walls.sh"           "${HOME}/.local/bin/stoa-walls"
_link "${STOA_DIR}/scripts/stoa-memento.sh"         "${HOME}/.local/bin/stoa-memento"
_link "${STOA_DIR}/scripts/stoa-memento-data.sh"    "${HOME}/.local/bin/stoa-memento-data"
_link "${STOA_DIR}/scripts/stoa-keybinds-bar.sh"    "${HOME}/.local/bin/stoa-keybinds-bar"
_link "${STOA_DIR}/scripts/stoa-keybinds-toggle.sh" "${HOME}/.local/bin/stoa-keybinds-toggle"
_link "${STOA_DIR}/scripts/stoa-osd.sh"             "${HOME}/.local/bin/stoa-osd"
_link "${STOA_DIR}/scripts/stoa-clipboard.sh"      "${HOME}/.local/bin/stoa-clipboard"
_link "${STOA_DIR}/scripts/stoa-quotes-sync.sh"   "${HOME}/.local/bin/stoa-quotes-sync"
_link "${STOA_DIR}/scripts/stoa-locksmith.sh"    "${HOME}/.local/bin/stoa-locksmith"
_link "${STOA_DIR}/scripts/stoa-resize.sh"       "${HOME}/.local/bin/stoa-resize"
_link "${STOA_DIR}/scripts/stoa-paste.sh"        "${HOME}/.local/bin/stoa-paste"
_link "${STOA_DIR}/scripts/stoa-ocr.sh"          "${HOME}/.local/bin/stoa-ocr"
_link "${STOA_DIR}/scripts/stoa-rename.sh"       "${HOME}/.local/bin/stoa-rename"
chmod +x "${HOME}/.local/bin/stoa-fetch" "${HOME}/.local/bin/stoa-walls" \
         "${HOME}/.local/bin/stoa-memento" "${HOME}/.local/bin/stoa-memento-data" \
         "${HOME}/.local/bin/stoa-keybinds-bar" "${HOME}/.local/bin/stoa-keybinds-toggle" \
         "${HOME}/.local/bin/stoa-osd" "${HOME}/.local/bin/stoa-clipboard" \
         "${HOME}/.local/bin/stoa-quotes-sync" "${HOME}/.local/bin/stoa-locksmith" \
         "${HOME}/.local/bin/stoa-resize" "${HOME}/.local/bin/stoa-paste" \
         "${HOME}/.local/bin/stoa-ocr" "${HOME}/.local/bin/stoa-rename"

# ── XDG MIME defaults (browser + apps) ──
MIME_DIR="${HOME}/.local/share/applications"
mkdir -p "$MIME_DIR"
if [ ! -f "${MIME_DIR}/mimeapps.list" ]; then
    cat > "${MIME_DIR}/mimeapps.list" <<'MIME'
[Default Applications]
text/html=brave-browser.desktop
x-scheme-handler/http=brave-browser.desktop
x-scheme-handler/https=brave-browser.desktop
x-scheme-handler/about=brave-browser.desktop
x-scheme-handler/unknown=brave-browser.desktop
text/markdown=obsidian.desktop
application/pdf=org.pwmt.zathura.desktop
image/png=imv.desktop
image/jpeg=imv.desktop
image/gif=imv.desktop
image/webp=imv.desktop
video/mp4=mpv.desktop
video/x-matroska=mpv.desktop
video/webm=mpv.desktop
audio/mpeg=mpv.desktop
audio/flac=mpv.desktop
audio/ogg=mpv.desktop
inode/directory=thunar.desktop
MIME
    echo -e "  ${O}[+] mimeapps.list (Brave as default browser)${R}"
fi

echo ""
echo -e "${F}Shell configuration:${R}"
echo ""

echo -e "  ${S}Shell files are not linked automatically.${R}"
echo -e "  ${S}To use, add to the end of your .zshrc or .bashrc:${R}"
echo ""
echo -e "  ${B}Zsh:${R}  source ${STOA_DIR}/zsh/.zshrc"
echo -e "  ${B}Bash:${R} source ${STOA_DIR}/zsh/.bashrc"
echo ""

echo -e "  ${O}Done! The path of the wise is prepared.${R}"
echo ""
echo -e "  ${F}Keybinds:${R}"
echo -e "  ${S}  Super+Return  Terminal (Alacritty)${R}"
echo -e "  ${S}  Super+B       Browser (Brave)${R}"
echo -e "  ${S}  Super+E       Files (lf)${R}"
echo -e "  ${S}  Super+Shift+E Files (Thunar)${R}"
echo -e "  ${S}  Super+N       Monitor (btop)${R}"
echo -e "  ${S}  Super+D       Launcher (Rofi)${R}"
echo -e "  ${S}  Super+O       Notes (Obsidian)${R}"
echo -e "  ${S}  Super+M       Memento Mori (eww)${R}"
echo -e "  ${S}  Super+/       Bar keybinds (toggle)${R}"
echo -e "  ${S}  Super+Shift+T OCR — extract text from screen${R}"
echo -e "  ${S}  Super+Shift+P Advanced paste${R}"
echo ""
