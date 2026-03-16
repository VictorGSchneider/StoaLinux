#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Clipboard Manager                             ║
# ║  wl-clipboard + cliphist + rofi com favoritos                ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Uso:
#   stoa-clipboard show    — Histórico (fixados no topo) → colar
#   stoa-clipboard pin     — Fixar/desfixar item do histórico
#   stoa-clipboard clear   — Limpar histórico (preserva fixados)

PINS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/stoa"
PINS_FILE="${PINS_DIR}/clipboard-pins"
ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

mkdir -p "$PINS_DIR"
touch "$PINS_FILE"

_show() {
    # Monta lista: fixados no topo, depois histórico normal
    local pinned=""
    local history

    if [ -s "$PINS_FILE" ]; then
        while IFS= read -r line; do
            pinned+="📌 ${line}"$'\n'
        done < "$PINS_FILE"
    fi

    history=$(cliphist list)

    local choice
    choice=$(printf '%s%s' "$pinned" "$history" | rofi "${ROFI_ARGS[@]}" -p "📋 Clipboard")

    [ -z "$choice" ] && exit 0

    # Se é um item fixado, remover prefixo e copiar
    if [[ "$choice" == "📌 "* ]]; then
        printf '%s' "${choice#📌 }" | wl-copy
    else
        printf '%s' "$choice" | cliphist decode | wl-copy
    fi
}

_pin() {
    # Mostra histórico + fixados para toggle
    local history
    history=$(cliphist list)

    local pinned_display=""
    if [ -s "$PINS_FILE" ]; then
        while IFS= read -r line; do
            pinned_display+="📌 [desfixar] ${line}"$'\n'
        done < "$PINS_FILE"
    fi

    local choice
    choice=$(printf '%s%s' "$pinned_display" "$history" | rofi "${ROFI_ARGS[@]}" -p "📌 Fixar/Desfixar")

    [ -z "$choice" ] && exit 0

    if [[ "$choice" == "📌 [desfixar] "* ]]; then
        # Desfixar: remover do arquivo de pins
        local content="${choice#📌 \[desfixar\] }"
        grep -vFx "$content" "$PINS_FILE" > "${PINS_FILE}.tmp"
        mv "${PINS_FILE}.tmp" "$PINS_FILE"
        notify-send -t 2000 "Clipboard" "Item desfixado"
    else
        # Fixar: decodificar e adicionar
        local decoded
        decoded=$(printf '%s' "$choice" | cliphist decode)
        # Não duplicar
        if grep -qFx "$decoded" "$PINS_FILE" 2>/dev/null; then
            notify-send -t 2000 "Clipboard" "Item já está fixado"
        else
            printf '%s\n' "$decoded" >> "$PINS_FILE"
            notify-send -t 2000 "Clipboard" "Item fixado 📌"
        fi
    fi
}

_clear() {
    cliphist wipe
    notify-send -t 2000 "Clipboard" "Histórico limpo (fixados preservados)"
}

case "${1:-show}" in
    show)  _show  ;;
    pin)   _pin   ;;
    clear) _clear ;;
    *)     echo "Uso: stoa-clipboard {show|pin|clear}" ;;
esac
