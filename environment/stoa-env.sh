#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Variáveis de Ambiente                        ║
# ║  "A unidade é força." — Sêneca                              ║
# ║                                                              ║
# ║  Padroniza toolkits (GTK, Qt, Electron) para aparência      ║
# ║  consistente e define apps padrão.                           ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Tema escuro global ──
export GTK_THEME="Adwaita:dark"
export GTK2_RC_FILES="/usr/share/themes/Adwaita-dark/gtk-2.0/gtkrc"

# ── Qt usa qt5ct/qt6ct para respeitar tema escuro ──
export QT_QPA_PLATFORMTHEME="qt5ct"
export QT_STYLE_OVERRIDE="Fusion"
export QT_AUTO_SCREEN_SCALE_FACTOR=1

# ── Electron/Chromium (Brave) em modo escuro ──
export ELECTRON_OZONE_PLATFORM_HINT="auto"

# ── Apps padrão ──
export BROWSER="brave"
export EDITOR="nvim"
export VISUAL="nvim"
export TERMINAL="alacritty"
export FILE_MANAGER="lf"
export PAGER="less"

# ── XDG ──
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

# ── Cursor ──
export XCURSOR_THEME="Adwaita"
export XCURSOR_SIZE=24

# ── NVIDIA (Wayland) ──
# Descomente se usar GPU NVIDIA com Hyprland:
# export LIBVA_DRIVER_NAME=nvidia
# export __GLX_VENDOR_LIBRARY_NAME=nvidia
# export GBM_BACKEND=nvidia-drm
# export NVD_BACKEND=direct
# export WLR_NO_HARDWARE_CURSORS=1
# export __GL_GSYNC_ALLOWED=1
# export __GL_VRR_ALLOWED=1
