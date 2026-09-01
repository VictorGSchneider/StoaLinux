#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Stoatools Archive                              ║
# ║  Compress files/folders or extract archives                  ║
# ║  Requires: zip, unzip, tar, yad                              ║
# ║  Optional: p7zip (7z format), unrar (.rar extraction)         ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-archive file1 [file2 ...]   — compress selection, or
#                                       extract if all are archives
#
# Called directly from Thunar's "Stoatools" custom-action submenu
# (see config/thunar/uca.xml) with the current Thunar selection.

_notify() {
    notify-send -t "${2:-3000}" "Archive" "$1"
}

_is_archive() {
    case "${1,,}" in
        *.zip|*.tar|*.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tbz|*.tar.xz|*.txz|*.7z|*.rar)
            return 0 ;;
        *) return 1 ;;
    esac
}

# Splits "name.tar.gz" -> "name<TAB>tar.gz". Files with no known archive
# extension pass through as "name<TAB>" (used for de-duplicating plain
# extraction folder names too).
_split_archive_name() {
    local base="$1"
    case "${base,,}" in
        *.tar.gz)  printf '%s\t%s\n' "${base%.*.*}" "tar.gz" ;;
        *.tar.bz2) printf '%s\t%s\n' "${base%.*.*}" "tar.bz2" ;;
        *.tar.xz)  printf '%s\t%s\n' "${base%.*.*}" "tar.xz" ;;
        *.tgz)     printf '%s\t%s\n' "${base%.*}" "tgz" ;;
        *.tbz2)    printf '%s\t%s\n' "${base%.*}" "tbz2" ;;
        *.tbz)     printf '%s\t%s\n' "${base%.*}" "tbz" ;;
        *.txz)     printf '%s\t%s\n' "${base%.*}" "txz" ;;
        *.tar)     printf '%s\t%s\n' "${base%.*}" "tar" ;;
        *.zip)     printf '%s\t%s\n' "${base%.*}" "zip" ;;
        *.7z)      printf '%s\t%s\n' "${base%.*}" "7z" ;;
        *.rar)     printf '%s\t%s\n' "${base%.*}" "rar" ;;
        *)         printf '%s\t%s\n' "${base}" "" ;;
    esac
}

# Appends -1, -2, ... before the extension until the path doesn't exist.
_unique_path() {
    local path="$1" dir base stem ext n=1 candidate="$1"
    dir=$(dirname "$path")
    base=$(basename "$path")
    IFS=$'\t' read -r stem ext <<< "$(_split_archive_name "$base")"
    while [ -e "$candidate" ]; do
        if [ -n "$ext" ]; then
            candidate="${dir}/${stem}-${n}.${ext}"
        else
            candidate="${dir}/${stem}-${n}"
        fi
        n=$((n + 1))
    done
    echo "$candidate"
}

_extract_one() {
    local archive="$1" destdir="$2" base ext
    base=$(basename "$archive")
    IFS=$'\t' read -r _ ext <<< "$(_split_archive_name "$base")"

    mkdir -p "$destdir" || return 1

    case "$ext" in
        zip)          unzip -q -o -- "$archive" -d "$destdir" ;;
        tar)          tar xf "$archive" -C "$destdir" ;;
        tar.gz|tgz)   tar xzf "$archive" -C "$destdir" ;;
        tar.bz2|tbz2|tbz) tar xjf "$archive" -C "$destdir" ;;
        tar.xz|txz)   tar xJf "$archive" -C "$destdir" ;;
        7z)
            command -v 7z &>/dev/null || { _notify "7z not installed (install p7zip)"; return 1; }
            7z x -y -o"$destdir" -- "$archive" >/dev/null
            ;;
        rar)
            if command -v unrar &>/dev/null; then
                unrar x -y -- "$archive" "${destdir}/" >/dev/null
            elif command -v 7z &>/dev/null; then
                7z x -y -o"$destdir" -- "$archive" >/dev/null
            else
                _notify "No tool to extract .rar (install unrar or p7zip)"
                return 1
            fi
            ;;
        *)
            _notify "Unknown archive format: $base"
            return 1
            ;;
    esac
}

