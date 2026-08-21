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

    # Already a correct symlink — nothing to do
    if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
        return 0
    fi

    mkdir -p "$(dirname "$dst")"

    # Files and symlinks are replaced atomically: back up with `cp` (which
    # leaves the original in place), build the new symlink beside the
    # destination, then rename over it. rename(2) is atomic, so a config
    # watcher never observes a missing file.
    #
    # The previous `mv` + `ln` order left a window where the destination did
    # not exist. Hyprland watches ~/.config/hypr/hyprland.lua and reloads on
    # change, so running install.sh from a live session reliably raised
    #     cannot open /home/<user>/.config/hypr/hyprland.lua
    # even though the link that followed was perfectly good.
    if [ ! -d "$dst" ] || [ -L "$dst" ]; then
        if [ -e "$dst" ] || [ -L "$dst" ]; then
            local backup="${dst}.bak.$(date +%s)"
            echo -e "  ${S}[~] Backup: ${dst} → ${backup}${R}"
            cp -a "$dst" "$backup"
        fi
        local tmp
        tmp="$(mktemp -u "${dst}.stoa-XXXXXX")"
        ln -s "$src" "$tmp"
        mv -T "$tmp" "$dst"
        echo -e "  ${O}[+] ${dst}${R}"
        return 0
    fi

    # A real directory cannot be atomically swapped for a symlink, so it
    # keeps the move-then-link path. No live-watched config is a directory.
    local backup="${dst}.bak.$(date +%s)"
    echo -e "  ${S}[~] Backup: ${dst} → ${backup}${R}"
    mv "$dst" "$backup"
    ln -s "$src" "$dst"
    echo -e "  ${O}[+] ${dst}${R}"
}

# Same semantics as _link, but the destination lives under a root-owned
# path (e.g. /etc/pacman.d/hooks, /usr/local/bin). All destructive ops go
# through `sudo` so we never silently drop a failure.
_sudo_link() {
    local src="$1"
    local dst="$2"

    # Already a correct symlink — nothing to do
    if sudo test -L "$dst" && [ "$(sudo readlink "$dst")" = "$src" ]; then
        return 0
    fi

    if sudo test -e "$dst" || sudo test -L "$dst"; then
        local backup="${dst}.bak.$(date +%s)"
        echo -e "  ${S}[~] Backup: ${dst} → ${backup}${R}"
        sudo mv "$dst" "$backup"
    fi

    sudo mkdir -p "$(dirname "$dst")"
    sudo ln -sf "$src" "$dst"
    echo -e "  ${O}[+] ${dst}${R}"
}

echo -e "${F}Creating symlinks...${R}"
echo ""

# ── Window managers ──
_link "${STOA_DIR}/config/hypr/hyprland.lua"    "${CONFIG_DIR}/hypr/hyprland.lua"
_link "${STOA_DIR}/config/hypr/hyprlock.conf"   "${CONFIG_DIR}/hypr/hyprlock.conf"
# Hyprland 0.55 replaced hyprlang with lua. Hyprland prefers hyprland.lua
# when both exist, but a leftover hyprland.conf symlink pointing at a file
# we no longer ship would just be a dead link — and on a pre-0.55 binary it
# would silently keep serving the stale config. Drop ours; a real file the
# user wrote themselves is left alone.
if [ -L "${CONFIG_DIR}/hypr/hyprland.conf" ]; then
    rm -f "${CONFIG_DIR}/hypr/hyprland.conf"
    echo -e "  ${S}[~] Removed stale hyprland.conf symlink (migrated to hyprland.lua).${R}"
fi
_link "${STOA_DIR}/config/waybar/config"        "${CONFIG_DIR}/waybar/config"
_link "${STOA_DIR}/config/waybar/style.css"     "${CONFIG_DIR}/waybar/style.css"
_link "${STOA_DIR}/config/noctalia/colorschemes/Stoa" \
      "${CONFIG_DIR}/noctalia/colorschemes/Stoa"
_link "${STOA_DIR}/config/noctalia/plugins.json" \
      "${CONFIG_DIR}/noctalia/plugins.json"
_link "${STOA_DIR}/theme/noctalia-plugins/stoa-memento" \
      "${CONFIG_DIR}/noctalia/plugins/stoa-memento"
