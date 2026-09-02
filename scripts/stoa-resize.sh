#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Image Resizer                                 ║
# ║  Resize multiple images at once                              ║
# ║  Requires: imagemagick, yad                                 ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage:
#   stoa-resize img1.png img2.jpg ...   — resize with menu
#   stoa-resize *.png                   — glob works too

# Require ImageMagick 7 (`magick`). Legacy `convert` differs in resize syntax.
if ! command -v magick &>/dev/null; then
    echo "stoa-resize: ImageMagick 7 (magick) not found in PATH"
    notify-send -t 3000 "Image Resizer" "ImageMagick 7 (magick) not installed"
    exit 1
fi

if ! command -v yad &>/dev/null; then
    echo "stoa-resize: 'yad' not found in PATH" >&2
    notify-send -t 5000 "Image Resizer" "yad not installed.\nInstall: sudo pacman -S yad"
    exit 1
fi

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

PRESETS="25%   — Thumbnail!50%   — Half!75%   — Three quarters!1920x1080 — Full HD!1280x720  — HD!800x600   — Small!640x480   — Web!Custom (use field below)"
DESTINATIONS="Overwrite originals!Save as copy (_resized)!Save to resized/ folder"

form=$(yad --form --title="Image Resizer" --text="Resize ${#images[@]} image(s)" \
    --field="Preset":CB "$PRESETS" \
    --field="Custom size (e.g. 800x600 or 50%)":TEXT "" \
    --field="Destination":CB "$DESTINATIONS" \
    --width=420 \
    --button="Cancel:1" --button="Resize:0")
[ $? -ne 0 ] && exit 0

IFS='|' read -r preset custom dest _ <<< "$form"

if [ -n "$custom" ]; then
    size="$custom"
else
    size=$(echo "$preset" | awk '{print $1}')
fi
[ -z "$size" ] && exit 0
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
