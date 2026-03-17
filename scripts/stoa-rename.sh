#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Stoatools Rename                               ║
# ║  Batch rename files with regex and preview                   ║
# ║  Requires: rofi                                              ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-rename *.jpg               — rename with interactive menu
#   stoa-rename -f "old" -r "new" *.jpg  — direct without menu
#   stoa-rename -f "\.jpeg$" -r ".jpg" -R ~/Photos  — recursive

ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

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

# Interactive menu if -f was not passed
if [ -z "$FIND_PATTERN" ]; then
    FIND_PATTERN=$(rofi "${ROFI_ARGS[@]}" -p "Find (regex)")
    [ -z "$FIND_PATTERN" ] && exit 0

    REPLACE_STR=$(rofi "${ROFI_ARGS[@]}" -p "Replace with")
    # REPLACE_STR can be empty (delete match)

    opts=$(printf "Apply rename\nCase insensitive\nReplace all (global)\nDry run (preview only)" | \
        rofi "${ROFI_ARGS[@]}" -p "Options" -multi-select)

    [[ "$opts" == *"Case insensitive"* ]] && CASE_FLAG="I"
    [[ "$opts" == *"all"* ]] && GLOBAL_FLAG="g"
    [[ "$opts" == *"Dry run"* ]] && DRY_RUN=true
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
    new_name=$(echo "$old_name" | sed -E "s/${FIND_PATTERN}/${REPLACE_STR}/${SED_FLAGS}")

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
    notify-send -t 5000 "Stoatools Rename" "Dry run: $changes file(s)\n(see terminal)"
    exit 0
fi

# Confirmation via rofi
confirm=$(printf "Rename %d file(s)\nCancel" "$changes" | \
    rofi "${ROFI_ARGS[@]}" -p "Preview" -mesg "$(echo "$preview" | head -20)")

if [[ "$confirm" != "Rename"* ]]; then
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