_link "${STOA_DIR}/theme/noctalia-plugins/stoa-drive-pill" \
      "${CONFIG_DIR}/noctalia/plugins/stoa-drive-pill"
_link "${STOA_DIR}/theme/noctalia-plugins/stoa-health" \
      "${CONFIG_DIR}/noctalia/plugins/stoa-health"
# stoa-health replaces the old doctor-pill and vitals plugins — drop
# their stale symlinks so the plugin manager doesn't try to load them
rm -f "${CONFIG_DIR}/noctalia/plugins/stoa-doctor-pill" \
      "${CONFIG_DIR}/noctalia/plugins/stoa-vitals"

# ── Noctalia v5 ──
# v5 is configured from ~/.config/noctalia/*.toml (all merged, hot-reloaded)
# plus palettes/<name>.json. Both are symlinked so a `git pull` propagates,
# matching how every other Stoa config is wired.
#
# Note this is the same directory the v4 pair used. The two formats do not
# collide: v5 reads only *.toml and palettes/, and ignores the v4 JSON files
# below. That is what lets the legacy stack stay in place as a fallback.
mkdir -p "${CONFIG_DIR}/noctalia/palettes"
_link "${STOA_DIR}/config/noctalia/config.toml" \
      "${CONFIG_DIR}/noctalia/config.toml"
_link "${STOA_DIR}/config/noctalia/palettes/Stoa.json" \
      "${CONFIG_DIR}/noctalia/palettes/Stoa.json"

# ── Noctalia v4 (legacy) ──
# settings.json — opinionated Stoa seed (floating bar, Stoa
# color scheme, EB Garamond, layout incl. screen-toolkit/clipper/
# keybind-cheatsheet plugin widgets). Copy-seed semantics like
# stoa.conf: only place when absent so the user's tweaks survive
# reinstalls. Wipe ~/.config/noctalia/settings.json to reset.
if [ ! -f "${CONFIG_DIR}/noctalia/settings.json" ]; then
    cp "${STOA_DIR}/config/noctalia/settings.json" \
       "${CONFIG_DIR}/noctalia/settings.json"
    echo -e "  ${O}[+] ${CONFIG_DIR}/noctalia/settings.json${R}"
else
    echo -e "  ${S}[~] noctalia/settings.json already exists (preserved)${R}"
fi
_link "${STOA_DIR}/config/i3/config"            "${CONFIG_DIR}/i3/config"
_link "${STOA_DIR}/config/i3/i3status.conf"     "${CONFIG_DIR}/i3/i3status.conf"
_link "${STOA_DIR}/config/picom/picom.conf"     "${CONFIG_DIR}/picom/picom.conf"

# ── Apps ──
_link "${STOA_DIR}/config/kitty/kitty.conf" "${CONFIG_DIR}/kitty/kitty.conf"
_link "${STOA_DIR}/config/nvim/init.vim"            "${CONFIG_DIR}/nvim/init.vim"
_link "${STOA_DIR}/config/nvim/colors/stoa.vim"     "${CONFIG_DIR}/nvim/colors/stoa.vim"
_link "${STOA_DIR}/config/rofi/config.rasi"         "${CONFIG_DIR}/rofi/config.rasi"
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

# OnlyOffice theme — only seed settings.json when absent to preserve user prefs
ONLYOFFICE_DIR="${HOME}/.config/onlyoffice/desktopeditors"
if [ -d "${HOME}/.config/onlyoffice" ] || command -v onlyoffice-desktopeditors &>/dev/null; then
    mkdir -p "$ONLYOFFICE_DIR"
    if [ ! -f "${ONLYOFFICE_DIR}/settings.json" ]; then
        cp "${STOA_DIR}/theme/onlyoffice/stoa-onlyoffice.json" "${ONLYOFFICE_DIR}/settings.json" 2>/dev/null && \
            echo -e "  ${O}[+] OnlyOffice Stoa theme applied${R}" || true
    else
        echo -e "  ${S}[~] OnlyOffice settings.json preserved${R}"
    fi
fi

STEAM_CSS_DIR="${HOME}/.steam/steam/steamui"
if [ -d "${HOME}/.steam" ]; then
    _link "${STOA_DIR}/theme/steam/stoa-steam.css" "${STEAM_CSS_DIR}/libraryroot.custom.css"
    echo -e "  ${O}[+] Steam Stoa CSS linked${R}"
