#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Keybinds Toggle                               ║
# ║  Alterna a exibição dos atalhos na Waybar                    ║
# ╚══════════════════════════════════════════════════════════════╝

STOA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/stoa"
STOA_CONF="${STOA_DIR}/stoa.conf"

# Garantir que o diretório e arquivo existam
mkdir -p "$STOA_DIR"
if [ ! -f "$STOA_CONF" ]; then
    echo "STOA_SHOW_KEYBINDS=true" > "$STOA_CONF"
fi

# Ler valor atual
source "$STOA_CONF"
CURRENT="${STOA_SHOW_KEYBINDS:-true}"

# Alternar
if [ "$CURRENT" = "true" ]; then
    sed -i 's/^STOA_SHOW_KEYBINDS=.*/STOA_SHOW_KEYBINDS=false/' "$STOA_CONF"
    notify-send -t 2000 "Stoa" "Atalhos na barra: desabilitados"
else
    sed -i 's/^STOA_SHOW_KEYBINDS=.*/STOA_SHOW_KEYBINDS=true/' "$STOA_CONF"
    notify-send -t 2000 "Stoa" "Atalhos na barra: habilitados"
fi

# Recarregar Waybar para aplicar
pkill -SIGUSR2 waybar
