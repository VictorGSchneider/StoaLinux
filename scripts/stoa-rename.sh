#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Stoatools Rename                               ║
# ║  Batch rename files with regex and preview                   ║
# ║  Requires: yad                                               ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-rename *.jpg               — rename with interactive menu
#   stoa-rename -f "old" -r "new" *.jpg  — direct without menu
#   stoa-rename -f "\.jpeg$" -r ".jpg" -R ~/Photos  — recursive

_usage() {
    cat <<EOF
Usage: stoa-rename [options] [files...]

Options:
  -f PATTERN    Regex pattern to search
  -r REPLACE    Replacement string
  -R DIR        Recursive mode (all files in directory)
  -i            Case insensitive
  -g            Replace all occurrences (global)
  -n            Dry run (show only, don't rename)
  -h            Show this help

Examples:
  stoa-rename *.jpg                        Interactive menu
  stoa-rename -f "IMG_" -r "photo_" *.jpg  Direct
  stoa-rename -f "\d+" -r "001" -i *.png   Case insensitive
  stoa-rename -f "\.jpeg$" -r ".jpg" -R .  Recursive
EOF
}

FIND_PATTERN=""
REPLACE_STR=""
RECURSIVE_DIR=""
CASE_FLAG=""
GLOBAL_FLAG=""
DRY_RUN=false

while getopts "f:r:R:ignh" opt; do
    case $opt in
        f) FIND_PATTERN="$OPTARG" ;;
        r) REPLACE_STR="$OPTARG" ;;
        R) RECURSIVE_DIR="$OPTARG" ;;
        i) CASE_FLAG="I" ;;
        g) GLOBAL_FLAG="g" ;;
        n) DRY_RUN=true ;;
        h) _usage; exit 0 ;;
        *) _usage; exit 1 ;;
    esac
done
shift $((OPTIND - 1))

# Collect files
files=()
if [ -n "$RECURSIVE_DIR" ]; then
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$RECURSIVE_DIR" -type f -print0 | sort -z)
elif [ $# -gt 0 ]; then
    for f in "$@"; do
        [ -f "$f" ] && files+=("$f")
    done
fi

if [ ${#files[@]} -eq 0 ]; then
    notify-send -t 3000 "Stoatools Rename" "No files selected"
    echo "No files selected."
    exit 1
fi

# Interactive form if -f was not passed
if [ -z "$FIND_PATTERN" ]; then
    form=$(yad --form --title="Stoatools Rename" --text="Rename ${#files[@]} file(s)" \
        --field="Find (regex)":TEXT "" \
        --field="Replace with":TEXT "" \
        --field="Case insensitive":CHK FALSE \
        --field="Replace all occurrences (global)":CHK FALSE \
        --field="Dry run (preview only)":CHK FALSE \
        --width=420 \
        --button="Cancel:1" --button="Continue:0")
    [ $? -ne 0 ] && exit 0

    IFS='|' read -r FIND_PATTERN REPLACE_STR case_chk global_chk dryrun_chk _ <<< "$form"
    [ -z "$FIND_PATTERN" ] && exit 0
    # REPLACE_STR can be empty (delete match)

    [ "$case_chk" = "TRUE" ] && CASE_FLAG="I"
    [ "$global_chk" = "TRUE" ] && GLOBAL_FLAG="g"
    [ "$dryrun_chk" = "TRUE" ] && DRY_RUN=true
fi

# Build sed flags
SED_FLAGS="${CASE_FLAG}${GLOBAL_FLAG}"

# Preview changes
preview=""
changes=0
declare -A rename_map

for f in "${files[@]}"; do
    dir=$(dirname "$f")
    old_name=$(basename "$f")
    # Use SOH (\x01) as sed delimiter — safe against `|` inside user regex
    # alternation like `(foo|bar)`, which would otherwise break the s command.
    new_name=$(printf '%s' "$old_name" | sed -E $'s\x01'"${FIND_PATTERN}"$'\x01'"${REPLACE_STR}"$'\x01'"${SED_FLAGS}")

    if [ "$old_name" != "$new_name" ]; then
        preview+="${old_name}  →  ${new_name}"$'\n'
        rename_map["$f"]="${dir}/${new_name}"
        ((changes++))
    fi
done

if [ $changes -eq 0 ]; then
    notify-send -t 3000 "Stoatools Rename" "No files match the pattern"
    exit 0
fi

# Show preview
if $DRY_RUN; then
    echo "$preview"
    echo "---"
    echo "$changes file(s) would be renamed (dry run)"
    yad --text-info --title="Stoatools Rename (dry run)" \
        --text="$changes file(s) would be renamed:" \
        --width=600 --height=350 --button="Close:1" <<< "$preview"
    exit 0
fi

# Confirmation
yad --text-info --title="Stoatools Rename" \
    --text="$changes file(s) will be renamed:" \
    --width=600 --height=350 \
    --button="Cancel:1" --button="Rename $changes file(s):0" <<< "$preview"

if [ $? -ne 0 ]; then
    exit 0
fi

# Execute rename
renamed=0
for src in "${!rename_map[@]}"; do
    dst="${rename_map[$src]}"
    if [ -e "$dst" ]; then
        notify-send -t 3000 "Stoatools Rename" "Conflict: $(basename "$dst") already exists, skipping"
        continue
    fi
    mv -- "$src" "$dst" && ((renamed++))
done

notify-send -t 3000 "Stoatools Rename" "${renamed}/${changes} file(s) renamed"
