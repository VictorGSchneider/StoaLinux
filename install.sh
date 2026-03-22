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
_link "${STOA_DIR}/config/kitty/kitty.conf" "${CONFIG_DIR}/kitty/kitty.conf"
_link "${STOA_DIR}/config/nvim/init.vim"            "${CONFIG_DIR}/nvim/init.vim"
_link "${STOA_DIR}/config/nvim/colors/stoa.vim"     "${CONFIG_DIR}/nvim/colors/stoa.vim"
_link "${STOA_DIR}/config/rofi/config.rasi"         "${CONFIG_DIR}/rofi/config.rasi"
_link "${STOA_DIR}/config/dunst/dunstrc"            "${CONFIG_DIR}/dunst/dunstrc"
_link "${STOA_DIR}/config/zathura/zathurarc"        "${CONFIG_DIR}/zathura/zathurarc"
_link "${STOA_DIR}/config/mpv/mpv.conf"             "${CONFIG_DIR}/mpv/mpv.conf"
_link "${STOA_DIR}/config/btop/btop.conf"           "${CONFIG_DIR}/btop/btop.conf"
_link "${STOA_DIR}/config/lf/lfrc"                  "${CONFIG_DIR}/lf/lfrc"
_link "${STOA_DIR}/config/imv/config"               "${CONFIG_DIR}/imv/config"
_link "${STOA_DIR}/config/thunar/uca.xml"           "${CONFIG_DIR}/Thunar/uca.xml"
_link "${STOA_DIR}/config/eww/eww.yuck"             "${CONFIG_DIR}/eww/eww.yuck"
_link "${STOA_DIR}/config/eww/eww.scss"             "${CONFIG_DIR}/eww/eww.scss"
_link "${STOA_DIR}/config/Code/User/settings.json"  "${CONFIG_DIR}/Code/User/settings.json"
_link "${STOA_DIR}/config/fastfetch/config.jsonc"      "${CONFIG_DIR}/fastfetch/config.jsonc"
_link "${STOA_DIR}/config/fastfetch/stoa-temple.txt"   "${CONFIG_DIR}/fastfetch/stoa-temple.txt"

# ── Theme (GTK + Qt + Steam + Calibre + YACReader + OnlyOffice + Betterbird + VS Code) ──
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

# OnlyOffice theme
ONLYOFFICE_DIR="${HOME}/.config/onlyoffice/desktopeditors"
if [ -d "${HOME}/.config/onlyoffice" ] || command -v onlyoffice-desktopeditors &>/dev/null; then
    mkdir -p "$ONLYOFFICE_DIR"
    cp "${STOA_DIR}/theme/onlyoffice/stoa-onlyoffice.json" "${ONLYOFFICE_DIR}/settings.json" 2>/dev/null && \
        echo -e "  ${O}[+] OnlyOffice Stoa theme applied${R}" || true
fi

# Betterbird theme (userChrome.css)
BB_PROFILE_DIR=$(find "${HOME}/.betterbird" -maxdepth 2 -name "prefs.js" -printf '%h\n' 2>/dev/null | head -1)
if [ -n "$BB_PROFILE_DIR" ]; then
    mkdir -p "${BB_PROFILE_DIR}/chrome"
    _link "${STOA_DIR}/theme/betterbird/stoa-betterbird.css" "${BB_PROFILE_DIR}/chrome/userChrome.css"
    echo -e "  ${O}[+] Betterbird Stoa theme applied${R}"
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

# Div Acer Manager Max — apply Stoa theme (if installed)
if command -v div-acer-manager &>/dev/null || [ -d "/opt/div-acer-manager-max" ] || [ -d "/opt/DivAcerManagerMax" ]; then
    bash "${STOA_DIR}/theme/div-acer-manager/stoa-damx-apply.sh" apply 2>/dev/null && \
        echo -e "  ${O}[+] Div Acer Manager Stoa theme applied${R}" || true
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
# ── Pacman hook (auto-apply theme after installs) ──
if [ -d /etc/pacman.d/hooks ] || sudo mkdir -p /etc/pacman.d/hooks 2>/dev/null; then
    sudo cp "${STOA_DIR}/theme/pacman-hooks/stoa-theme.hook" /etc/pacman.d/hooks/ 2>/dev/null && \
    sudo cp "${STOA_DIR}/theme/pacman-hooks/stoa-theme-enforce" /usr/local/bin/ 2>/dev/null && \
    sudo chmod +x /usr/local/bin/stoa-theme-enforce 2>/dev/null && \
    echo -e "  ${O}[+] Pacman theme hook installed${R}" || \
    echo -e "  ${S}[~] Pacman hook skipped (no sudo)${R}"
