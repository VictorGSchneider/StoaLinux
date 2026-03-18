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

# ── Window managers ──
_link "${STOA_DIR}/config/hypr/hyprland.conf"   "${CONFIG_DIR}/hypr/hyprland.conf"
_link "${STOA_DIR}/config/hypr/hyprlock.conf"   "${CONFIG_DIR}/hypr/hyprlock.conf"
_link "${STOA_DIR}/config/waybar/config"        "${CONFIG_DIR}/waybar/config"
_link "${STOA_DIR}/config/waybar/style.css"     "${CONFIG_DIR}/waybar/style.css"
_link "${STOA_DIR}/config/i3/config"            "${CONFIG_DIR}/i3/config"
_link "${STOA_DIR}/config/i3/i3status.conf"     "${CONFIG_DIR}/i3/i3status.conf"
_link "${STOA_DIR}/config/picom/picom.conf"     "${CONFIG_DIR}/picom/picom.conf"

# ── Apps ──
_link "${STOA_DIR}/config/alacritty/alacritty.toml" "${CONFIG_DIR}/alacritty/alacritty.toml"
_link "${STOA_DIR}/config/nvim/init.vim"            "${CONFIG_DIR}/nvim/init.vim"
_link "${STOA_DIR}/config/nvim/colors/stoa.vim"     "${CONFIG_DIR}/nvim/colors/stoa.vim"
_link "${STOA_DIR}/config/rofi/config.rasi"         "${CONFIG_DIR}/rofi/config.rasi"
_link "${STOA_DIR}/config/dunst/dunstrc"            "${CONFIG_DIR}/dunst/dunstrc"
_link "${STOA_DIR}/config/neofetch/config.conf"     "${CONFIG_DIR}/neofetch/config.conf"
_link "${STOA_DIR}/config/zathura/zathurarc"        "${CONFIG_DIR}/zathura/zathurarc"
_link "${STOA_DIR}/config/mpv/mpv.conf"             "${CONFIG_DIR}/mpv/mpv.conf"
_link "${STOA_DIR}/config/btop/btop.conf"           "${CONFIG_DIR}/btop/btop.conf"
_link "${STOA_DIR}/config/lf/lfrc"                  "${CONFIG_DIR}/lf/lfrc"
_link "${STOA_DIR}/config/imv/config"               "${CONFIG_DIR}/imv/config"
_link "${STOA_DIR}/config/thunar/uca.xml"           "${CONFIG_DIR}/Thunar/uca.xml"
_link "${STOA_DIR}/config/eww/eww.yuck"             "${CONFIG_DIR}/eww/eww.yuck"
_link "${STOA_DIR}/config/eww/eww.scss"             "${CONFIG_DIR}/eww/eww.scss"

# ── Theme (GTK + Qt + Steam + Calibre + YACReader + OnlyOffice + Betterbird) ──
_link "${STOA_DIR}/theme/gtk-3.0/settings.ini"  "${CONFIG_DIR}/gtk-3.0/settings.ini"
_link "${STOA_DIR}/theme/gtk-3.0/stoa-gtk.css"  "${CONFIG_DIR}/gtk-3.0/gtk.css"
_link "${STOA_DIR}/theme/gtk-4.0/settings.ini"  "${CONFIG_DIR}/gtk-4.0/settings.ini"
_link "${STOA_DIR}/theme/gtk-4.0/stoa-gtk.css"  "${CONFIG_DIR}/gtk-4.0/gtk.css"
_link "${STOA_DIR}/theme/qt5ct/qt5ct.conf"      "${CONFIG_DIR}/qt5ct/qt5ct.conf"
_link "${STOA_DIR}/theme/qt6ct/qt6ct.conf"      "${CONFIG_DIR}/qt6ct/qt6ct.conf"

if [ -f "${STOA_DIR}/theme/calibre/stoa-calibre.py" ]; then
    python3 "${STOA_DIR}/theme/calibre/stoa-calibre.py" 2>/dev/null && \
        echo -e "  ${O}[+] Calibre Stoa theme applied${R}" || true
fi

