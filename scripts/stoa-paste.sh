#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Advanced Paste                                ║
# ║  Cola conteúdo do clipboard em diferentes formatos           ║
# ║  Requer: wl-clipboard, rofi, jq (opcional)                  ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Uso:
#   stoa-paste          — menu com opções de formatação
#   stoa-paste plain    — cola como texto puro (sem formatação)

ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

_get_clipboard() {
    wl-paste 2>/dev/null
}

_set_clipboard() {
    wl-copy "$1"
}

_type_text() {
    # Simula digitação via wtype (Wayland)
    if command -v wtype &>/dev/null; then
        wtype -d 10 -- "$1"
    else
        _set_clipboard "$1"
        notify-send -t 2000 "Advanced Paste" "Conteúdo copiado (instale wtype para digitar)"
    fi
}

_paste_plain() {
    local text
    text=$(_get_clipboard)
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Texto puro copiado"
}

_paste_upper() {
    local text
    text=$(_get_clipboard | tr '[:lower:]' '[:upper:]')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "MAIÚSCULAS copiado"
}

_paste_lower() {
    local text
    text=$(_get_clipboard | tr '[:upper:]' '[:lower:]')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "minúsculas copiado"
}

_paste_title() {
    local text
    text=$(_get_clipboard | sed 's/\b\(.\)/\u\1/g')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Título Capitalizado copiado"
}

_paste_sentence() {
    local text
    text=$(_get_clipboard | sed 's/.*/\L&/' | sed 's/^\(.\)/\U\1/' | sed 's/\. \(.\)/. \U\1/g')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Frase capitalizada copiado"
}

_paste_trim() {
    local text
    text=$(_get_clipboard | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -s '[:space:]' ' ')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Espaços removidos, copiado"
}

_paste_single_line() {
    local text
    text=$(_get_clipboard | tr '\n' ' ' | sed 's/  */ /g;s/^ //;s/ $//')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Linha única copiado"
}

_paste_snake() {
    local text
    text=$(_get_clipboard | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/_/g' | sed 's/[^a-z0-9_]//g')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "snake_case copiado"
}

_paste_camel() {
    local text
    text=$(_get_clipboard | sed 's/[_-]/ /g' | sed 's/\b\(.\)/\u\1/g' | sed 's/ //g' | sed 's/^\(.\)/\l\1/')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "camelCase copiado"
}

_paste_json_format() {
    local text
    text=$(_get_clipboard)
    if command -v jq &>/dev/null; then
        local formatted
        formatted=$(echo "$text" | jq . 2>/dev/null)
        if [ $? -eq 0 ]; then
            _set_clipboard "$formatted"
            notify-send -t 1500 "Advanced Paste" "JSON formatado copiado"
        else
            notify-send -t 2000 "Advanced Paste" "Clipboard não contém JSON válido"
        fi
    else
        notify-send -t 2000 "Advanced Paste" "jq não instalado"
    fi
}

_paste_markdown_clean() {
    local text
    text=$(_get_clipboard | sed 's/[#*_`~>\[\]]//g' | sed '/^---$/d' | sed '/^===$/d')
    _set_clipboard "$text"
    notify-send -t 1500 "Advanced Paste" "Markdown limpo copiado"
}

_menu() {
    local options=(
        "Texto puro (sem formatação)"
        "MAIÚSCULAS"
        "minúsculas"
        "Título Capitalizado"
        "Frase capitalizada"
        "Remover espaços extras"
        "Linha única (sem quebras)"
        "snake_case"
        "camelCase"
        "Formatar JSON"
        "Limpar Markdown"
    )

    local choice
    choice=$(printf '%s\n' "${options[@]}" | rofi "${ROFI_ARGS[@]}" -p "Colar como")
    [ -z "$choice" ] && exit 0

    case "$choice" in
        "Texto puro"*)     _paste_plain ;;
        "MAIÚSCULAS"*)     _paste_upper ;;
        "minúsculas"*)     _paste_lower ;;
        "Título"*)         _paste_title ;;
        "Frase"*)          _paste_sentence ;;
        "Remover"*)        _paste_trim ;;
        "Linha"*)          _paste_single_line ;;
        "snake"*)          _paste_snake ;;
        "camel"*)          _paste_camel ;;
        "Formatar JSON"*)  _paste_json_format ;;
        "Limpar"*)         _paste_markdown_clean ;;
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