fi

# VS Code — install Stoa theme as extension
VSCODE_EXT_DIR="${HOME}/.vscode/extensions/stoa-theme"
mkdir -p "$VSCODE_EXT_DIR/themes"
cp "${STOA_DIR}/theme/vscode/package.json" "$VSCODE_EXT_DIR/"
cp "${STOA_DIR}/theme/vscode/themes/stoa-color-theme.json" "$VSCODE_EXT_DIR/themes/"
echo -e "  ${O}[+] VS Code Stoa theme installed${R}"
echo -e "  ${S}    To activate: Ctrl+K Ctrl+T → Stoa${R}"

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
_link "${STOA_DIR}/scripts/stoa-firewall.sh"       "${HOME}/.local/bin/stoa-firewall"
_link "${STOA_DIR}/scripts/stoa-screensaver.sh"   "${HOME}/.local/bin/stoa-screensaver"
_link "${STOA_DIR}/scripts/stoa-winapps.sh"      "${HOME}/.local/bin/stoa-winapps"
_link "${STOA_DIR}/scripts/stoa-capture.sh"       "${HOME}/.local/bin/stoa-capture"
_link "${STOA_DIR}/scripts/stoa-doctor.sh"        "${HOME}/.local/bin/stoa-doctor"
_link "${STOA_DIR}/scripts/stoa-pkg-snapshot.sh"  "${HOME}/.local/bin/stoa-pkg-snapshot"
_link "${STOA_DIR}/scripts/stoa-gpu-setup.sh"    "${HOME}/.local/bin/stoa-gpu-setup"
_link "${STOA_DIR}/scripts/stoa-maintain.sh"      "${HOME}/.local/bin/stoa-maintain"
_link "${STOA_DIR}/scripts/stoa-predict.sh"      "${HOME}/.local/bin/stoa-predict"
cp    "${STOA_DIR}/scripts/stoa-predict.py"      "${HOME}/.local/bin/stoa-predict.py"
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
         "${HOME}/.local/bin/stoa-drive" \
         "${HOME}/.local/bin/stoa-firewall" \
         "${HOME}/.local/bin/stoa-screensaver" \
         "${HOME}/.local/bin/stoa-winapps" \
         "${HOME}/.local/bin/stoa-capture" \
         "${HOME}/.local/bin/stoa-doctor" \
         "${HOME}/.local/bin/stoa-pkg-snapshot" \
         "${HOME}/.local/bin/stoa-gpu-setup"
         "${HOME}/.local/bin/stoa-maintain" \
         "${HOME}/.local/bin/stoa-predict" \
         "${HOME}/.local/bin/stoa-predict.py"

# ── Pacman hooks (require sudo) ──
echo ""
echo -e "${F}Pacman hooks:${R}"
echo ""
HOOK_DIR="/etc/pacman.d/hooks"
if [ -d "$HOOK_DIR" ] || sudo mkdir -p "$HOOK_DIR" 2>/dev/null; then
    sudo cp "${STOA_DIR}/theme/pacman-hooks/stoa-pkg-snapshot.hook" "${HOOK_DIR}/" 2>/dev/null \
        && echo -e "  ${O}[+] stoa-pkg-snapshot.hook${R}" \
        || echo -e "  ${S}[!] Could not install pkg-snapshot hook (need sudo)${R}"
    sudo cp "${STOA_DIR}/theme/pacman-hooks/stoa-theme.hook" "${HOOK_DIR}/" 2>/dev/null \
        && echo -e "  ${O}[+] stoa-theme.hook${R}" \
        || echo -e "  ${S}[!] Could not install theme hook (need sudo)${R}"
    # The hook calls /usr/local/bin/stoa-pkg-snapshot — symlink it
    sudo ln -sf "${HOME}/.local/bin/stoa-pkg-snapshot" /usr/local/bin/stoa-pkg-snapshot 2>/dev/null
else
    echo -e "  ${S}[!] Could not create ${HOOK_DIR} (need sudo)${R}"
fi

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
text/plain=code.desktop
text/x-python=code.desktop
text/x-csrc=code.desktop
text/x-chdr=code.desktop
text/x-c++src=code.desktop
text/x-java=code.desktop
text/x-shellscript=code.desktop
text/x-script.python=code.desktop
application/javascript=code.desktop
application/json=code.desktop
application/x-yaml=code.desktop
application/xml=code.desktop
application/toml=code.desktop
text/x-rust=code.desktop
text/x-go=code.desktop
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