fi

# OnlyOffice — install Stoa theme JSON (read-only theme file, safe to link)
ONLYOFFICE_THEME_DIR="${HOME}/.local/share/onlyoffice/desktopeditors/themes"
if command -v desktopeditors &>/dev/null || [ -d "/opt/onlyoffice" ]; then
    _link "${STOA_DIR}/theme/onlyoffice/stoa-onlyoffice.json" \
          "${ONLYOFFICE_THEME_DIR}/stoa-onlyoffice.json"
    echo -e "  ${O}[+] OnlyOffice Stoa theme linked${R}"
    echo -e "  ${S}    To activate: File → Advanced Settings → Interface theme → Stoa${R}"
fi

# Div Acer Manager Max — apply Stoa theme (if installed)
if command -v div-acer-manager &>/dev/null || [ -d "/opt/div-acer-manager-max" ] || [ -d "/opt/DivAcerManagerMax" ]; then
    bash "${STOA_DIR}/theme/div-acer-manager/stoa-damx-apply.sh" apply 2>/dev/null && \
        echo -e "  ${O}[+] Div Acer Manager Stoa theme applied${R}" || true
fi

# Betterbird / Thunderbird — apply Stoa CSS to all profiles via symlink
_link_mail_profiles() {
    local label="$1" root="$2"
    [ -d "$root" ] || return 0
    for profile_dir in "${root}/"*.default*; do
        [ -d "$profile_dir" ] || continue
        _link "${STOA_DIR}/theme/betterbird/stoa-betterbird.css" \
              "${profile_dir}/chrome/userChrome.css"
        _link "${STOA_DIR}/theme/betterbird/stoa-betterbird.css" \
              "${profile_dir}/chrome/userContent.css"
        # Enable toolkit.legacyUserProfileCustomizations.stylesheets
        local prefs_file="${profile_dir}/user.js"
        if ! grep -q 'legacyUserProfileCustomizations' "$prefs_file" 2>/dev/null; then
            echo 'user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);' >> "$prefs_file"
        fi
        echo -e "  ${O}[+] ${label} Stoa CSS linked ($(basename "$profile_dir"))${R}"
    done
}
if [ -d "${HOME}/.betterbird" ]; then
    _link_mail_profiles "Betterbird" "${HOME}/.betterbird"
elif [ -d "${HOME}/.thunderbird" ]; then
    _link_mail_profiles "Thunderbird" "${HOME}/.thunderbird"
fi

# ── Pacman hook (auto-apply theme after installs) ──
# stoa-theme.hook and stoa-theme-enforce are linked in the Pacman hooks
# section below together with the other hooks that require sudo.
if ! sudo test -d /etc/pacman.d/hooks; then
    sudo mkdir -p /etc/pacman.d/hooks 2>/dev/null || \
        echo -e "  ${S}[~] Pacman hook skipped (no sudo)${R}"
fi

# VS Code — install Stoa theme as extension (via symlinks)
VSCODE_EXT_DIR="${HOME}/.vscode/extensions/stoa-theme"
_link "${STOA_DIR}/theme/vscode/package.json" \
      "${VSCODE_EXT_DIR}/package.json"
_link "${STOA_DIR}/theme/vscode/themes/stoa-color-theme.json" \
      "${VSCODE_EXT_DIR}/themes/stoa-color-theme.json"
echo -e "  ${O}[+] VS Code Stoa theme installed${R}"
echo -e "  ${S}    To activate: Ctrl+K Ctrl+T → Stoa${R}"

# ── Stoa data dirs ──
mkdir -p "${CONFIG_DIR}/stoa/wallpapers"
mkdir -p "${HOME}/Pictures/screenshots"

# ── GLSL shaders (stoa-walls + stoa-screensaver) ──
_link "${STOA_DIR}/theme/shaders" "${CONFIG_DIR}/stoa/shaders"

# ── Environment ──
_link "${STOA_DIR}/shell/stoa-env.sh" "${CONFIG_DIR}/stoa/stoa-env.sh"

# ── Stoa config (preserves user settings) ──
if [ ! -f "${CONFIG_DIR}/stoa/stoa.conf" ]; then
    cp "${STOA_DIR}/stoa.conf" "${CONFIG_DIR}/stoa/stoa.conf"
    echo -e "  ${O}[+] ${CONFIG_DIR}/stoa/stoa.conf${R}"
