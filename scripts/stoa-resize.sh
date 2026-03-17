#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Image Resizer                                 ║
# ║  Resize multiple images at once                              ║
# ║  Requires: imagemagick, rofi                                ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-resize img1.png img2.jpg ...   — resize with menu
#   stoa-resize *.png                   — glob works too

ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

PRESETS=(
    "25%   — Thumbnail"
    "50%   — Half"
    "75%   — Three quarters"
    "1920x1080 — Full HD"
    "1280x720  — HD"
    "800x600   — Small"
    "640x480   — Web"
    "Custom..."
)

if [ $# -eq 0 ]; then
    echo "Usage: stoa-resize image1 [image2 ...]"
    notify-send -t 3000 "Image Resizer" "Usage: stoa-resize image1 [image2 ...]"
    exit 1
fi

# Filter valid image files only
images=()
for f in "$@"; do
    if [ -f "$f" ] && file --mime-type -b "$f" | grep -q "^image/"; then
        images+=("$f")
    fi
done

if [ ${#images[@]} -eq 0 ]; then
    notify-send -t 3000 "Image Resizer" "No valid images found"
    exit 1
fi

# Size menu
choice=$(printf '%s\n' "${PRESETS[@]}" | rofi "${ROFI_ARGS[@]}" -p "Resize ${#images[@]} image(s)")
[ -z "$choice" ] && exit 0

# Extract dimension
if [[ "$choice" == "Custom..."* ]]; then
    size=$(rofi "${ROFI_ARGS[@]}" -p "Size (e.g. 800x600 or 50%)")
    [ -z "$size" ] && exit 0
else
    size=$(echo "$choice" | awk '{print $1}')
fi

# Destination menu
dest=$(printf "Overwrite originals\nSave as copy (_resized)\nSave to resized/ folder" | \
    rofi "${ROFI_ARGS[@]}" -p "Destination")
[ -z "$dest" ] && exit 0

count=0
for img in "${images[@]}"; do
    dir=$(dirname "$img")
    base=$(basename "$img")
    name="${base%.*}"
    ext="${base##*.}"

    case "$dest" in
        "Overwrite"*)
            magick "$img" -resize "$size" "$img"
            ;;
        "Save as copy"*)
            magick "$img" -resize "$size" "${dir}/${name}_resized.${ext}"
            ;;
        "Save to"*)
            mkdir -p "${dir}/resized"
            magick "$img" -resize "$size" "${dir}/resized/${base}"
            ;;
    esac
    ((count++))
done

notify-send -t 3000 "Image Resizer" "${count} image(s) resized to ${size}"
