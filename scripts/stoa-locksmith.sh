#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — File Locksmith                                ║
# ║  Find (and unlock) whatever is holding a file or folder      ║
# ║  Requires: lsof, rofi, getent, coreutils                    ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Modeled after PowerToys' File Locksmith: point it at one or more
# files/folders and it lists every process with an open handle on
# them (folders are scanned recursively), then lets you inspect or
# end those processes to release the lock.
#
# Usage:
#   stoa-locksmith /path/to/file /path/to/dir ...  — scan directly
#   stoa-locksmith                                  — prompt for a path via rofi

ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

_notify() {
    notify-send -t "${2:-3000}" "Locksmith" "$1"
}

# Emits deduped "PID\tCOMMAND\tUID\tNAME" rows for every handle open
# under the given files/dirs. Returns 1 if nothing is locked.
_scan() {
    local raw
    raw=$(mktemp)

    for p in "$@"; do
        if [ ! -e "$p" ]; then
            _notify "Not found: $p"
            continue
        fi
        if [ -d "$p" ]; then
            timeout 20 lsof -Fpcun +D "$p" 2>/dev/null
        else
            timeout 20 lsof -Fpcun -- "$p" 2>/dev/null
        fi
    done > "$raw"

    if [ ! -s "$raw" ]; then
        rm -f "$raw"
        return 1
    fi

    awk '
        /^p/ { pid = substr($0, 2) }
        /^c/ { cmd = substr($0, 2) }
        /^u/ { uid = substr($0, 2) }
        /^n/ {
            name = substr($0, 2)
            key = pid "\t" cmd "\t" uid "\t" name
            if (!(key in seen)) {
                seen[key] = 1
                print key
            }
        }
    ' "$raw"
    rm -f "$raw"
}

_end_pid() {
    local pid="$1" signal="$2" label="$3"
    if kill "$signal" "$pid" 2>/dev/null; then
        _notify "$label sent to PID $pid" 2000
    else
        _notify "Failed to end PID $pid (try with sudo)" 2000
    fi
}

paths=("$@")

if [ ${#paths[@]} -eq 0 ]; then
    input=$(rofi "${ROFI_ARGS[@]}" -p "File or folder path")
    [ -z "$input" ] && exit 0
    paths=("$input")
fi

for p in "${paths[@]}"; do
    if [ -d "$p" ]; then
        _notify "Scanning $(basename "$p")/ for open handles…" 1500
        break
    fi
done

parsed=$(_scan "${paths[@]}")
if [ -z "$parsed" ]; then
    printf -v list '%s\n' "${paths[@]}"
    _notify "Nothing is locking:\n${list}"
    exit 0
fi

rows=()
pids=()
while IFS=$'\t' read -r pid cmd uid name; do
    [ -z "$pid" ] && continue
    user=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1)
    [ -z "$user" ] && user="$uid"
    rows+=("$(printf 'PID %-8s %-18s %-10s %s' "$pid" "$cmd" "$user" "$name")")
    pids+=("$pid")
done <<< "$parsed"

if [ ${#rows[@]} -eq 0 ]; then
    _notify "Nothing is locking the selected path(s)"
    exit 0
fi

if [ ${#paths[@]} -eq 1 ]; then
    title="Locking: $(basename "${paths[0]}")"
else
    title="Locking ${#paths[@]} selected items"
fi
end="  End all listed tasks"

menu=$(printf '%s\n' "${rows[@]}")
menu+=$'\n'"$end"

choice=$(printf '%s\n' "$menu" | rofi "${ROFI_ARGS[@]}" -p "$title")
[ -z "$choice" ] && exit 0

if [ "$choice" = "$end" ]; then
    confirm=$(printf "Yes, end all\nCancel" | rofi "${ROFI_ARGS[@]}" -p "End ${#pids[@]} process handle(s)?")
    [[ "$confirm" != Yes* ]] && exit 0

    declare -A killed
    count=0
    for pid in "${pids[@]}"; do
        [ -n "${killed[$pid]}" ] && continue
        killed[$pid]=1
        kill "$pid" 2>/dev/null && count=$((count + 1))
    done
    _notify "SIGTERM sent to $count process(es)" 2000
    exit 0
fi

pid=$(echo "$choice" | awk '{print $2}')
[ -z "$pid" ] && exit 0

action=$(printf "View details (ps)\nEnd task (SIGTERM)\nForce end task (SIGKILL)\nCancel" | \
    rofi "${ROFI_ARGS[@]}" -p "PID $pid")

case "$action" in
    "View details"*)
        details=$(ps -p "$pid" -o pid,ppid,user,%cpu,%mem,stat,start,command --no-headers 2>/dev/null)
        echo "$details" | rofi "${ROFI_ARGS[@]}" -p "Details PID $pid"
        ;;
    "End task"*)
        _end_pid "$pid" "-TERM" "SIGTERM"
        ;;
    "Force end task"*)
        _end_pid "$pid" "-KILL" "SIGKILL"
        ;;
esac