else
    echo -e "  ${S}[~] stoa.conf already exists (preserved)${R}"
fi

# stoa-sync manifest (same copy-seed semantics — user uncomments paths)
if [ ! -f "${CONFIG_DIR}/stoa/sync.list" ]; then
    cp "${STOA_DIR}/config/stoa/sync.list" "${CONFIG_DIR}/stoa/sync.list"
    echo -e "  ${O}[+] ${CONFIG_DIR}/stoa/sync.list${R}"
else
    echo -e "  ${S}[~] stoa/sync.list already exists (preserved)${R}"
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
_link "${STOA_DIR}/scripts/stoa-drive-status"      "${HOME}/.local/bin/stoa-drive-status"
_link "${STOA_DIR}/scripts/stoa-drive-pin"         "${HOME}/.local/bin/stoa-drive-pin"
_link "${STOA_DIR}/scripts/stoa-drive-unpin"       "${HOME}/.local/bin/stoa-drive-unpin"
_link "${STOA_DIR}/scripts/stoa-drive-emblems"     "${HOME}/.local/bin/stoa-drive-emblems"
_link "${STOA_DIR}/scripts/stoa-firewall.sh"       "${HOME}/.local/bin/stoa-firewall"
_link "${STOA_DIR}/scripts/stoa-screensaver.sh"   "${HOME}/.local/bin/stoa-screensaver"
_link "${STOA_DIR}/scripts/stoa-winapps.sh"      "${HOME}/.local/bin/stoa-winapps"
_link "${STOA_DIR}/scripts/stoa-capture.sh"       "${HOME}/.local/bin/stoa-capture"
_link "${STOA_DIR}/scripts/stoa-doctor.sh"        "${HOME}/.local/bin/stoa-doctor"
_link "${STOA_DIR}/scripts/stoa-doctor-status"    "${HOME}/.local/bin/stoa-doctor-status"
_link "${STOA_DIR}/scripts/stoa-vitals-status"    "${HOME}/.local/bin/stoa-vitals-status"
_link "${STOA_DIR}/scripts/stoa-pkg-snapshot.sh"  "${HOME}/.local/bin/stoa-pkg-snapshot"
_link "${STOA_DIR}/scripts/stoa-gpu-setup.sh"    "${HOME}/.local/bin/stoa-gpu-setup"
_link "${STOA_DIR}/scripts/stoa-display.sh"      "${HOME}/.local/bin/stoa-display"
_link "${STOA_DIR}/scripts/stoa-maintain.sh"      "${HOME}/.local/bin/stoa-maintain"
_link "${STOA_DIR}/scripts/stoa-bar.sh"           "${HOME}/.local/bin/stoa-bar"
_link "${STOA_DIR}/scripts/stoa-bar-toggle.sh"   "${HOME}/.local/bin/stoa-bar-toggle"
_link "${STOA_DIR}/scripts/stoa-sync.sh"          "${HOME}/.local/bin/stoa-sync"
_link "${STOA_DIR}/scripts/stoa-predict.sh"      "${HOME}/.local/bin/stoa-predict"
_link "${STOA_DIR}/scripts/stoa-predict.py"      "${HOME}/.local/bin/stoa-predict.py"

# The bins above are all symlinks to source files tracked in-tree with +x
# already set, so no chmod loop is needed here. If a source ever loses +x,
# fix it in the repo rather than papering over it at install time.

# ── DFM — Dotfile Manager (installed from the in-tree Stoa fork) ──
# The Stoa fork lives at scripts/stoa-dfm/ (see scripts/vendor/README.md).
# Install it editable so a `git pull` on StoaLinux propagates changes to the
# running binary, matching the symlink semantics used for every other stoa-*
# script. pipx is preferred (PEP 668 friendly); fall back to a user-local
# venv when pipx is unavailable.
DFM_SRC="${STOA_DIR}/scripts/stoa-dfm"
DFM_VENV="${HOME}/.local/share/dfm-venv"
DFM_BIN="${HOME}/.local/bin/dfm"

