#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — File Locksmith                                ║
# ║  Find (and unlock) whatever is holding a file or folder      ║
# ║  Requires: lsof, yad, getent, coreutils                     ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Modeled after PowerToys' File Locksmith: point it at one or more
# files/folders and it lists every process with an open handle on
# them (folders are scanned recursively), then lets you inspect or
# end those processes to release the lock.
#
# Usage:
#   stoa-locksmith /path/to/file /path/to/dir ...  — scan directly
#   stoa-locksmith                                  — prompt for a path via yad

_notify() {
    notify-send -t "${2:-3000}" "Locksmith" "$1"
}

if ! command -v yad &>/dev/null; then
    echo "stoa-locksmith: 'yad' not found in PATH" >&2
    _notify "yad not installed.\nInstall: sudo pacman -S yad" 5000
    exit 1
fi

# yad convention: an EVEN --button response code dumps the widget's
# value to stdout before exiting; an ODD code just exits with it.
YAD_CANCEL=1
YAD_VIEW=2
YAD_END=4
YAD_FORCE=6

SEP=$'\x1f'

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

_end_pids() {
    local signal="$1" label="$2"; shift 2
    local count=0
    for pid in "$@"; do
        kill "$signal" "$pid" 2>/dev/null && count=$((count + 1))
    done
    _notify "$label sent to $count process(es)" 2000
}

paths=("$@")

if [ ${#paths[@]} -eq 0 ]; then
    input=$(yad --entry --title="Locksmith" --text="File or folder path" --width=400)
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

entries=()
while IFS=$'\t' read -r pid cmd uid name; do
    [ -z "$pid" ] && continue
    user=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1)
    [ -z "$user" ] && user="$uid"
    entries+=("${pid}${SEP}${cmd}${SEP}${user}${SEP}${name}")
done <<< "$parsed"

if [ ${#entries[@]} -eq 0 ]; then
    _notify "Nothing is locking the selected path(s)"
    exit 0
fi

if [ ${#paths[@]} -eq 1 ]; then
    title="Locking: $(basename "${paths[0]}")"
else
    title="Locking ${#paths[@]} selected items"
fi

# Pre-check the row when there's only one result, so it can be acted
# on with a single button click and no extra checkbox tick.
default_check=FALSE
[ ${#entries[@]} -eq 1 ] && default_check=TRUE

rows=()
for entry in "${entries[@]}"; do
    IFS="$SEP" read -r pid cmd user name <<< "$entry"
    rows+=("$default_check" "$pid" "$cmd" "$user" "$name")
done

output=$(yad --list --checklist --title="Locksmith" --text="$title" \
    --column="Sel":CHK --column="PID":NUM --column="Command" --column="User" --column="File" \
    --separator="$SEP" \
    "${rows[@]}" \
    --width=760 --height=320 \
    --button="Cancel:$YAD_CANCEL" \
    --button="View Details:$YAD_VIEW" \
    --button="End Task(s):$YAD_END" \
    --button="Force End:$YAD_FORCE")
rc=$?

[ "$rc" -eq "$YAD_CANCEL" ] && exit 0

pids=()
while IFS="$SEP" read -r _ pid _ _ _; do
    [ -n "$pid" ] && pids+=("$pid")
done <<< "$output"

if [ ${#pids[@]} -eq 0 ]; then
    _notify "No process selected"
    exit 0
fi

mapfile -t pids < <(printf '%s\n' "${pids[@]}" | sort -un)

case "$rc" in
    "$YAD_VIEW")
        details=$(ps -p "$(IFS=,; echo "${pids[*]}")" \
            -o pid,ppid,user,%cpu,%mem,stat,start,command --no-headers 2>/dev/null)
        yad --text-info --title="Process details" --fontname="monospace 10" \
            --width=700 --height=200 --button="Close:1" <<< "$details"
        ;;
    "$YAD_END"|"$YAD_FORCE")
        if [ ${#pids[@]} -gt 1 ]; then
            yad --question --title="Locksmith" \
                --text="End ${#pids[@]} process(es)?" \
                --button="Cancel:1" --button="Yes, end all:0"
            [ $? -ne 0 ] && exit 0
        fi
        if [ "$rc" -eq "$YAD_FORCE" ]; then
            _end_pids "-KILL" "SIGKILL" "${pids[@]}"
        else
            _end_pids "-TERM" "SIGTERM" "${pids[@]}"
        fi
        ;;
esac
