#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Clipboard Manager                              ║
# ║  wl-clipboard + cliphist + yad with pinned favorites         ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-clipboard show    — History (pinned on top) → paste
#   stoa-clipboard pin     — Pin/unpin item from history
#   stoa-clipboard clear   — Clear history (preserves pinned)

# ── --help ──
case "${1:-}" in
    -h|--help|help)
        cat <<'STOA_HELP'
stoa-clipboard — clipboard history with pinned entries (cliphist + yad).

USAGE
  stoa-clipboard [COMMAND]

COMMANDS
  show     history, pinned items on top; pick one to copy it   (default)
  pin      pin or unpin an item from the history
  clear    clear the history (pinned items are kept)
  help     show this help

OPTIONS
  -h, --help    show this help

FILES
  ~/.local/share/stoa/clipboard-pins    pinned entries (one per line)

RESUMO RÁPIDO
  stoa-clipboard [show | pin | clear | help]
  stoa-clipboard -h | --help
STOA_HELP
        exit 0
        ;;
esac

PINS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/stoa"
PINS_FILE="${PINS_DIR}/clipboard-pins"

mkdir -p "$PINS_DIR"
touch "$PINS_FILE"

_copy() {
    wl-copy
}

_STOA_YAD_LIB="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../lib/stoa-yad.sh"
# shellcheck source=lib/stoa-yad.sh
[ -r "$_STOA_YAD_LIB" ] && source "$_STOA_YAD_LIB"

_yad_pick() {
    stoa_yad_list "$1"
}

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
    choice=$(printf '%s%s' "$pinned" "$history" | _yad_pick "📋 Clipboard")

    [ -z "$choice" ] && exit 0

    # If it's a pinned item, remove prefix and copy
    if [[ "$choice" == "📌 "* ]]; then
        printf '%s' "${choice#📌 }" | _copy
    else
        printf '%s' "$choice" | cliphist decode | _copy
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
    choice=$(printf '%s%s' "$pinned_display" "$history" | _yad_pick "📌 Pin/Unpin")

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
