#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — File Locksmith                                ║
# ║  Find which process is locking a file                        ║
# ║  Requires: lsof, rofi                                       ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-locksmith /path/to/file  — show processes directly
#   stoa-locksmith                — open rofi to type path

ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

_check_file() {
    local file="$1"

    if [ ! -e "$file" ]; then
        notify-send -t 3000 "Locksmith" "File not found: $file"
        exit 1
    fi

    local result
    result=$(lsof -- "$file" 2>/dev/null | tail -n +2)

    if [ -z "$result" ]; then
        notify-send -t 3000 "Locksmith" "No process using:\n$file"
        exit 0
    fi

    # Format: PID | COMMAND | USER | TYPE
    local formatted
    formatted=$(echo "$result" | awk '{printf "PID %-8s  %-20s  %-12s  %s\n", $2, $1, $3, $5}')

    local choice
    choice=$(echo "$formatted" | rofi "${ROFI_ARGS[@]}" -p "Processes using: $(basename "$file")")

    [ -z "$choice" ] && exit 0

    # Extract PID from selection
    local pid
    pid=$(echo "$choice" | awk '{print $2}')

    # Ask what to do
    local action
    action=$(printf "View details (ps)\nKill process (SIGTERM)\nForce kill (SIGKILL)\nCancel" | \
        rofi "${ROFI_ARGS[@]}" -p "PID $pid")

    case "$action" in
        "View details"*)
            local details
            details=$(ps -p "$pid" -o pid,ppid,user,%cpu,%mem,stat,start,command --no-headers 2>/dev/null)
            echo "$details" | rofi "${ROFI_ARGS[@]}" -p "Details PID $pid"
            ;;
        "Kill process"*)
            kill "$pid" 2>/dev/null && \
                notify-send -t 2000 "Locksmith" "SIGTERM sent to PID $pid" || \
                notify-send -t 2000 "Locksmith" "Failed to kill PID $pid (try with sudo)"
            ;;
        "Force kill"*)
            kill -9 "$pid" 2>/dev/null && \
                notify-send -t 2000 "Locksmith" "SIGKILL sent to PID $pid" || \
                notify-send -t 2000 "Locksmith" "Failed to kill PID $pid (try with sudo)"
            ;;
    esac
}

if [ -n "$1" ]; then
    _check_file "$1"
else
    file=$(rofi "${ROFI_ARGS[@]}" -p "File path")
    [ -z "$file" ] && exit 0
    _check_file "$file"
fi
