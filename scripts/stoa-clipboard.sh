#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Clipboard Manager                             ║
# ║  wl-clipboard + cliphist + rofi with pinned favorites        ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-clipboard show    — History (pinned on top) → paste
#   stoa-clipboard pin     — Pin/unpin item from history
#   stoa-clipboard clear   — Clear history (preserves pinned)

PINS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/stoa"
PINS_FILE="${PINS_DIR}/clipboard-pins"
ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

mkdir -p "$PINS_DIR"
touch "$PINS_FILE"

_show() {
    # Build list: pinned on top, then normal history
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

    # If it's a pinned item, remove prefix and copy
    if [[ "$choice" == "📌 "* ]]; then
        printf '%s' "${choice#📌 }" | wl-copy
    else
        printf '%s' "$choice" | cliphist decode | wl-copy
    fi
}

_pin() {
    # Show history + pinned for toggle
    local history
    history=$(cliphist list)

    local pinned_display=""
    if [ -s "$PINS_FILE" ]; then
        while IFS= read -r line; do
            pinned_display+="📌 [unpin] ${line}"$'\n'
        done < "$PINS_FILE"
    fi

    local choice
    choice=$(printf '%s%s' "$pinned_display" "$history" | rofi "${ROFI_ARGS[@]}" -p "📌 Pin/Unpin")

    [ -z "$choice" ] && exit 0

    if [[ "$choice" == "📌 [unpin] "* ]]; then
        # Unpin: remove from pins file
        local content="${choice#📌 \[unpin\] }"
        grep -vFx "$content" "$PINS_FILE" > "${PINS_FILE}.tmp"
        mv "${PINS_FILE}.tmp" "$PINS_FILE"
        notify-send -t 2000 "Clipboard" "Item unpinned"
    else
        # Pin: decode and add
        local decoded
        decoded=$(printf '%s' "$choice" | cliphist decode)
        # Don't duplicate
        if grep -qFx "$decoded" "$PINS_FILE" 2>/dev/null; then
            notify-send -t 2000 "Clipboard" "Item already pinned"
        else
            printf '%s\n' "$decoded" >> "$PINS_FILE"
            notify-send -t 2000 "Clipboard" "Item pinned 📌"
        fi
    fi
}

_clear() {
    cliphist wipe
    notify-send -t 2000 "Clipboard" "History cleared (pinned preserved)"
}

case "${1:-show}" in
    show)  _show  ;;
    pin)   _pin   ;;
    clear) _clear ;;
    *)     echo "Usage: stoa-clipboard {show|pin|clear}" ;;
esac
