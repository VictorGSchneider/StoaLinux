#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Display toggle                                ║
# ║  "The impediment to action advances action."                 ║
# ║                                  — Marcus Aurelius            ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Cycles the external monitor through three modes on each invocation:
#   1. laptop-only  — external disabled
#   2. extend-right — external placed to the right of the internal
#   3. mirror       — external mirrors the internal panel
#
# Bound by hyprland.conf to XF86Display (Fn+F7 on Acer Nitro) and
# Super+P (Win+P-style fallback for laptops whose Fn key is dead).

set -euo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/stoa-display-mode"

_notify() {
    notify-send -t 2500 -i video-display "Display" "$1" 2>/dev/null || true
}

# --- Detect monitors ---------------------------------------------------
# Internal: first connected eDP/LVDS panel.
# External: first connected non-eDP monitor (HDMI / DP / DVI).
INTERNAL=$(hyprctl monitors all -j 2>/dev/null \
    | jq -r 'first(.[] | select(.name | test("^(eDP|LVDS)"; "i")) | .name)' \
    || true)

EXTERNAL=$(hyprctl monitors all -j 2>/dev/null \
    | jq -r 'first(.[] | select(.name | test("^(eDP|LVDS)"; "i") | not) | .name)' \
    || true)

if [ -z "$INTERNAL" ] || [ "$INTERNAL" = "null" ]; then
    _notify "Sem painel interno detectado"
    exit 1
fi

if [ -z "$EXTERNAL" ] || [ "$EXTERNAL" = "null" ]; then
    _notify "Nenhum monitor externo conectado"
    exit 0
fi

# --- Cycle: laptop → extend → mirror → laptop ... ---------------------
LAST=$(cat "$STATE_FILE" 2>/dev/null || echo "laptop")

case "$LAST" in
    laptop)
        NEXT="extend"
        hyprctl keyword monitor "${EXTERNAL},preferred,auto-right,1" >/dev/null
        _notify "Estendido → ${EXTERNAL} à direita de ${INTERNAL}"
        ;;
    extend)
        NEXT="mirror"
        hyprctl keyword monitor "${EXTERNAL},preferred,auto,1,mirror,${INTERNAL}" >/dev/null
        _notify "Espelhado → ${EXTERNAL} clona ${INTERNAL}"
        ;;
    mirror|*)
        NEXT="laptop"
        hyprctl keyword monitor "${EXTERNAL},disable" >/dev/null
        _notify "Apenas laptop (${INTERNAL})"
        ;;
esac

echo "$NEXT" > "$STATE_FILE"
