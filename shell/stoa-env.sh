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
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

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
# export LIBVA_DRIVER_NAME=nvidia
# export VDPAU_DRIVER=nvidia
# export __GLX_VENDOR_LIBRARY_NAME=nvidia
# export GBM_BACKEND=nvidia-drm
# export NVD_BACKEND=direct
# export WLR_NO_HARDWARE_CURSORS=1
# export __GL_GSYNC_ALLOWED=1
# export __GL_VRR_ALLOWED=1

# AMD (radeonsi / RADV):
# export LIBVA_DRIVER_NAME=radeonsi
# export VDPAU_DRIVER=radeonsi

# Intel (iHD for Gen8+, i965 for older):
# export LIBVA_DRIVER_NAME=iHD
# export VDPAU_DRIVER=va_gl

# Hybrid laptops (AMD/Intel iGPU + NVIDIA dGPU, muxless HDMI on dGPU):
# Use the iGPU's VAAPI driver above, and let stoa-gpu-setup.sh add
# AQ_DRM_DEVICES to hyprland.conf so HDMI lights up on the NVIDIA card.