mkdir -p "${CONFIG_DIR}/YACReader"
if [ -f "${STOA_DIR}/theme/yacreader/stoa-yacreader.qss" ]; then
    _link "${STOA_DIR}/theme/yacreader/stoa-yacreader.qss" "${CONFIG_DIR}/YACReader/stoa-yacreader.qss"
fi

STEAM_CSS_DIR="${HOME}/.steam/steam/steamui"
if [ -d "${HOME}/.steam" ]; then
    mkdir -p "$STEAM_CSS_DIR"
    cp "${STOA_DIR}/theme/steam/stoa-steam.css" "${STEAM_CSS_DIR}/libraryroot.custom.css" 2>/dev/null && \
        echo -e "  ${O}[+] Steam Stoa CSS applied${R}" || true
fi

# OnlyOffice — install Stoa theme JSON
ONLYOFFICE_THEME_DIR="${HOME}/.local/share/onlyoffice/desktopeditors/themes"
if command -v desktopeditors &>/dev/null || [ -d "/opt/onlyoffice" ]; then
    mkdir -p "$ONLYOFFICE_THEME_DIR"
    cp "${STOA_DIR}/theme/onlyoffice/stoa-onlyoffice.json" "${ONLYOFFICE_THEME_DIR}/stoa-onlyoffice.json" 2>/dev/null && \
        echo -e "  ${O}[+] OnlyOffice Stoa theme installed${R}" || true
    echo -e "  ${S}    To activate: File → Advanced Settings → Interface theme → Stoa${R}"
fi

# Betterbird — apply Stoa CSS to all profiles
if [ -d "${HOME}/.betterbird" ]; then
    for profile_dir in "${HOME}/.betterbird/"*.default*; do
        [ -d "$profile_dir" ] || continue
        chrome_dir="${profile_dir}/chrome"
        mkdir -p "$chrome_dir"
        cp "${STOA_DIR}/theme/betterbird/stoa-betterbird.css" "${chrome_dir}/userChrome.css" 2>/dev/null
        cp "${STOA_DIR}/theme/betterbird/stoa-betterbird.css" "${chrome_dir}/userContent.css" 2>/dev/null
        # Enable toolkit.legacyUserProfileCustomizations.stylesheets
        prefs_file="${profile_dir}/user.js"
        if ! grep -q 'legacyUserProfileCustomizations' "$prefs_file" 2>/dev/null; then
            echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$prefs_file"
        fi
        echo -e "  ${O}[+] Betterbird Stoa CSS applied ($(basename "$profile_dir"))${R}"
    done
elif [ -d "${HOME}/.thunderbird" ]; then
    for profile_dir in "${HOME}/.thunderbird/"*.default*; do
        [ -d "$profile_dir" ] || continue
        chrome_dir="${profile_dir}/chrome"
        mkdir -p "$chrome_dir"
        cp "${STOA_DIR}/theme/betterbird/stoa-betterbird.css" "${chrome_dir}/userChrome.css" 2>/dev/null
        cp "${STOA_DIR}/theme/betterbird/stoa-betterbird.css" "${chrome_dir}/userContent.css" 2>/dev/null
        prefs_file="${profile_dir}/user.js"
        if ! grep -q 'legacyUserProfileCustomizations' "$prefs_file" 2>/dev/null; then
            echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$prefs_file"
        fi
        echo -e "  ${O}[+] Thunderbird Stoa CSS applied ($(basename "$profile_dir"))${R}"
    done
fi

# ── Stoa data dirs ──
mkdir -p "${CONFIG_DIR}/stoa/wallpapers"
mkdir -p "${HOME}/Pictures/screenshots"

