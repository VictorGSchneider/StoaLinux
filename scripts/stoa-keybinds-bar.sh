#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Keybinds Bar                                  ║
# ║  Módulo Waybar: mostra atalhos principais na barra           ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Lê STOA_SHOW_KEYBINDS do stoa.conf.
# Waybar esconde módulos custom com output vazio.

STOA_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/stoa/stoa.conf"

# Carregar config
if [ -f "$STOA_CONF" ]; then
    # shellcheck source=/dev/null
    source "$STOA_CONF"
fi

# Padrão: habilitado
STOA_SHOW_KEYBINDS="${STOA_SHOW_KEYBINDS:-true}"

if [ "$STOA_SHOW_KEYBINDS" != "true" ]; then
    echo ""
    exit 0
fi

# Texto compacto para a barra
TEXT="⏎ Term │ B Brave │ D Rofi │ E Arquivos │ N Monitor │ O Notas │ V Clipboard │ Q Fechar │ F Full │ HJKL Nav"

# Tooltip completo
TOOLTIP="╔═══ STOA KEYBINDS ═══╗\n"
TOOLTIP+="Super+Enter   Terminal\n"
TOOLTIP+="Super+B       Brave Browser\n"
TOOLTIP+="Super+D       Rofi (launcher)\n"
TOOLTIP+="Super+E       Arquivos (lf)\n"
TOOLTIP+="Super+N       Monitor (btop)\n"
TOOLTIP+="Super+O       Obsidian\n"
TOOLTIP+="Super+M       Memento Mori\n"
TOOLTIP+="Super+V       Clipboard (histórico)\n"
TOOLTIP+="Super+Shift+V Fixar item no clipboard\n"
TOOLTIP+="Super+Q       Fechar janela\n"
TOOLTIP+="Super+F       Fullscreen\n"
TOOLTIP+="Super+Shift+Space  Flutuante\n"
TOOLTIP+="─────────────────────\n"
TOOLTIP+="Super+HJKL    Navegação\n"
TOOLTIP+="Super+Shift+HJKL  Mover janela\n"
TOOLTIP+="Super+R       Modo resize\n"
TOOLTIP+="Super+1-0     Workspaces I-X\n"
TOOLTIP+="─────────────────────\n"
TOOLTIP+="Print         Screenshot (satty)\n"
TOOLTIP+="Super+Print   Screenshot (seleção)\n"
TOOLTIP+="Super+/       Ocultar/mostrar atalhos\n"
TOOLTIP+="╚═════════════════════╝"

# Waybar JSON format
printf '{"text": "%s", "tooltip": "%s", "class": "keybinds"}' "$TEXT" "$TOOLTIP"
