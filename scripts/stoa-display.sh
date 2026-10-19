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
# Bound by hyprland.lua and niri/config.kdl to XF86Display (Fn+F7 on Acer
# Nitro) and Super+P (Win+P-style fallback for laptops whose Fn key is dead).
# Works in both compositors through lib/stoa-wm.sh. niri cannot mirror on its
# own: the mirror step needs wl-mirror and is skipped without it.

set -euo pipefail

_STOA_LIB="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/lib"
# shellcheck source=lib/stoa-wm.sh
source "$_STOA_LIB/stoa-wm.sh"

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/stoa-display-mode"

_notify() {
    notify-send -t 2500 -i video-display "Display" "$1" 2>/dev/null || true
}

# --- Detect monitors ---------------------------------------------------
# Internal: first eDP/LVDS panel.
# External: first non-eDP monitor (HDMI / DP / DVI), even if currently off.
INTERNAL=$(stoa_wm_internal_output || true)
EXTERNAL=$(stoa_wm_external_output || true)

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
        stoa_wm_output_extend "$EXTERNAL" "$INTERNAL"
        _notify "Estendido → ${EXTERNAL} à direita de ${INTERNAL}"
        ;;
    extend)
        if stoa_wm_can_mirror; then
            NEXT="mirror"
            stoa_wm_output_mirror "$EXTERNAL" "$INTERNAL"
            _notify "Espelhado → ${EXTERNAL} clona ${INTERNAL}"
        else
            # No mirroring here (niri without wl-mirror): skip to laptop-only.
            NEXT="laptop"
            stoa_wm_output_disable "$EXTERNAL"
            _notify "Apenas laptop (${INTERNAL}) — espelhar requer wl-mirror"
        fi
        ;;
    mirror|*)
        NEXT="laptop"
        stoa_wm_output_disable "$EXTERNAL"
        _notify "Apenas laptop (${INTERNAL})"
        ;;
esac

echo "$NEXT" > "$STATE_FILE"