# ── Environment ──
_link "${STOA_DIR}/shell/stoa-env.sh" "${CONFIG_DIR}/stoa/stoa-env.sh"

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
_link "${STOA_DIR}/scripts/stoa-clipboard.sh"       "${HOME}/.local/bin/stoa-clipboard"
_link "${STOA_DIR}/scripts/stoa-quotes-sync.sh"     "${HOME}/.local/bin/stoa-quotes-sync"
_link "${STOA_DIR}/scripts/stoa-locksmith.sh"       "${HOME}/.local/bin/stoa-locksmith"
_link "${STOA_DIR}/scripts/stoa-resize.sh"          "${HOME}/.local/bin/stoa-resize"
_link "${STOA_DIR}/scripts/stoa-paste.sh"           "${HOME}/.local/bin/stoa-paste"
_link "${STOA_DIR}/scripts/stoa-ocr.sh"             "${HOME}/.local/bin/stoa-ocr"
_link "${STOA_DIR}/scripts/stoa-rename.sh"          "${HOME}/.local/bin/stoa-rename"
_link "${STOA_DIR}/scripts/stoa-thunar.sh"          "${HOME}/.local/bin/stoa-thunar"
_link "${STOA_DIR}/scripts/stoa-face-setup.sh"      "${HOME}/.local/bin/stoa-face"
_link "${STOA_DIR}/scripts/stoa-settings.sh"        "${HOME}/.local/bin/stoa-settings"
_link "${STOA_DIR}/scripts/stoa-store.sh"           "${HOME}/.local/bin/stoa-store"
_link "${STOA_DIR}/scripts/stoa-drive.sh"           "${HOME}/.local/bin/stoa-drive"
chmod +x "${HOME}/.local/bin/stoa-fetch" "${HOME}/.local/bin/stoa-walls" \
         "${HOME}/.local/bin/stoa-memento" "${HOME}/.local/bin/stoa-memento-data" \
         "${HOME}/.local/bin/stoa-keybinds-bar" "${HOME}/.local/bin/stoa-keybinds-toggle" \
         "${HOME}/.local/bin/stoa-osd" "${HOME}/.local/bin/stoa-clipboard" \
         "${HOME}/.local/bin/stoa-quotes-sync" "${HOME}/.local/bin/stoa-locksmith" \
         "${HOME}/.local/bin/stoa-resize" "${HOME}/.local/bin/stoa-paste" \
         "${HOME}/.local/bin/stoa-ocr" "${HOME}/.local/bin/stoa-rename" \
         "${HOME}/.local/bin/stoa-thunar" "${HOME}/.local/bin/stoa-face" \
         "${HOME}/.local/bin/stoa-settings" \
         "${HOME}/.local/bin/stoa-store" \
         "${HOME}/.local/bin/stoa-drive"

# ── XDG MIME defaults ──
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
x-scheme-handler/mailto=betterbird.desktop
message/rfc822=betterbird.desktop
text/markdown=obsidian.desktop
application/vnd.openxmlformats-officedocument.wordprocessingml.document=onlyoffice-desktopeditors.desktop
application/vnd.openxmlformats-officedocument.spreadsheetml.sheet=onlyoffice-desktopeditors.desktop
application/vnd.openxmlformats-officedocument.presentationml.presentation=onlyoffice-desktopeditors.desktop
application/msword=onlyoffice-desktopeditors.desktop
application/vnd.ms-excel=onlyoffice-desktopeditors.desktop
application/vnd.ms-powerpoint=onlyoffice-desktopeditors.desktop
application/vnd.oasis.opendocument.text=onlyoffice-desktopeditors.desktop
application/vnd.oasis.opendocument.spreadsheet=onlyoffice-desktopeditors.desktop
application/vnd.oasis.opendocument.presentation=onlyoffice-desktopeditors.desktop
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
application/epub+zip=calibre-ebook-viewer.desktop
application/x-mobipocket-ebook=calibre-ebook-viewer.desktop
application/x-fictionbook+xml=calibre-ebook-viewer.desktop
application/x-cbz=YACReader.desktop
application/x-cbr=YACReader.desktop
application/x-cb7=YACReader.desktop
application/vnd.comicbook+zip=YACReader.desktop
application/vnd.comicbook-rar=YACReader.desktop
inode/directory=thunar.desktop
MIME
    echo -e "  ${O}[+] mimeapps.list${R}"
fi

echo ""
echo -e "${F}Shell configuration:${R}"
echo ""

echo -e "  ${S}Shell files are not linked automatically.${R}"
echo -e "  ${S}To use, add to the end of your .zshrc or .bashrc:${R}"
echo ""
echo -e "  ${B}Zsh:${R}  source ${STOA_DIR}/shell/.zshrc"
echo -e "  ${B}Bash:${R} source ${STOA_DIR}/shell/.bashrc"
echo ""

echo -e "  ${O}Done! The path of the wise is prepared.${R}"
echo ""
