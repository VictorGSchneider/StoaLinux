#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — File Locksmith                                ║
# ║  Descobre qual processo está travando um arquivo             ║
# ║  Requer: lsof, rofi                                         ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Uso:
#   stoa-locksmith /caminho/arquivo  — mostra processos direto
#   stoa-locksmith                   — abre rofi para digitar caminho

ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

_check_file() {
    local file="$1"

    if [ ! -e "$file" ]; then
        notify-send -t 3000 "Locksmith" "Arquivo não encontrado: $file"
        exit 1
    fi

    local result
    result=$(lsof -- "$file" 2>/dev/null | tail -n +2)

    if [ -z "$result" ]; then
        notify-send -t 3000 "Locksmith" "Nenhum processo usando:\n$file"
        exit 0
    fi

    # Formata: PID | COMMAND | USER | TYPE
    local formatted
    formatted=$(echo "$result" | awk '{printf "PID %-8s  %-20s  %-12s  %s\n", $2, $1, $3, $5}')

    local choice
    choice=$(echo "$formatted" | rofi "${ROFI_ARGS[@]}" -p "Processos usando: $(basename "$file")")

    [ -z "$choice" ] && exit 0

    # Extrai PID da seleção
    local pid
    pid=$(echo "$choice" | awk '{print $2}')

    # Pergunta se quer matar
    local action
    action=$(printf "Ver detalhes (ps)\nMatar processo (SIGTERM)\nForçar matar (SIGKILL)\nCancelar" | \
        rofi "${ROFI_ARGS[@]}" -p "PID $pid")

    case "$action" in
        "Ver detalhes"*)
            local details
            details=$(ps -p "$pid" -o pid,ppid,user,%cpu,%mem,stat,start,command --no-headers 2>/dev/null)
            echo "$details" | rofi "${ROFI_ARGS[@]}" -p "Detalhes PID $pid"
            ;;
        "Matar processo"*)
            kill "$pid" 2>/dev/null && \
                notify-send -t 2000 "Locksmith" "SIGTERM enviado ao PID $pid" || \
                notify-send -t 2000 "Locksmith" "Falha ao matar PID $pid (tente com sudo)"
            ;;
        "Forçar matar"*)
            kill -9 "$pid" 2>/dev/null && \
                notify-send -t 2000 "Locksmith" "SIGKILL enviado ao PID $pid" || \
                notify-send -t 2000 "Locksmith" "Falha ao matar PID $pid (tente com sudo)"
            ;;
    esac
}

if [ -n "$1" ]; then
    _check_file "$1"
else
    file=$(rofi "${ROFI_ARGS[@]}" -p "Caminho do arquivo")
    [ -z "$file" ] && exit 0
    _check_file "$file"
fi
