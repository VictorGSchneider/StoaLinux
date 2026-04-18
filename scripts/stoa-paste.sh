#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Advanced Paste                                ║
# ║  Paste clipboard content in different formats                ║
# ║  Requires: wl-clipboard, rofi, jq (optional)                ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-paste          — menu with format options
#   stoa-paste plain    — paste as plain text (no formatting)

ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

# Detect session type
_is_wayland() { [ -n "${WAYLAND_DISPLAY:-}" ]; }

_get_clipboard() {
    if _is_wayland; then
        wl-paste 2>/dev/null
    else
        xclip -selection clipboard -o 2>/dev/null
    fi
}

_set_clipboard() {
    if _is_wayland; then
        wl-copy "$1"
    else
        printf '%s' "$1" | xclip -selection clipboard
    fi
}

_type_text() {
    # Simulate typing via wtype (Wayland)
    if command -v wtype &>/dev/null; then
        wtype -d 10 -- "$1"
    else
        _set_clipboard "$1"
        notify-send -t 2000 "Advanced Paste" "Copied (install wtype for typing)"
    fi
}

_paste_plain() {
    local text
    text=$(_get_clipboard)
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Plain text copied"
}

_paste_upper() {
    local text
    text=$(_get_clipboard | tr '[:lower:]' '[:upper:]')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "UPPERCASE copied"
}

_paste_lower() {
    local text
    text=$(_get_clipboard | tr '[:upper:]' '[:lower:]')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "lowercase copied"
}

_paste_title() {
    local text
    text=$(_get_clipboard | sed 's/\b\(.\)/\u\1/g')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Title Case copied"
}

_paste_sentence() {
    local text
    text=$(_get_clipboard | sed 's/.*/\L&/' | sed 's/^\(.\)/\U\1/' | sed 's/\. \(.\)/. \U\1/g')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Sentence case copied"
}

_paste_trim() {
    local text
    text=$(_get_clipboard | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -s '[:space:]' ' ')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Trimmed whitespace, copied"
}

_paste_single_line() {
    local text
    text=$(_get_clipboard | tr '\n' ' ' | sed 's/  */ /g;s/^ //;s/ $//')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Single line copied"
}

_paste_snake() {
    local text
    text=$(_get_clipboard | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/_/g' | sed 's/[^a-z0-9_]//g')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "snake_case copied"
}

_paste_camel() {
    local text
    text=$(_get_clipboard | sed 's/[_-]/ /g' | sed 's/\b\(.\)/\u\1/g' | sed 's/ //g' | sed 's/^\(.\)/\l\1/')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "camelCase copied"
}

_paste_json_format() {
    local text
    text=$(_get_clipboard)
    if command -v jq &>/dev/null; then
        local formatted
        formatted=$(echo "$text" | jq . 2>/dev/null)
        if [ $? -eq 0 ]; then
            _set_clipboard "$formatted"
            notify-send -t 1500 "Advanced Paste" "Formatted JSON copied"
        else
            notify-send -t 2000 "Advanced Paste" "Clipboard does not contain valid JSON"
        fi
    else
        notify-send -t 2000 "Advanced Paste" "jq not installed"
    fi
}

_paste_markdown_clean() {
    local text
    text=$(_get_clipboard | sed 's/[#*_`~>\[\]]//g' | sed '/^---$/d' | sed '/^===$/d')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Clean Markdown copied"
}

_menu() {
    local options=(
        "Plain text (no formatting)"
        "UPPERCASE"
        "lowercase"
        "Title Case"
        "Sentence case"
        "Trim extra whitespace"
        "Single line (no breaks)"
        "snake_case"
        "camelCase"
        "Format JSON"
        "Strip Markdown"
    )

    local choice
    choice=$(printf '%s\n' "${options[@]}" | rofi "${ROFI_ARGS[@]}" -p "Paste as")
    [ -z "$choice" ] && exit 0

    case "$choice" in
        "Plain"*)          _paste_plain ;;
        "UPPERCASE"*)      _paste_upper ;;
        "lowercase"*)      _paste_lower ;;
        "Title"*)          _paste_title ;;
        "Sentence"*)       _paste_sentence ;;
        "Trim"*)           _paste_trim ;;
        "Single"*)         _paste_single_line ;;
        "snake"*)          _paste_snake ;;
        "camel"*)          _paste_camel ;;
        "Format JSON"*)    _paste_json_format ;;
        "Strip"*)          _paste_markdown_clean ;;
    esac
}

case "${1:-}" in
    plain)     _paste_plain ;;
    upper)     _paste_upper ;;
    lower)     _paste_lower ;;
    title)     _paste_title ;;
    trim)      _paste_trim ;;
    snake)     _paste_snake ;;
    camel)     _paste_camel ;;
    json)      _paste_json_format ;;
    markdown)  _paste_markdown_clean ;;
    *)         _menu ;;
esac