if [ -d "$DFM_SRC" ] && [ -f "${DFM_SRC}/setup.py" ]; then
    if command -v pipx &>/dev/null; then
        pipx install --force --editable "$DFM_SRC" >/dev/null
        echo -e "  ${O}[+] dfm (pipx, editable from scripts/stoa-dfm)${R}"
    elif command -v python3 &>/dev/null; then
        python3 -m venv "$DFM_VENV"
        "$DFM_VENV/bin/pip" install --upgrade pip >/dev/null
        "$DFM_VENV/bin/pip" install -e "$DFM_SRC" >/dev/null
        ln -sf "$DFM_VENV/bin/dfm" "$DFM_BIN"
        echo -e "  ${O}[+] dfm (venv, editable from scripts/stoa-dfm)${R}"
    else
        echo -e "  ${S}[!] python3 not found — skipping dfm install${R}"
    fi

    # Desktop entry so the Noctalia launcher / app grids pick it up.
    if [ -f "${DFM_SRC}/data/dfm.desktop" ]; then
        _link "${DFM_SRC}/data/dfm.desktop" \
              "${HOME}/.local/share/applications/dfm.desktop"
    fi
fi

# ── Pacman hooks (require sudo) ──
echo ""
echo -e "${F}Pacman hooks:${R}"
echo ""
HOOK_DIR="/etc/pacman.d/hooks"
if [ -d "$HOOK_DIR" ] || sudo mkdir -p "$HOOK_DIR" 2>/dev/null; then
    _sudo_link "${STOA_DIR}/theme/pacman-hooks/stoa-pkg-snapshot.hook" "${HOOK_DIR}/stoa-pkg-snapshot.hook"
    _sudo_link "${STOA_DIR}/theme/pacman-hooks/stoa-theme.hook"        "${HOOK_DIR}/stoa-theme.hook"
    # The hooks call /usr/local/bin/{stoa-pkg-snapshot,stoa-theme-enforce}.
    # The theme-enforce link is created above (pacman-hook block). Here we
    # link the pkg-snapshot bin — pointing at the repo source directly so
    # it also works when ~/.local/bin/stoa-pkg-snapshot (itself a symlink
    # into the repo) resolves on a per-user basis.
    _sudo_link "${STOA_DIR}/scripts/stoa-pkg-snapshot.sh" /usr/local/bin/stoa-pkg-snapshot
else
    echo -e "  ${S}[!] Could not create ${HOOK_DIR} (need sudo)${R}"
fi

# ── Polkit rules ──
POLKIT_RULES_DIR="/etc/polkit-1/rules.d"
if [ -d "$POLKIT_RULES_DIR" ] || sudo mkdir -p "$POLKIT_RULES_DIR" 2>/dev/null; then
    _sudo_link "${STOA_DIR}/config/polkit/50-stoa-wheel.rules" \
               "${POLKIT_RULES_DIR}/50-stoa-wheel.rules"
    echo -e "  ${O}[+] Polkit wheel rules installed${R}"
else
    echo -e "  ${S}[!] Could not install polkit rules (need sudo)${R}"
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

# Brave override — bypass libsecret/gnome-keyring so the browser never
# prompts for the keyring password. The local override shadows the system
# brave-browser.desktop in rofi, mimeapps, and xdg-open. Written every run
# so a Brave package update can't silently reintroduce the prompt.
BRAVE_DESKTOP="${MIME_DIR}/brave-browser.desktop"
cat > "$BRAVE_DESKTOP" <<'BRAVE'
[Desktop Entry]
Version=1.0
Name=Brave Web Browser
GenericName=Web Browser
Comment=Access the Internet
Exec=brave --password-store=basic --enable-features=UseOzonePlatform --ozone-platform=wayland %U
StartupNotify=true
Terminal=false
Icon=brave-browser
Type=Application
Categories=Network;WebBrowser;
MimeType=application/pdf;application/rdf+xml;application/rss+xml;application/xhtml+xml;application/xhtml_xml;application/xml;image/gif;image/jpeg;image/png;image/webp;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;
Actions=new-window;new-private-window;

[Desktop Action new-window]
Name=New Window
Exec=brave --password-store=basic --enable-features=UseOzonePlatform --ozone-platform=wayland

[Desktop Action new-private-window]
Name=New Incognito Window
Exec=brave --password-store=basic --enable-features=UseOzonePlatform --ozone-platform=wayland --incognito
BRAVE
echo -e "  ${O}[+] brave-browser.desktop (--password-store=basic)${R}"

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
