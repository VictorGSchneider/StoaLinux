#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Environment Variables                         ║
# ║  "Unity is strength." — Seneca                              ║
# ║                                                              ║
# ║  Standardizes toolkits (GTK, Qt, Electron) for consistent   ║
# ║  appearance and defines default apps.                        ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Global dark theme ──
export GTK_THEME="Adwaita:dark"
export GTK2_RC_FILES="/usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc"

# ── Qt uses qt5ct/qt6ct to respect dark theme ──
export QT_QPA_PLATFORMTHEME="qt5ct"
export QT_STYLE_OVERRIDE="Fusion"
export QT_AUTO_SCREEN_SCALE_FACTOR=1

# ── Electron/Chromium (Brave) in dark mode ──
export ELECTRON_OZONE_PLATFORM_HINT="auto"

# ── Default apps ──
export BROWSER="brave"
export EDITOR="nvim"
export VISUAL="nvim"
export TERMINAL="kitty"
export FILE_MANAGER="thunar"
export PAGER="less"

# ── XDG ──
# Inside a session the compositor sets XDG_CURRENT_DESKTOP itself (niri:
# "niri", Hyprland: "Hyprland" via hyprland.lua). This fallback only covers
# shells started outside one — a TTY login, which tty1 autostart then hands
# to the compositor — so it follows the compositor Stoa starts there:
# ~/.config/stoa/wm (post-install.sh / `stoa-wm set`), else whichever is
# installed, Hyprland first, the same pick as stoa-autostart-hyprland.sh.
# A wrong value here makes xdg-desktop-portal pick the other compositor's
# backend (screen sharing, file pickers).
if [ -z "${XDG_CURRENT_DESKTOP:-}" ]; then
    _stoa_wm_env=$(head -n1 "${XDG_CONFIG_HOME:-$HOME/.config}/stoa/wm" 2>/dev/null | tr -d '[:space:]')
    case "$_stoa_wm_env" in
        niri|hyprland) ;;
        *) if ! command -v Hyprland >/dev/null 2>&1 && command -v niri >/dev/null 2>&1; then
               _stoa_wm_env=niri
           fi ;;
    esac
    case "$_stoa_wm_env" in
        niri) export XDG_CURRENT_DESKTOP="niri" ;;
        *)    export XDG_CURRENT_DESKTOP="Hyprland" ;;
    esac
    unset _stoa_wm_env
fi
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# ── Quickshell / Noctalia icon theme ──
# QT_QPA_PLATFORMTHEME above is a Qt5-only plugin name, so Qt6 apps —
# Quickshell, and with it Noctalia — get no platform theme and fall back to
# the "hicolor" icon theme. That leaves every desktop entry pointing at a
# generic freedesktop icon name without a match, drawing the placeholder tile
# in the launcher. QS_ICON_THEME is Quickshell's own override and takes
# precedence, so mirror the GTK icon theme into it.
QS_ICON_THEME=$(sed -n 's/^gtk-icon-theme-name[[:space:]]*=[[:space:]]*//p' \
    "${XDG_CONFIG_HOME}/gtk-3.0/settings.ini" 2>/dev/null | head -1)
export QS_ICON_THEME="${QS_ICON_THEME:-Colloid-dark}"

# ── Cursor ──
export XCURSOR_THEME="Colloid-cursors"
export XCURSOR_SIZE=24

# ── Gaming (Steam) ──
export STEAM_FORCE_DESKTOPUI_SCALING=1
export PROTON_ENABLE_NVAPI=1

# ── GPU / Wayland — set by stoa-gpu-setup.sh ──
# These are commented out by default. Run `scripts/stoa-gpu-setup.sh`
# and it will uncomment the lines matching your GPU. Setting them
# manually for the wrong vendor breaks VAAPI / Wayland (e.g.
# LIBVA_DRIVER_NAME=nvidia on an AMD/Intel iGPU disables hw decode).

# NVIDIA (proprietary, Wayland):
export LIBVA_DRIVER_NAME=radeonsi
export VDPAU_DRIVER=radeonsi
# export __GLX_VENDOR_LIBRARY_NAME=nvidia
# export GBM_BACKEND=nvidia-drm
# export NVD_BACKEND=direct
export WLR_NO_HARDWARE_CURSORS=1
export __GL_GSYNC_ALLOWED=1
export __GL_VRR_ALLOWED=1

# AMD (radeonsi / RADV):
export LIBVA_DRIVER_NAME=radeonsi
export VDPAU_DRIVER=radeonsi

# Intel (iHD for Gen8+, i965 for older):
export LIBVA_DRIVER_NAME=radeonsi
export VDPAU_DRIVER=radeonsi

# Hybrid laptops (AMD/Intel iGPU + NVIDIA dGPU, muxless HDMI on dGPU):
# Use the iGPU's VAAPI driver above, and let stoa-gpu-setup.sh add
# AQ_DRM_DEVICES to hyprland.lua so HDMI lights up on the NVIDIA card.
