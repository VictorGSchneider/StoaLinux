#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  STOA LINUX — Wallpaper Generator                           ║
# ║  Generates minimalist wallpapers with the Stoic palette      ║
# ║  Requires: imagemagick                                       ║
# ╚══════════════════════════════════════════════════════════════╝

WALLDIR="${HOME}/.config/stoa/wallpapers"
mkdir -p "$WALLDIR"

WIDTH=1920
HEIGHT=1080

# Use ImageMagick 7 (`magick`) when available, fall back to IM6 (`convert`).
# The rectangle/gradient/CLUT syntax we use below is identical in both.
if command -v magick &>/dev/null; then
    IM=(magick)
elif command -v convert &>/dev/null; then
    IM=(convert)
else
    echo "stoa-walls: ImageMagick not found (neither 'magick' nor 'convert')." >&2
    echo "            Install: sudo pacman -S imagemagick" >&2
    exit 1
fi

# Pick a usable mono font for the 'memento' wallpaper. ImageMagick matches
# fontconfig families: 'JetBrains Mono' (space) is the canonical name; the
# hyphenated form some docs show is not always resolved. Fall back gracefully.
_pick_font() {
    local candidates=("JetBrains Mono" "JetBrainsMono-Regular" "JetBrains-Mono" \
                      "DejaVu Sans Mono" "DejaVu-Sans-Mono" "monospace")
    for f in "${candidates[@]}"; do
        if "${IM[@]}" -list font 2>/dev/null | grep -qiE "^[[:space:]]*(Font:[[:space:]]*)?${f}\$"; then
            echo "$f"; return
        fi
    done
    # Last resort: let IM pick its default
    echo ""
}
FONT=$(_pick_font)

echo "Generating Stoic wallpapers..."

# 1. Marble — subtle gradient
"${IM[@]}" -size ${WIDTH}x${HEIGHT} \
    gradient:"#2d2921-#1a1714" \
    -blur 0x2 \
    "$WALLDIR/marble.png"
echo "  [+] marble.png"

# 2. Parchment — warm tone
"${IM[@]}" -size ${WIDTH}x${HEIGHT} \
    gradient:"#211e19-#1a1714" \
    -fill "#c49a5c" -draw "rectangle 0,$((HEIGHT/2-1)),${WIDTH},$((HEIGHT/2+1))" \
    -blur 0x40 \
    "$WALLDIR/parchment.png"
echo "  [+] parchment.png"

# 3. Columns — minimalist vertical lines
"${IM[@]}" -size ${WIDTH}x${HEIGHT} \
    xc:"#1a1714" \
    -fill "#2d2921" \
    -draw "rectangle $((WIDTH/2-60)),0,$((WIDTH/2-58)),${HEIGHT}" \
    -draw "rectangle $((WIDTH/2-30)),0,$((WIDTH/2-28)),${HEIGHT}" \
    -draw "rectangle $((WIDTH/2)),0,$((WIDTH/2+2)),${HEIGHT}" \
    -draw "rectangle $((WIDTH/2+30)),0,$((WIDTH/2+32)),${HEIGHT}" \
    -draw "rectangle $((WIDTH/2+60)),0,$((WIDTH/2+62)),${HEIGHT}" \
    "$WALLDIR/columns.png"
echo "  [+] columns.png"

# 4. Minimalist with text
memento_args=(-size ${WIDTH}x${HEIGHT} xc:"#1a1714" -gravity center)
[ -n "$FONT" ] && memento_args+=(-font "$FONT")
memento_args+=(-pointsize 18 -fill "#4a4540" -annotate +0+0 "MEMENTO MORI" "$WALLDIR/memento.png")
"${IM[@]}" "${memento_args[@]}"
echo "  [+] memento.png"

echo ""
echo "Wallpapers saved to: $WALLDIR"
echo ""
echo "Apply:"
echo "  Hyprland (Wayland): swaybg -i $WALLDIR/marble.png -m fill"
echo "  i3 (Xorg):          feh --bg-fill $WALLDIR/marble.png"
