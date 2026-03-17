#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Stoatools (Thunar integration)                ║
# ║  Right-click menu for Thunar custom actions                 ║
# ║  Requires: rofi                                             ║
# ╚══════════════════════════════════════════════════════════════╝
#
# Usage (called by Thunar uca.xml):
#   stoa-thunar file1 [file2 ...]

ROFI_ARGS=(-dmenu -config ~/.config/rofi/config.rasi)

if [ $# -eq 0 ]; then
    notify-send -t 3000 "Stoatools" "No files selected"
    exit 1
fi

files=("$@")
count=${#files[@]}
first="${files[0]}"
is_image=false

# Check if first file is an image
if file --mime-type -b "$first" 2>/dev/null | grep -q "^image/"; then
    is_image=true
fi

# Build menu based on file types
menu=""
menu+="  Rename — batch rename with regex\n"
menu+="  Locksmith — find who is using this file\n"

if $is_image; then
    menu+="  Resize — resize images with presets\n"
    menu+="  OCR — extract text from image\n"
fi

choice=$(printf "$menu" | rofi "${ROFI_ARGS[@]}" -p "Stoatools ($count file(s))")
[ -z "$choice" ] && exit 0

case "$choice" in
    *Rename*)
        ~/.local/bin/stoa-rename "${files[@]}"
        ;;
    *Locksmith*)
        ~/.local/bin/stoa-locksmith "$first"
        ;;
    *Resize*)
        ~/.local/bin/stoa-resize "${files[@]}"
        ;;
    *OCR*)
        ~/.local/bin/stoa-ocr "$first"
        ;;
esac