_extract_menu() {
    local paths=("$@")
    local form action destbase
    form=$(yad --form --title="Archive" --text="Extract ${#paths[@]} archive(s)" \
        --field="Action":CB "Extract Here!Extract to the folder below" \
        --field="Destination folder (only used for 'Extract to')":TEXT "$(dirname "${paths[0]}")" \
        --width=480 \
        --button="Cancel:1" --button="Extract:0")
    [ $? -ne 0 ] && exit 0

    IFS='|' read -r action destbase _ <<< "$form"

    if [ "$action" = "Extract Here" ]; then
        destbase=""
    else
        [ -z "$destbase" ] && exit 0
        mkdir -p "$destbase" || { _notify "Could not create $destbase"; exit 1; }
    fi

    local ok=0
    for p in "${paths[@]}"; do
        local base stem
        base=$(basename "$p")
        IFS=$'\t' read -r stem _ <<< "$(_split_archive_name "$base")"

        local parent="$destbase"
        [ -z "$parent" ] && parent=$(dirname "$p")

        local destdir
        destdir=$(_unique_path "${parent}/${stem}")

        if _extract_one "$p" "$destdir"; then
            ok=$((ok + 1))
        fi
    done

    _notify "Extracted ${ok}/${#paths[@]} archive(s)"
}

_compress_menu() {
    local paths=("$@")
    local fmt_options="zip!tar.gz!tar.xz"
    command -v 7z &>/dev/null && fmt_options+="!7z"

    local outdir default_name
    outdir=$(dirname "${paths[0]}")
    if [ ${#paths[@]} -eq 1 ]; then
        default_name=$(basename "${paths[0]}")
        default_name="${default_name%.*}"
    else
        default_name=$(basename "$outdir")
    fi
    [ -z "$default_name" ] && default_name="Archive"

    local form fmt name
    form=$(yad --form --title="Archive" --text="Compress ${#paths[@]} item(s)" \
        --field="Format":CB "$fmt_options" \
        --field="Archive name (no extension)":TEXT "$default_name" \
        --width=420 \
        --button="Cancel:1" --button="Compress:0")
    [ $? -ne 0 ] && exit 0

    IFS='|' read -r fmt name _ <<< "$form"
    [ -z "$name" ] && exit 0

    local outfile
    outfile=$(_unique_path "${outdir}/${name}.${fmt}")

    local bases=()
    for p in "${paths[@]}"; do
        bases+=("$(basename "$p")")
    done

    _notify "Compressing to $(basename "$outfile")…" 1500

    local rc=1
    case "$fmt" in
        zip)
            (cd "$outdir" && zip -rq "$outfile" -- "${bases[@]}")
            rc=$?
            ;;
        tar.gz)
            tar czf "$outfile" -C "$outdir" -- "${bases[@]}"
            rc=$?
            ;;
        tar.xz)
            tar cJf "$outfile" -C "$outdir" -- "${bases[@]}"
            rc=$?
            ;;
        7z)
            command -v 7z &>/dev/null || { _notify "7z not installed (install p7zip)"; exit 1; }
            (cd "$outdir" && 7z a "$outfile" -- "${bases[@]}" >/dev/null)
            rc=$?
            ;;
    esac

    if [ "$rc" -eq 0 ] && [ -e "$outfile" ]; then
        _notify "Created $(basename "$outfile")"
    else
        _notify "Failed to create $(basename "$outfile")"
        rm -f "$outfile"
    fi
}

paths=("$@")

if [ ${#paths[@]} -eq 0 ]; then
    _notify "No files selected"
    exit 1
fi

all_archives=true
for p in "${paths[@]}"; do
    if ! _is_archive "$p"; then
        all_archives=false
        break
    fi
done

if $all_archives; then
    _extract_menu "${paths[@]}"
else
    _compress_menu "${paths[@]}"
fi
